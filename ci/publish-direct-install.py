#!/usr/bin/env python3
"""Prepare or publish an Ad Hoc build of 焦点 for the registered iPhone."""

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
from zipfile import ZIP_DEFLATED, ZipFile


PROJECT = Path(__file__).resolve().parent.parent
BUNDLE_ID = "com.wangheng.aiserverclient"
CONFIG = Path.home() / ".local/share/focus-direct-install/config.json"
WORK_ROOT = Path.home() / ".cache/ai-server-ios"
RECEIPT_ROOT = CONFIG.parent / "receipts"
ARCHIVE_NAME = "VerifiedAIServerClient.xcarchive.zip"
IPA_NAME = "Focus-AdHoc.ipa"
RECEIPT_NAME = "release.json"
SYMBOLS_NAME = "dSYMs.zip"


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


def build_app(work, config, entry_url, version, build, source_commit):
    source = work / "source"
    source.mkdir()
    snapshot = work / "source.tar"
    command(["git", "archive", "--output", str(snapshot), source_commit], cwd=PROJECT)
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
    return archive


def binary_uuids(path):
    output = command(["dwarfdump", "--uuid", path], capture_output=True, text=True).stdout
    return sorted(re.findall(r"^UUID: ([0-9A-Fa-f-]{36})", output, re.MULTILINE))


def app_binary_uuids(app, symbols=None):
    identifiers = {}
    for component in [app, *sorted((app / "PlugIns").glob("*.appex"))]:
        info = plistlib.loads((component / "Info.plist").read_bytes())
        name = info["CFBundleExecutable"]
        require(Path(name).name == name, "Invalid app executable name")
        uuids = binary_uuids(component / name)
        bundle = info["CFBundleIdentifier"]
        require(uuids and bundle not in identifiers, f"Missing or duplicate binary identity for {bundle}")
        if symbols is not None:
            dwarf = symbols / f"{component.name}.dSYM" / "Contents/Resources/DWARF" / name
            require(dwarf.is_file() and binary_uuids(dwarf) == uuids, f"Missing or mismatched dSYM for {bundle}")
        identifiers[bundle] = uuids
    return identifiers


def read_handoff(handoff, identity):
    require(handoff.is_dir() and not handoff.is_symlink() and handoff.stat().st_uid == os.getuid()
            and not (handoff.stat().st_mode & 0o077), "Release handoff must be a private owned directory")
    path = handoff / RECEIPT_NAME
    require(path.is_file() and not path.is_symlink(), "Release handoff receipt is missing")
    receipt = json.loads(path.read_bytes())
    require(receipt["identity"] == identity, "Build already prepared with a different source or release configuration")
    require(receipt["status"] == "prepared", "Release handoff receipt has invalid status")
    archive = handoff / ARCHIVE_NAME
    require(archive.is_file() and not archive.is_symlink() and sha256(archive) == receipt["archive_sha256"],
            "Prepared archive checksum differs")
    return receipt


