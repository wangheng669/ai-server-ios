#!/usr/bin/env python3
"""Build and publish 焦点 for the device in the local direct-install configuration."""

import argparse
import fcntl
import hashlib
import json
import os
import plistlib
import re
import secrets
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit


PROJECT = Path(__file__).resolve().parent.parent
BUNDLE_ID = "com.wangheng.aiserverclient"
CONFIG = Path.home() / ".local/share/focus-direct-install/config.json"
WORK_ROOT = Path.home() / ".cache/ai-server-ios"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def version_key(version, build):
    require(re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", version), "Invalid marketing version")
    parts = tuple(map(int, version.split(".")))
    require(build > 0, "Build number must be positive")
    return parts + (0,) * (3 - len(parts)) + (build,)


def command(args, **options):
    return subprocess.run(args, check=True, **options)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for block in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def fetch(url, path, status=200, byte_range=None):
    args = ["curl", "-fsS", "--max-time", "90", "-o", str(path), "-w", "%{http_code}"]
    if byte_range:
        args += ["--range", byte_range]
    result = command(args + [url], capture_output=True, text=True)
    require(result.stdout == str(status), f"Expected HTTP {status}, got {result.stdout}")


def build_app(work, config, entry_url, version, build):
    source = work / "source"
    source.mkdir()
    snapshot = work / "source.tar"
    command(["git", "archive", "--output", str(snapshot), "HEAD"], cwd=PROJECT)
    command(["tar", "-xf", str(snapshot), "-C", str(source)])
    snapshot.unlink()

    info_path = source / "Config/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info["CFBundleShortVersionString"] = version
    info["CFBundleVersion"] = str(build)
    info["FocusDirectInstallURL"] = entry_url
    info_path.write_bytes(plistlib.dumps(info))

    archive = work / "AIServerClient.xcarchive"
    log_path = work / "archive.log"
    with log_path.open("wb") as log:
        command([
            "xcodebuild", "archive", "-project", "AIServerClient.xcodeproj", "-scheme", "AIServerClient",
            "-configuration", "Release", "-destination", "generic/platform=iOS", "-archivePath", str(archive),
            "-derivedDataPath", str(work / "DerivedData"), f"DEVELOPMENT_TEAM={config['team_id']}",
            "CODE_SIGN_STYLE=Automatic", "COMPILER_INDEX_STORE_ENABLE=NO",
            f"MARKETING_VERSION={version}", f"CURRENT_PROJECT_VERSION={build}",
        ], cwd=source, stdout=log, stderr=subprocess.STDOUT)
    return archive, source / "AIClient/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"


def export_app(work, config, archive, assets):
    options = work / "ExportOptions.plist"
    options.write_bytes(plistlib.dumps({
        "destination": "export",
        "method": "debugging",
        "signingStyle": "automatic",
        "stripSwiftSymbols": True,
        "teamID": config["team_id"],
        "manifest": {
            "appURL": assets["software-package"],
            "displayImageURL": assets["display-image"],
            "fullSizeImageURL": assets["full-size-image"],
        },
    }))
    export = work / "export"
    with (work / "export.log").open("wb") as log:
        command([
            "xcodebuild", "-exportArchive", "-archivePath", str(archive),
            "-exportOptionsPlist", str(options), "-exportPath", str(export),
        ], stdout=log, stderr=subprocess.STDOUT)
    ipa, = export.glob("*.ipa")
    return ipa, export / "manifest.plist"


def verify_app(work, ipa, config, entry_url, version, build):
    verification = work / "verify-ipa"
    verification.mkdir()
    command(["ditto", "-x", "-k", str(ipa), str(verification)])
    app, = (verification / "Payload").glob("*.app")
    command(["codesign", "--verify", "--deep", "--strict", str(app)])
    extensions = sorted((app / "PlugIns").glob("*.appex"))
    require(len(extensions) == 2, "Expected both notification extensions")
    expiry = []
    for component in [app, *extensions]:
        info = plistlib.loads((component / "Info.plist").read_bytes())
        require((info["CFBundleShortVersionString"], info["CFBundleVersion"]) == (version, str(build)),
                f"Version mismatch in {component.name}")
        profile = plistlib.loads(command(
            ["security", "cms", "-D", "-i", str(component / "embedded.mobileprovision")],
            capture_output=True,
        ).stdout)
        require(profile["ProvisionedDevices"] == [config["device_udid"]],
                f"Unexpected device list in {component.name}")
        require(profile["TeamIdentifier"] == [config["team_id"]], f"Unexpected team in {component.name}")
        expiry.append(profile["ExpirationDate"].replace(tzinfo=timezone.utc))
        if component == app:
            require(info["CFBundleIdentifier"] == BUNDLE_ID, "Unexpected app identifier")
            require(info["FocusDirectInstallURL"] == entry_url, "The app must open the fixed install page")
            require(profile["Entitlements"]["aps-environment"] == "development", "Unexpected push environment")
    require(min(expiry) > datetime.now(timezone.utc), "The device profiles have expired")


INSTALL_PAGE = """<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex,nofollow,noarchive">
<meta name="referrer" content="no-referrer">
<title>安装焦点AI</title>
<style>
body{font:17px -apple-system,system-ui,sans-serif;margin:0 auto;padding:48px 24px;max-width:400px;color:#161616;background:#f6f7f8}
img{border-radius:17px}
a{display:block;text-align:center;padding:15px 18px;border-radius:14px;background:#005bd1;color:#fff;text-decoration:none;font-weight:600}
[hidden]{display:none}
@media(prefers-color-scheme:dark){body{background:#17181b;color:#fafafa}}
</style></head>
<body><main>
<img id="icon" alt="" width="70" height="70" hidden>
<h1>焦点AI</h1><p id="status" role="status">正在查询最新版本…</p>
<a id="install" hidden>安装最新版</a>
</main>
<script>
const status = document.getElementById("status");
const install = document.getElementById("install");
const icon = document.getElementById("icon");
window.addEventListener("pageshow", async () => {
  install.hidden = true;
  status.textContent = "正在查询最新版本…";
  try {
    const response = await fetch("latest.json?open=" + crypto.randomUUID(), {cache: "no-store"});
    if (!response.ok) throw new Error("Latest build unavailable");
    const latest = await response.json();
    if (!/^build-[0-9.]+-[0-9]+-[0-9a-f]{16}$/.test(latest.package)) {
      throw new Error("Invalid package path");
    }
    const base = new URL(latest.package + "/", window.location.href);
    const manifest = new URL("manifest.plist", base);
    install.href = "itms-services://?action=download-manifest&url=" + encodeURIComponent(manifest.href);
    icon.src = new URL("icon-57.png", base).href;
    icon.hidden = false;
    status.textContent = "最新版 " + latest.version + "（" + latest.build + "）";
    install.hidden = false;
  } catch {
    status.textContent = "暂时无法读取最新版本，请稍后重试。";
  }
});
</script></body></html>""".encode("utf-8")


def write_atomic(path, content):
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as staged:
        staged.write(content)
    try:
        os.replace(staged.name, path)
    finally:
        Path(staged.name).unlink(missing_ok=True)


def publish(work, channel, entry_url, package, base, assets, ipa, manifest_path, icon, version, build):
    item, = plistlib.loads(manifest_path.read_bytes())["items"]
    require(item["metadata"]["bundle-identifier"] == BUNDLE_ID, "Manifest app identifier differs")
    require(item["metadata"]["bundle-version"] == version, "Manifest version differs")
    require({asset["kind"]: asset["url"] for asset in item["assets"]} == assets, "Manifest URLs differ")

    page = channel / "install.html"
    latest = channel / "latest.json"
    previous = latest.read_bytes() if latest.exists() else None
    content = json.dumps({"version": version, "build": build, "package": package.name}).encode()
    stage = Path(tempfile.mkdtemp(prefix=".staging-", dir=channel))
    package_available = False
    promoted = False
    try:
        shutil.copyfile(ipa, stage / "Focus.ipa")
        shutil.copyfile(manifest_path, stage / "manifest.plist")
        for size in (57, 512):
            command(["sips", "-z", str(size), str(size), str(icon), "--out", str(stage / f"icon-{size}.png")],
                    stdout=subprocess.DEVNULL)
        stage.rename(package)
        package_available = True
        manifest_readback = work / "public-manifest.plist"
        fetch(base + "manifest.plist", manifest_readback)
        require(manifest_readback.read_bytes() == manifest_path.read_bytes(), "Public manifest differs")
        fetch(base + "Focus.ipa", work / "first-byte", status=206, byte_range="0-0")
        require((work / "first-byte").stat().st_size == 1, "IPA byte range differs")
        fetch(base + "Focus.ipa", work / "public.ipa")
        require(sha256(work / "public.ipa") == sha256(ipa), "Public IPA differs")
        for size in (57, 512):
            image = f"icon-{size}.png"
            fetch(base + image, work / image)
            require(sha256(work / image) == sha256(package / image), "Public icon differs")
        if not page.exists() or page.read_bytes() != INSTALL_PAGE:
            write_atomic(page, INSTALL_PAGE)
        fetch(entry_url + "?check=" + secrets.token_hex(8), work / "public-install.html")
        require((work / "public-install.html").read_bytes() == INSTALL_PAGE, "Public install page differs")
        write_atomic(latest, content)
        promoted = True
        fetch(entry_url.rsplit("/", 1)[0] + "/latest.json?check=" + secrets.token_hex(8), work / "public-latest.json")
        require((work / "public-latest.json").read_bytes() == content, "Public latest version differs")
    except BaseException:
        if promoted:
            if previous is None:
                latest.unlink()
            else:
                write_atomic(latest, previous)
        shutil.rmtree(package if package_available else stage)
        raise


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True, type=int)
    args = parser.parse_args()
    target_version = version_key(args.version, args.build)
    require(not CONFIG.stat().st_mode & 0o077, "Direct-install configuration must be private")
    config = json.loads(CONFIG.read_text())
    origin = urlsplit(config["public_origin"])
    require(origin.scheme == "https" and origin.hostname and not origin.username
            and not origin.path and not origin.query and not origin.fragment, "Expected a public HTTPS origin")
    channel_name = config["channel"]
    require(re.fullmatch(r"focus-update-[a-f0-9]{48}", channel_name), "Invalid private channel path")
    channel = Path(config["public_img_root"]).resolve(strict=True) / channel_name
    entry_url = f"{config['public_origin']}/img/{channel_name}/install.html"
    with CONFIG.with_suffix(".lock").open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        require(not command(["git", "status", "--porcelain"], cwd=PROJECT, capture_output=True).stdout,
                "Commit the intended source in a clean worktree first")
        require(not channel.is_symlink(), "Direct-install channel must be a real directory")
        channel.mkdir(exist_ok=True)
        latest = channel / "latest.json"
        if latest.exists():
            current = json.loads(latest.read_bytes())
            require(target_version > version_key(current["version"], current["build"]),
                    "The direct-install page already serves this build or a newer one")
        WORK_ROOT.mkdir(exist_ok=True, parents=True)
        work = Path(tempfile.mkdtemp(prefix="focus-direct-", dir=WORK_ROOT))
        print(f"Building {args.version} ({args.build}). Logs: {work}", flush=True)
        archive, icon = build_app(work, config, entry_url, args.version, args.build)
        package = channel / f"build-{args.version}-{args.build}-{secrets.token_hex(8)}"
        base = f"{config['public_origin']}/img/{channel_name}/{package.name}/"
        assets = {kind: base + file for kind, file in {
            "software-package": "Focus.ipa", "display-image": "icon-57.png", "full-size-image": "icon-512.png",
        }.items()}
        ipa, manifest = export_app(work, config, archive, assets)
        verify_app(work, ipa, config, entry_url, args.version, args.build)
        publish(work, channel, entry_url, package, base, assets, ipa, manifest, icon, args.version, args.build)
        print(f"Published {args.version} ({args.build}): {entry_url}", flush=True)


if __name__ == "__main__":
    main()
