#!/usr/bin/env python3
"""Build, sign and publish an Ad Hoc build of 焦点 for the configured devices."""

import argparse
import base64
import fcntl
import hashlib
import json
import os
import plistlib
import re
import secrets
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit
from zipfile import ZIP_DEFLATED, ZipFile


PROJECT = Path.home() / "Desktop/ai-server-ios"
GITHUB_REPO = "wangheng669/ai-server-ios"
SIGNING_WORKFLOW = "focus-adhoc.yml"
BUNDLE_ID = "com.wangheng.aiserverclient"
CONFIG = Path.home() / ".local/share/focus-direct-install/release-config.json"
LOCK = CONFIG.parent / "config.lock"
QUEUE_ROOT = CONFIG.parent / "queue"
QUEUE_DELAY = 90
QUEUE_MAX_DELAY = 180
WORK_ROOT = Path.home() / ".cache/ai-server-ios"
SCRATCH_ROOT = WORK_ROOT / "focus-direct-install-tmp"
RECEIPT_ROOT = CONFIG.parent / "receipts"
DIAGNOSTICS_ROOT = CONFIG.parent / "diagnostics"
ARCHIVE_NAME = "VerifiedAIServerClient.xcarchive.zip"
IPA_NAME = "Focus-AdHoc.ipa"
RECEIPT_NAME = "release.json"
SYMBOLS_NAME = "dSYMs.zip"
BUILD_PATHS = ("AIClient", "AIServerClient.xcodeproj", "Config", "NotificationContentExtension",
               "NotificationServiceExtension")
ICON_PATH = "AIClient/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"


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
    result = subprocess.run(args + [url], capture_output=True, text=True)
    require(result.returncode == 0 and result.stdout == str(status),
            f"Public readback failed (expected HTTP {status}, received {result.stdout or 'no response'})")


def git_output(*args):
    return command(["git", "-C", PROJECT, *args], capture_output=True).stdout


def private_directory(path):
    path.mkdir(mode=0o700, exist_ok=True)
    require(path.is_dir() and path.resolve() == path and path.stat().st_uid == os.getuid()
            and not (path.stat().st_mode & 0o077), f"Expected an owned private directory: {path}")


def free_bytes(path):
    info = os.statvfs(path)
    return info.f_bavail * info.f_frsize


@contextmanager
def scratch(stage):
    free_before = free_bytes(SCRATCH_ROOT)
    occupied = 0
    try:
        with tempfile.TemporaryDirectory(prefix=f"{stage}.", dir=SCRATCH_ROOT) as temp:
            path = Path(temp)
            try:
                yield path
            finally:
                result = subprocess.run(["du", "-sk", path], capture_output=True, text=True)
                if result.returncode == 0:
                    occupied = int(result.stdout.split()[0]) * 1024
    finally:
        print(f"storage stage={stage} scratch_bytes={occupied} available_before_bytes={free_before} "
              f"available_after_bytes={free_bytes(SCRATCH_ROOT)}", flush=True)


def prune_scratch(channel):
    cutoff = time.time() - 24 * 60 * 60
    roots = [(SCRATCH_ROOT, r"(prepare|sign|publish|finished)\."),
             (RECEIPT_ROOT, r"\.focus-receipt\."),
             (channel, r"\.focus-public\.")]
    candidates = [p for root, prefix in roots if root.is_dir() and root.resolve() == root
                  for p in root.iterdir() if re.fullmatch(prefix + r"[a-z0-9_]{8}", p.name)
                  and p.is_dir() and not p.is_symlink() and p.stat().st_uid == os.getuid()
                  and not (p.stat().st_mode & 0o077) and not p.is_mount() and p.stat().st_mtime < cutoff]
    if not candidates:
        return
    owner = command(["id", "-un"], capture_output=True, text=True).stdout.strip()
    open_files = subprocess.run(["lsof", "-nP", "-a", "-u", owner, "-Fn"], capture_output=True, text=True)
    require(open_files.returncode == 0, "Unable to verify whether release scratch is in use")
    active_paths = [line[1:] for line in open_files.stdout.splitlines() if line.startswith("n/")]
    for path in candidates:
        if not any(p == str(path) or p.startswith(f"{path}/") for p in active_paths):
            shutil.rmtree(path)
            print(f"Removed stale release scratch {path.name}", flush=True)


