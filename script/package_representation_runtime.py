#!/usr/bin/env python3
"""Copy the pinned, locally built shadow runtime without downloading anything."""
import hashlib
import json
from pathlib import Path
import shutil
import sys


def main():
    source, destination = map(Path, sys.argv[1:])
    manifest = source / "build-manifest.json"
    if manifest.is_symlink() or not manifest.is_file() or manifest.stat().st_size > 65536:
        raise ValueError("Missing bounded runtime build manifest")
    raw = manifest.read_bytes()
    info = json.loads(raw)
    required = {
        "archi-gguf-shadow", "libllama.0.dylib", "libggml.0.dylib",
        "libggml-base.0.dylib", "libggml-cpu.0.dylib", "LICENSE", "JSON_LICENSE.MIT",
    }
    if (info.get("schema") != "archi-gguf-worker-build/v1"
            or info.get("upstream_revision") != "161755f29e415e2c33efe906e91843c068efd664"
            or info.get("backend_revision") != "llama.cpp:161755f29"
            or info.get("architecture") != "arm64"
            or info.get("execution") != "cpu"
            or info.get("mode") != "shadow"
            or set(info.get("runtime_sha256", {})) != required):
        raise ValueError("Unsupported representation runtime identity or contents")
    for name in sorted(required):
        path = source / name
        if path.is_symlink() or not path.is_file() or path.stat().st_size > 512 * 1024 * 1024:
            raise ValueError("Runtime member must be a bounded regular file: " + name)
        if hashlib.sha256(path.read_bytes()).hexdigest() != info["runtime_sha256"][name]:
            raise ValueError("Runtime digest mismatch: " + name)
    destination.mkdir(parents=True, exist_ok=False)
    for name in sorted(required):
        shutil.copy2(source / name, destination / name)
        if hashlib.sha256((destination / name).read_bytes()).hexdigest() != info["runtime_sha256"][name]:
            raise ValueError("Copied runtime digest mismatch: " + name)
    (destination / manifest.name).write_bytes(raw)
    print("Packaged pinned arm64 read-only representation runtime")


if __name__ == "__main__":
    main()