def prepare_archive(config, entry_url, identity, handoff):
    if handoff.exists():
        receipt = read_handoff(handoff, identity)
    else:
        version, build = identity["version"], identity["build"]
        print(f"Building {version} ({build}) from {identity['source_commit']}", flush=True)
        with tempfile.TemporaryDirectory(prefix=".focus-adhoc-prepare.", dir=WORK_ROOT) as temp:
            work = Path(temp)
            stage = work / "handoff"
            stage.mkdir()
            try:
                archive = build_app(work, config, entry_url, version, build, identity["source_commit"])
                app = archive / "Products/Applications/AIServerClient.app"
                archive_zip = stage / ARCHIVE_NAME
                command(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", archive, archive_zip])
                receipt = {
                    "identity": identity,
                    "archive_sha256": sha256(archive_zip),
                    "binary_uuids": app_binary_uuids(app, archive / "dSYMs"),
                    "package": f"build-{version}-{build}-{secrets.token_hex(8)}",
                    "status": "prepared",
                }
                write_atomic(stage / RECEIPT_NAME, json.dumps(receipt, indent=2).encode())
                stage.rename(handoff)
            except BaseException:
                log = work / "archive.log"
                if log.is_file():
                    diagnostics = CONFIG.parent / "diagnostics"
                    diagnostics.mkdir(exist_ok=True)
                    saved = diagnostics / f"{handoff.name}-{identity['source_commit'][:12]}.log"
                    write_atomic(saved, log.read_bytes())
                    print(f"Build log: {saved}", flush=True)
                raise
    print(f"archive_path={handoff / ARCHIVE_NAME}")
    print(f"archive_sha256={receipt['archive_sha256']}")
    signed = handoff / IPA_NAME
    if signed.is_file() and not signed.is_symlink():
        print(f"signed_ipa={signed}")


def component_plist(args):
    return plistlib.loads(command(args, capture_output=True).stdout)


def verify_app(work, ipa, config, entry_url, version, build):
    verification = work / "verify-ipa"
    verification.mkdir()
    command(["ditto", "-x", "-k", ipa, verification])
    app, = (verification / "Payload").glob("*.app")
    command(["codesign", "--verify", "--deep", "--strict", app])
    extensions = sorted((app / "PlugIns").glob("*.appex"))
    expected_ids = {
        BUNDLE_ID,
        BUNDLE_ID + ".NotificationContentExtension",
        BUNDLE_ID + ".NotificationServiceExtension",
    }
    verified_ids = set()
    for index, component in enumerate([app, *extensions]):
        info = plistlib.loads((component / "Info.plist").read_bytes())
        bundle_id = info["CFBundleIdentifier"]
        require(bundle_id in expected_ids - verified_ids, f"Unexpected app identifier: {bundle_id}")
        verified_ids.add(bundle_id)
        require((info["CFBundleShortVersionString"], info["CFBundleVersion"]) == (version, str(build)),
                f"Version mismatch in {bundle_id}")
        profile = component_plist(["security", "cms", "-D", "-i", component / "embedded.mobileprovision"])
        signed = component_plist(["codesign", "-d", "--entitlements", ":-", component])
        allowed = profile["Entitlements"]
        require(profile["ProvisionedDevices"] == [config["device_udid"]],
                f"Unexpected device list in {bundle_id}")
        require(profile["TeamIdentifier"] == [config["team_id"]] and not profile.get("ProvisionsAllDevices"),
                f"Unexpected profile team or distribution type in {bundle_id}")
        require(profile["ExpirationDate"].replace(tzinfo=timezone.utc) > datetime.now(timezone.utc),
                f"Expired profile in {bundle_id}")
        app_id = config["team_id"] + "." + bundle_id
        for entitlements in (signed, allowed):
            require(entitlements.get("application-identifier") == app_id, f"Unexpected App ID in {bundle_id}")
            require(not entitlements.get("get-task-allow") and not entitlements.get("beta-reports-active"),
                    f"Expected Ad Hoc distribution in {bundle_id}")
        certificate_prefix = verification / f"certificate-{index}-"
        command(["codesign", "-d", f"--extract-certificates={certificate_prefix}", component],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        leaf = Path(str(certificate_prefix) + "0").read_bytes()
        require(leaf in profile["DeveloperCertificates"], f"Signing certificate is not in profile for {bundle_id}")
        if component == app:
            require(bundle_id == BUNDLE_ID, "Unexpected main application identifier")
            require(info["FocusDirectInstallURL"] == entry_url, "The app must open the fixed install page")
            require(signed.get("aps-environment") == allowed.get("aps-environment") == "production",
                    "Expected production push notifications for Ad Hoc distribution")
        print(f"Verified Ad Hoc signature and registered device: {bundle_id}", flush=True)
    require(verified_ids == expected_ids, "Expected both notification extensions")
    return app_binary_uuids(app)


def install_manifest(assets, version):
    return plistlib.dumps({"items": [{
        "assets": [{"kind": kind, "url": url} for kind, url in assets.items()],
        "metadata": {
            "bundle-identifier": BUNDLE_ID,
            "bundle-version": version,
            "kind": "software",
            "platform-identifier": "com.apple.platform.iphoneos",
            "title": "焦点",
        },
    }]})


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


def save_release_receipt(handoff, destination, receipt, ipa_sha256):
    published = dict(receipt, status="published", ipa_sha256=ipa_sha256)
    if destination.exists() or destination.is_symlink():
        record = destination / RECEIPT_NAME
        symbols = destination / SYMBOLS_NAME
        require(destination.is_dir() and not destination.is_symlink()
                and destination.stat().st_uid == os.getuid() and not (destination.stat().st_mode & 0o077)
                and record.is_file() and not record.is_symlink()
                and symbols.is_file() and not symbols.is_symlink(),
                "Release receipt must contain a private record and symbols")
        saved = json.loads(record.read_bytes())
        readback_at = saved.pop("public_readback_at", None)
        require(isinstance(readback_at, str) and readback_at
                and saved == dict(published, dsym_sha256=sha256(symbols)),
                "Saved release receipt differs from the published handoff")
        return

    archive_prefix = "AIServerClient.xcarchive/"
    published["public_readback_at"] = datetime.now(timezone.utc).isoformat()
    with tempfile.TemporaryDirectory(prefix=".staging-", dir=destination.parent) as staging:
        stage = Path(staging) / "receipt"
        stage.mkdir()
        symbols = stage / SYMBOLS_NAME
        with ZipFile(handoff / ARCHIVE_NAME) as archive, ZipFile(symbols, "w", ZIP_DEFLATED) as output:
            members = [info for info in archive.infolist()
                       if info.filename.startswith(archive_prefix + "dSYMs/") and not info.is_dir()]
            require(any("/Contents/Resources/DWARF/" in info.filename for info in members),
                    "No dSYM binaries in the prepared archive")
            for info in members:
                name = info.filename.removeprefix(archive_prefix)
                require(".." not in Path(name).parts, "Invalid dSYM path in the prepared archive")
                with archive.open(info) as source, output.open(name, "w") as target:
                    shutil.copyfileobj(source, target, 1024 * 1024)
        published["dsym_sha256"] = sha256(symbols)
        write_atomic(stage / RECEIPT_NAME, json.dumps(published, indent=2).encode())
        stage.rename(destination)


def publish(work, channel, entry_url, package, base, assets, ipa, manifest_path, icon, version, build):
    item, = plistlib.loads(manifest_path.read_bytes())["items"]
    require(item["metadata"]["bundle-identifier"] == BUNDLE_ID, "Manifest app identifier differs")
    require(item["metadata"]["bundle-version"] == version, "Manifest version differs")
    require({asset["kind"]: asset["url"] for asset in item["assets"]} == assets, "Manifest URLs differ")

    page = channel / "install.html"
    latest = channel / "latest.json"
    previous = latest.read_bytes() if latest.exists() else None
    content = json.dumps({"version": version, "build": build, "package": package.name}).encode()
    package_available = False
    promoted = False
    try:
        require(not package.is_symlink(), "Public package must be a real directory")
        if package.exists():
            require(package.is_dir()
                    and (package / "manifest.plist").read_bytes() == manifest_path.read_bytes()
                    and sha256(package / "Focus.ipa") == sha256(ipa),
                    "Existing package differs from the release handoff")
        else:
            with tempfile.TemporaryDirectory(prefix=".staging-", dir=channel) as staging:
                stage = Path(staging) / "package"
                stage.mkdir()
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
        if previous != content:
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
        if package_available:
            shutil.rmtree(package)
        raise


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True, type=int)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--prepare", action="store_true", help="Build the archive for the Ad Hoc signer")
    action.add_argument("--signed-ipa", type=Path, help="Verify and publish this signed Ad Hoc package")
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
        WORK_ROOT.mkdir(exist_ok=True, parents=True)
        require(WORK_ROOT.resolve() == WORK_ROOT and WORK_ROOT.stat().st_uid == os.getuid(),
                "Direct-install work root must be an owned directory")
        configuration = json.dumps([entry_url, config["team_id"], config["device_udid"]]).encode()
        commit = command(["git", "rev-parse", "HEAD"], cwd=PROJECT, capture_output=True, text=True).stdout.strip()
        identity = {
            "source_commit": commit,
            "version": args.version,
            "build": args.build,
            "configuration_sha256": hashlib.sha256(configuration).hexdigest(),
        }
        key = json.dumps([entry_url, target_version]).encode()
        handoff = WORK_ROOT / f"focus-adhoc-export.{hashlib.sha256(key).hexdigest()}"
        latest = channel / "latest.json"
        current = json.loads(latest.read_bytes()) if latest.exists() else None
        current_version = version_key(current["version"], current["build"]) if current else (0, 0, 0, 0)
        if args.prepare:
            require(target_version > current_version, "The direct-install page already serves this build or a newer one")
            prepare_archive(config, entry_url, identity, handoff)
            return

        ipa = handoff / IPA_NAME
        require(args.signed_ipa.absolute() == ipa and ipa.is_file() and not ipa.is_symlink(),
                "Use the signed IPA from this build's prepare handoff")
        receipt = read_handoff(handoff, identity)
        require({path.name for path in handoff.iterdir()} == {ARCHIVE_NAME, IPA_NAME, RECEIPT_NAME},
                "Release handoff contains unexpected files")
        package_name = receipt["package"]
        require(re.fullmatch(rf"build-{re.escape(args.version)}-{args.build}-[0-9a-f]{{16}}", package_name),
                "Invalid package identity in release receipt")
        require(target_version > current_version or (target_version == current_version and current
                and current["package"] == package_name), "The direct-install page already serves another build or a newer one")

        RECEIPT_ROOT.mkdir(mode=0o700, exist_ok=True)
        require(RECEIPT_ROOT.resolve() == RECEIPT_ROOT and RECEIPT_ROOT.stat().st_uid == os.getuid()
                and not (RECEIPT_ROOT.stat().st_mode & 0o077), "Release receipt storage must be private and owned")
        destination = RECEIPT_ROOT / package_name
        package = channel / package_name
        base = f"{config['public_origin']}/img/{channel_name}/{package_name}/"
        assets = {kind: base + file for kind, file in {
            "software-package": "Focus.ipa", "display-image": "icon-57.png", "full-size-image": "icon-512.png",
        }.items()}
        icon = PROJECT / "AIClient/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

        ipa_sha256 = sha256(ipa)
        with tempfile.TemporaryDirectory(prefix=".focus-adhoc-verify.", dir=WORK_ROOT) as temp:
            work = Path(temp)
            uuids = verify_app(work, ipa, config, entry_url, args.version, args.build)
            require(uuids == receipt["binary_uuids"], "Signed IPA binaries differ from the prepared archive")
            require(ipa_sha256 == sha256(ipa), "Signed IPA changed during verification")
            manifest = work / "manifest.plist"
            manifest.write_bytes(install_manifest(assets, args.version))
            publish(work, channel, entry_url, package, base, assets, ipa, manifest, icon, args.version, args.build)

        require(ipa_sha256 == sha256(ipa), "Signed IPA changed during public verification")
        save_release_receipt(handoff, destination, receipt, ipa_sha256)
        with tempfile.TemporaryDirectory(prefix=".focus-adhoc-finished.", dir=WORK_ROOT) as cleanup:
            handoff.rename(Path(cleanup) / "handoff")
        print(f"release_record={destination / RECEIPT_NAME}")
        print(f"Published {args.version} ({args.build}): {entry_url}", flush=True)



if __name__ == "__main__":
    main()