def xcode_environment():
    env = os.environ.copy()
    override = env.pop("XCODE_XCCONFIG_FILE", "").strip()
    if override:
        path = Path(override).expanduser().resolve()
        require(path.is_file() and path.suffix == ".xcconfig" and os.access(path, os.R_OK),
                "XCODE_XCCONFIG_FILE must name a readable .xcconfig file")
        env["XCODE_XCCONFIG_FILE"] = str(path)
    command(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], env=env, stdout=subprocess.DEVNULL)
    return env


def build_app(work, config, entry_url, version, build, source_commit, env, lock_fd):
    source = work / "source"
    source.mkdir()
    with subprocess.Popen(["git", "-C", PROJECT, "archive", source_commit, "--", *BUILD_PATHS],
                          stdout=subprocess.PIPE) as snapshot:
        with snapshot.stdout:
            command(["tar", "-xf", "-", "-C", source], stdin=snapshot.stdout)
        require(snapshot.wait() == 0, "Unable to export the source commit")

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
        ], cwd=source, env=env, stdout=log, stderr=subprocess.STDOUT, pass_fds=(lock_fd,))
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
    require(receipt.get("protocol") == 1 and receipt["status"] == "prepared",
            "Release handoff must come from the canonical release tool")
    archive = handoff / ARCHIVE_NAME
    require(archive.is_file() and not archive.is_symlink() and sha256(archive) == receipt["archive_sha256"],
            "Prepared archive checksum differs")
    return receipt


