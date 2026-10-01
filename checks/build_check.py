"""Audit the actual Godot 4.5.1 web pack, APK and AAB with the standard library."""
from hashlib import sha256
import gzip
import json
from pathlib import Path
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def web_pack(path):
    # Pinned format: Godot's core/io/file_access_pack.cpp, 4.5.1-stable.
    data = path.read_bytes()
    magic, version, major, minor, patch, flags, base, directory = struct.unpack_from("<6I2Q", data)
    assert (magic, version, major, minor, patch, flags) == (0x43504447, 3, 4, 5, 1, 2)
    count, = struct.unpack_from("<I", data, directory)
    cursor, files = directory + 4, {}
    for _ in range(count):
        length, = struct.unpack_from("<I", data, cursor)
        cursor += 4
        name = data[cursor:cursor + length].decode().rstrip("\0").removeprefix("res://")
        cursor += length
        offset, size = struct.unpack_from("<QQ", data, cursor)
        file_flags, = struct.unpack_from("<I", data, cursor + 32)
        cursor += 36
        assert file_flags == 0 and base + offset + size <= directory
        files[name] = data[base + offset:base + offset + size]
    return files


def audit(files, manifest):
    assert not any(name.startswith(("training/", "checks/", ".tools/", "validation/", "builds/", "android/")) or name.endswith((".onnx", ".zip", ".pt")) for name in files)
    bundled = json.loads(files["models/manifest.json"])
    assert bundled["physics_hash"] == manifest["physics_hash"]
    hashes, runtime_bytes = {}, 0
    for level, profile in manifest["levels"].items():
        prefix = f"models/{level}/actor."
        binary, metadata = files[prefix + "bin"], files[prefix + "json"]
        actor = json.loads(metadata)
        digest = sha256(binary).hexdigest()
        assert digest == profile["weights_sha256"] == actor["weights_sha256"] == bundled["levels"][level]["weights_sha256"]
        assert actor["delay_ticks"] == profile["delay_ticks"] and actor["physics_hash"] == manifest["physics_hash"]
        assert actor["dims"] == [52, 64, 64, 2] and len(binary) == 30728
        assert len(binary) + len(metadata) < 50 * 1024
        runtime_bytes += len(binary) + len(metadata)
        hashes[level] = digest
    runtime_bytes += len(files["models/manifest.json"]) + len(files["models/schema.json"])
    assert runtime_bytes < 250 * 1024
    return {"files": len(files), "model_hashes": hashes, "runtime_policy_bytes": runtime_bytes, "excluded_training_checks_onnx": True}


def main():
    manifest = json.loads((ROOT / "models/manifest.json").read_text())
    report = {"physics_hash": manifest["physics_hash"], "artifacts": {}}
    pack = ROOT / "builds/web/index.pck"
    report["artifacts"]["web_pack"] = audit(web_pack(pack), manifest)
    html = (pack.parent / "index.html").read_text()
    assert "location.pathname.endsWith('/')" in html and "location.replace('index.html'" in html
    report["pwa_canonical_entry_redirect"] = True
    for name in ["index.pck", "index.wasm", "index.js"]:
        data = (pack.parent / name).read_bytes()
        report["artifacts"][name] = {"bytes": len(data), "gzip_bytes": len(gzip.compress(data)), "sha256": sha256(data).hexdigest()}
    for extension in ["apk", "aab"]:
        path = ROOT / f"builds/android/air-hockey-debug.{extension}"
        with zipfile.ZipFile(path) as archive:
            manifests = [name for name in archive.namelist() if name.endswith("/models/manifest.json")]
            assert len(manifests) == 1
            prefix = manifests[0].removesuffix("models/manifest.json")
            files = {name.removeprefix(prefix): archive.read(name) for name in archive.namelist() if name.startswith(prefix) and not name.endswith("/")}
        result = audit(files, manifest)
        result.update(bytes=path.stat().st_size, sha256=sha256(path.read_bytes()).hexdigest(), signing="debug key")
        report["artifacts"][extension] = result
    (ROOT / "validation/builds.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