def prepare_archive(config, entry_url, identity, handoff, lock_fd):
    if not handoff.exists() and not handoff.is_symlink():
        env = xcode_environment()
        version, build = identity["version"], identity["build"]
        print(f"Building {version} ({build}) from {identity['source_commit']}", flush=True)
        with scratch("prepare") as work:
            stage = work / "handoff"
            stage.mkdir()
            try:
                archive = build_app(work, config, entry_url, version, build, identity["source_commit"], env, lock_fd)
                app = archive / "Products/Applications/AIServerClient.app"
                archive_zip = stage / ARCHIVE_NAME
                command(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", archive, archive_zip])
                receipt = {
                    "protocol": 1,
                    "identity": identity,
                    "archive_sha256": sha256(archive_zip),
                    "binary_uuids": app_binary_uuids(app, archive / "dSYMs"),
                    "package": f"build-{version}-{build}-{secrets.token_hex(8)}",
                    "status": "prepared",
                }
                write_atomic(stage / RECEIPT_NAME, json.dumps(receipt, indent=2).encode())
                stage.rename(handoff)
            except BaseException:
                save_diagnostics(work, handoff, "archive")
                raise
    receipt = read_handoff(handoff, identity)
    print(f"archive_sha256={receipt['archive_sha256']}", flush=True)
    return receipt


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
        require(sorted(device.upper() for device in profile["ProvisionedDevices"]) == config["device_udids"],
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
        print(f"Verified Ad Hoc signature and {len(config['device_udids'])} registered devices: {bundle_id}", flush=True)
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
    with tempfile.TemporaryDirectory(prefix=".focus-receipt.", dir=destination.parent) as staging:
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
            with tempfile.TemporaryDirectory(prefix=".focus-public.", dir=channel) as staging:
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


def save_diagnostics(work, handoff, stage):
    log = work / f"{stage}.log"
    if log.is_file():
        private_directory(DIAGNOSTICS_ROOT)
        saved = DIAGNOSTICS_ROOT / f"{handoff.name}-{stage}.log"
        with log.open("rb") as file:
            file.seek(max(0, log.stat().st_size - 2 * 1024 * 1024))
            write_atomic(saved, file.read())
        print(f"{stage} log: {saved}", flush=True)


def export_signed(config, entry_url, identity, handoff, checksum, auth, lock_fd):
    receipt = read_handoff(handoff, identity)
    require(checksum == receipt["archive_sha256"], "Signing request does not match the prepared archive")
    ipa = handoff / IPA_NAME
    if ipa.is_file() and not ipa.is_symlink():
        print("Ad Hoc IPA already exported", flush=True)
        return
    require(not ipa.exists() and not ipa.is_symlink(), "Unexpected signed output path")
    env = xcode_environment()
    version, build = identity["version"], identity["build"]
    with scratch("sign") as work:
        archive = work / "AIServerClient.xcarchive"
        command(["ditto", "-x", "-k", handoff / ARCHIVE_NAME, work], pass_fds=(lock_fd,))
        app = archive / "Products/Applications/AIServerClient.app"
        command(["codesign", "--verify", "--deep", "--strict", app])
        signature = command(["codesign", "-dv", app], capture_output=True, text=True).stderr
        require(f"TeamIdentifier={config['team_id']}" in signature.splitlines(), "Archive signing team differs")
        info = plistlib.loads((app / "Info.plist").read_bytes())
        require(info["CFBundleIdentifier"] == BUNDLE_ID
                and (info["CFBundleShortVersionString"], info["CFBundleVersion"]) == (version, str(build))
                and app_binary_uuids(app) == receipt["binary_uuids"], "Archive does not match its signing receipt")

        key_id, issuer_id, private_key = auth
        key = work / "AuthKey.p8"
        options = work / "export-options.plist"
        export = work / "export"
        options.write_bytes(plistlib.dumps({"destination": "export", "method": "release-testing",
                                           "signingStyle": "automatic", "teamID": config["team_id"],
                                           "manageAppVersionAndBuildNumber": False}))
        key.write_bytes(private_key)
        try:
            command(["ruby", Path(__file__).with_name("register-focus-adhoc-devices.rb"), key, key_id, issuer_id],
                    input=json.dumps(config["device_udids"]), text=True, pass_fds=(lock_fd,))
            with (work / "export.log").open("wb") as log:
                result = subprocess.run(["xcodebuild", "-exportArchive", "-archivePath", archive,
                                         "-exportOptionsPlist", options, "-exportPath", export,
                                         "-allowProvisioningUpdates", "-authenticationKeyPath", key,
                                         "-authenticationKeyID", key_id, "-authenticationKeyIssuerID", issuer_id],
                                        env=env, stdout=log, stderr=subprocess.STDOUT, pass_fds=(lock_fd,))
                require(result.returncode == 0, f"Xcode Ad Hoc export exited with status {result.returncode}")
        except BaseException:
            save_diagnostics(work, handoff, "export")
            raise
        finally:
            key.unlink()
        exported, = export.glob("*.ipa")
        require(exported.is_file() and not exported.is_symlink(), "Missing signature export")
        require(verify_app(work, exported, config, entry_url, version, build) == receipt["binary_uuids"],
                "Signed IPA binaries differ from the prepared archive")
        exported.chmod(0o600)
        exported.rename(ipa)


def signing_runs(checksum):
    result = command(["gh", "run", "list", "--repo", GITHUB_REPO, "--workflow", SIGNING_WORKFLOW,
                      "--branch", "main", "--event", "workflow_dispatch", "--limit", "100",
                      "--json", "displayTitle,databaseId,status,conclusion"], capture_output=True)
    return [run for run in json.loads(result.stdout) if run["displayTitle"] == f"Focus Ad Hoc {checksum}"]


def request_signing(identity, checksum):
    matching = signing_runs(checksum)
    if matching and (matching[0]["status"] != "completed" or matching[0]["conclusion"] == "success"):
        return matching[0]["databaseId"], set()
    inputs = {"source_commit": identity["source_commit"], "version": identity["version"],
              "build": str(identity["build"]), "archive_sha256": checksum}
    command(["gh", "workflow", "run", SIGNING_WORKFLOW, "--repo", GITHUB_REPO, "--ref", "main", "--json"],
            input=json.dumps(inputs), text=True)
    return None, {run["databaseId"] for run in matching}


def wait_for_signing(checksum, request):
    run_id, previous = request
    deadline = time.monotonic() + 60
    while run_id is None and time.monotonic() < deadline:
        runs = signing_runs(checksum)
        run_id = next((run["databaseId"] for run in runs if run["databaseId"] not in previous), None)
        if run_id is None:
            time.sleep(3)
    require(run_id is not None, "Signing job is not visible yet. Resume using the same release command.")
    command(["gh", "run", "watch", str(run_id), "--repo", GITHUB_REPO, "--interval", "5", "--exit-status"])


def read_current(channel):
    latest = channel / "latest.json"
    current = json.loads(latest.read_bytes()) if latest.exists() else None
    current_version = version_key(current["version"], current["build"]) if current else (0, 0, 0, 0)
    return current, current_version


def require_package_name(package, identity):
    require(re.fullmatch(rf"build-{re.escape(identity['version'])}-{identity['build']}-[0-9a-f]{{16}}", package),
            "Invalid package identity in release receipt")


def finish_release(config, entry_url, identity, handoff, channel):
    current, current_version = read_current(channel)
    version, build = identity["version"], identity["build"]
    target = version_key(version, build)
    require(target >= current_version, "The direct-install page already serves a newer build")
    origin = config["public_origin"]
    if target == current_version and not handoff.exists():
        package = current["package"]
        require_package_name(package, identity)
        record = RECEIPT_ROOT / package / RECEIPT_NAME
        require(record.is_file() and not record.is_symlink(), "No receipt for the current build")
        saved = json.loads(record.read_bytes())
        require(saved.get("protocol") == 1 and saved["identity"] == identity
                and saved["package"] == package and saved["status"] == "published"
                and sha256(record.parent / SYMBOLS_NAME) == saved["dsym_sha256"], "Published receipt differs")
        with scratch("publish") as work:
            fetch(f"{origin}/img/{config['channel']}/{package}/Focus.ipa", work / "public.ipa")
            require(sha256(work / "public.ipa") == saved["ipa_sha256"], "Public IPA differs from the saved receipt")
            fetch(entry_url.rsplit("/", 1)[0] + "/latest.json?check=" + secrets.token_hex(8), work / "public-latest.json")
            require(json.loads((work / "public-latest.json").read_bytes()) == current, "Public latest version differs")
        print(f"Published {version} ({build}) verified. release_record={record}", flush=True)
        return

    ipa = handoff / IPA_NAME
    receipt = read_handoff(handoff, identity)
    require(ipa.is_file() and not ipa.is_symlink(), "The prepared release requires its signed IPA")
    require({path.name for path in handoff.iterdir()} == {ARCHIVE_NAME, IPA_NAME, RECEIPT_NAME},
            "Release handoff contains unexpected files")
    name = receipt["package"]
    require_package_name(name, identity)
    require(target > current_version or current["package"] == name,
            "The direct-install page already serves another build")
    private_directory(RECEIPT_ROOT)
    destination = RECEIPT_ROOT / name
    base = f"{origin}/img/{config['channel']}/{name}/"
    assets = {kind: base + file for kind, file in {
        "software-package": "Focus.ipa", "display-image": "icon-57.png", "full-size-image": "icon-512.png",
    }.items()}

    ipa_checksum = sha256(ipa)
    with scratch("publish") as work:
        require(verify_app(work, ipa, config, entry_url, version, build) == receipt["binary_uuids"],
                "Signed IPA binaries differ from the prepared archive")
        require(ipa_checksum == sha256(ipa), "Signed IPA changed during verification")
        manifest = work / "manifest.plist"
        manifest.write_bytes(install_manifest(assets, version))
        icon = work / "AppIcon.png"
        icon.write_bytes(git_output("show", f"{identity['source_commit']}:{ICON_PATH}"))
        publish(work, channel, entry_url, channel / name, base, assets, ipa, manifest, icon, version, build)
        require(ipa_checksum == sha256(ipa), "Signed IPA changed during public verification")
        save_release_receipt(handoff, destination, receipt, ipa_checksum)

    with scratch("finished") as work:
        handoff.rename(work / "handoff")
    print(f"Published {version} ({build}). release_record={destination / RECEIPT_NAME}", flush=True)


@contextmanager
def release_lock(channel):
    with LOCK.open("a+") as file:
        fcntl.flock(file, fcntl.LOCK_EX)
        WORK_ROOT.mkdir(exist_ok=True, parents=True)
        require(WORK_ROOT.resolve() == WORK_ROOT and WORK_ROOT.stat().st_uid == os.getuid(),
                "Direct-install work root must be an owned directory")
        private_directory(SCRATCH_ROOT)
        prune_scratch(channel)
        yield file.fileno()


@contextmanager
def queue_lock(name):
    private_directory(QUEUE_ROOT)
    with (QUEUE_ROOT / f"{name}.lock").open("a") as file:
        fcntl.flock(file, fcntl.LOCK_EX)
        yield


def queue_read():
    path = QUEUE_ROOT / "state.json"
    return json.loads(path.read_bytes()) if path.exists() else {"pending": None, "inflight": None}


def queue_save(state):
    write_atomic(QUEUE_ROOT / "state.json", json.dumps(state).encode())


def is_ancestor(older, newer):
    result = subprocess.run(["git", "-C", PROJECT, "merge-base", "--is-ancestor", older, newer])
    require(result.returncode in (0, 1), "Unable to check release commit ancestry")
    return result.returncode == 0


def current_release(channel):
    current, key = read_current(channel)
    if current is None:
        return None, key
    require_package_name(current["package"], current)
    record = RECEIPT_ROOT / current["package"] / RECEIPT_NAME
    if not record.is_file() or record.is_symlink():
        return None, key
    receipt = json.loads(record.read_bytes())
    identity = receipt["identity"]
    require(receipt.get("status") == "published" and receipt.get("public_readback_at")
            and receipt["package"] == current["package"]
            and version_key(identity["version"], identity["build"]) == key,
            "Current release receipt does not match the install channel")
    return identity, key


def queue_release(args, config, configuration_file, entry_url, channel):
    source = args.source_commit
    require(is_ancestor(source, os.environ["FOCUS_RELEASE_MAIN"]), "Queue only accepts commits already on main")
    with queue_lock("state"):
        published, _ = current_release(channel)
        if published and is_ancestor(source, published["source_commit"]):
            print(f"Already published in {published['version']} ({published['build']})", flush=True)
            return
        state = queue_read()
        pending = state["pending"]
        inflight = state["inflight"]
        if not inflight or not is_ancestor(source, inflight["source_commit"]):
            now = time.time()
            if pending and is_ancestor(source, pending["source_commit"]):
                if args.queue_now:
                    pending["ready_at"] = now
            else:
                if pending:
                    require(is_ancestor(pending["source_commit"], source), "Cannot batch divergent release commits")
                first = pending["first_at"] if pending else now
                urgent = args.queue_now or (pending and pending["urgent"])
                state["pending"] = {
                    "source_commit": source,
                    "first_at": first,
                    "ready_at": now if urgent else min(now + QUEUE_DELAY, first + QUEUE_MAX_DELAY),
                    "urgent": bool(urgent),
                }
            if args.queue_now:
                state["pending"]["urgent"] = True
            queue_save(state)
    print(f"Queued {source[:12]} for the shared direct-install release", flush=True)

    # Do not hold the archive/export lock here: the signing runner needs it.
    # The short state lock still lets other callers submit during signing.
    with queue_lock("dispatcher"):
        while True:
            with queue_lock("state"):
                state = queue_read()
                published, key = current_release(channel)
                if published and is_ancestor(source, published["source_commit"]):
                    print(f"Published {published['version']} ({published['build']}) includes {source[:12]}", flush=True)
                    return
                inflight = state["inflight"]
                pending = state["pending"]
                if inflight is None:
                    require(pending is not None, "Queued release request is missing")
                    remaining = pending["ready_at"] - time.time()
                    if remaining <= 0:
                        major, minor, patch, build = key
                        inflight = {
                            "source_commit": pending["source_commit"],
                            "version": f"{major}.{minor}.{patch + 1}",
                            "build": build + 1,
                        }
                        state.update(inflight=inflight, pending=None)
                        queue_save(state)
            if inflight is None:
                time.sleep(min(remaining, 2))
                continue
            if not published or not is_ancestor(inflight["source_commit"], published["source_commit"]):
                release_action(argparse.Namespace(**inflight, release=True, publish=False,
                                                  export_signed=False, prepare=False),
                               config, configuration_file, entry_url, channel, auth=None)
            with queue_lock("state"):
                state = queue_read()
                state["inflight"] = None
                pending = state["pending"]
                if pending and is_ancestor(pending["source_commit"], inflight["source_commit"]):
                    state["pending"] = None
                queue_save(state)


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version")
    parser.add_argument("--build", type=int)
    parser.add_argument("--source-commit", required=True, help="Full SHA of the committed app source")
    parser.add_argument("--archive-sha256", help=argparse.SUPPRESS)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--prepare", action="store_true", help="Prepare or reuse the archive")
    action.add_argument("--release", action="store_true", help="Prepare, sign and publish this release")
    action.add_argument("--publish", action="store_true", help="Resume public verification using a signed handoff")
    action.add_argument("--export-signed", action="store_true", help=argparse.SUPPRESS)
    action.add_argument("--queue", action="store_true", help="Batch a merged commit and wait for a shared release")
    action.add_argument("--queue-now", action="store_true", help="Batch immediately after any active release")
    args = parser.parse_args()
    queued = args.queue or args.queue_now
    if queued:
        require(args.version is None and args.build is None, "The shared queue assigns the release version")
    else:
        require(args.version is not None and args.build is not None, "Pass both --version and --build")
        version_key(args.version, args.build)
    require(re.fullmatch(r"[a-f0-9]{40}", args.source_commit), "Expected a full Git commit SHA")
    if args.export_signed:
        require(os.environ.get("GITHUB_REF") == "refs/heads/main"
                and os.environ.get("GITHUB_WORKFLOW_REF", "").split("@", 1)[0]
                == f"{GITHUB_REPO}/.github/workflows/{SIGNING_WORKFLOW}",
                "Signing must run in the dedicated workflow on main")
        require(args.archive_sha256 and re.fullmatch(r"[a-f0-9]{64}", args.archive_sha256),
                "Expected the prepared archive SHA-256")
        key = os.environ.pop("APP_STORE_CONNECT_PRIVATE_KEY_BASE64", "")
        key_id = os.environ.pop("APP_STORE_CONNECT_KEY_ID", "")
        issuer_id = os.environ.pop("APP_STORE_CONNECT_ISSUER_ID", "")
        require(key and key_id and issuer_id, "Signing workflow credentials are unavailable")
        auth = key_id, issuer_id, base64.b64decode("".join(key.split()), validate=True)
    else:
        require(re.fullmatch(r"[a-f0-9]{40}", os.environ.get("FOCUS_RELEASE_MAIN", "")),
                "Start from ~/.local/bin/focus-direct-install")
        require(not args.archive_sha256, "Archive checksums are input to the signing workflow only")
    require(git_output("cat-file", "-t", args.source_commit).strip() == b"commit", "Source commit is unavailable")
    config_info = CONFIG.stat()
    require(CONFIG.is_file() and not CONFIG.is_symlink() and config_info.st_uid == os.getuid()
            and not (config_info.st_mode & 0o077), "Direct-install configuration must be private")
    configuration_file = CONFIG.read_bytes()
    config = json.loads(configuration_file)
    origin = urlsplit(config["public_origin"])
    require(origin.scheme == "https" and origin.hostname and not origin.username
            and not origin.path and not origin.query and not origin.fragment, "Expected a public HTTPS origin")
    channel_name = config["channel"]
    require(re.fullmatch(r"focus-update-[a-f0-9]{48}", channel_name), "Invalid private channel path")
    channel = Path(config["public_img_root"]).resolve(strict=True) / channel_name
    entry_url = f"{config['public_origin']}/img/{channel_name}/install.html"
    devices = config["device_udids"]
    require(isinstance(devices, list) and devices and all(
        isinstance(device, str) and re.fullmatch(r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}|[0-9A-Fa-f]{40}", device)
        for device in devices
    ), "Expected a nonempty list of device UDIDs")
    config["device_udids"] = sorted(device.upper() for device in devices)
    require(len(set(config["device_udids"])) == len(devices), "Device UDIDs must be unique")
    if queued:
        queue_release(args, config, configuration_file, entry_url, channel)
    elif args.export_signed:
        release_action(args, config, configuration_file, entry_url, channel, auth)
    else:
        # Explicit recovery/maintenance cannot race with a queued publication.
        with queue_lock("dispatcher"):
            release_action(args, config, configuration_file, entry_url, channel, auth=None)


def release_action(args, config, configuration_file, entry_url, channel, auth):
    target = version_key(args.version, args.build)
    configuration = json.dumps([entry_url, config["team_id"], config["device_udids"]]).encode()
    identity = {"source_commit": args.source_commit, "version": args.version, "build": args.build,
                "configuration_sha256": hashlib.sha256(configuration).hexdigest()}
    key = json.dumps([entry_url, target]).encode()
    handoff = WORK_ROOT / f"focus-adhoc-export.{hashlib.sha256(key).hexdigest()}"

    with release_lock(channel) as lock_fd:
        require(CONFIG.read_bytes() == configuration_file, "Release configuration changed")
        require(not channel.is_symlink(), "Direct-install channel must be a real directory")
        channel.mkdir(exist_ok=True)
        current, current_version = read_current(channel)
        if args.publish or (args.release and target == current_version and not handoff.exists()):
            finish_release(config, entry_url, identity, handoff, channel)
            return
        require(target >= current_version, "The direct-install page already serves a newer build")
        if target == current_version:
            require(read_handoff(handoff, identity)["package"] == current["package"],
                    "The direct-install page already serves another build")
        if args.export_signed:
            export_signed(config, entry_url, identity, handoff, args.archive_sha256, auth, lock_fd)
            return
        receipt = prepare_archive(config, entry_url, identity, handoff, lock_fd)
        if args.prepare:
            return
        ipa = handoff / IPA_NAME
        if ipa.is_file() and not ipa.is_symlink():
            finish_release(config, entry_url, identity, handoff, channel)
            return
        request = request_signing(identity, receipt["archive_sha256"])
    wait_for_signing(receipt["archive_sha256"], request)
    with release_lock(channel):
        require(CONFIG.read_bytes() == configuration_file, "Release configuration changed while signing")
        finish_release(config, entry_url, identity, handoff, channel)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda _signum, _frame: sys.exit(143))
    main()
