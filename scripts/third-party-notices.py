#!/usr/bin/env python3
"""Writes MindMapAI/Resources/ThirdPartyNotices.txt from the resolved package
checkouts. MIT, BSD and Apache-2.0 all ask for their notices to ship with the
binary (ADR 0011); run this after changing a package version and commit the
result. Usage: scripts/third-party-notices.py [checkouts dir]"""
import json, pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent
checkouts = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else root / "scripts/out/DerivedData/SourcePackages/checkouts"
resolved = json.loads((root / "MindMapAI.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text())
versions = {p["identity"]: p["state"].get("version") or p["state"]["revision"][:12] for p in resolved["pins"]}

# Packages linked into the app, and code they vendor. swift-syntax is resolved
# but only builds mlx-swift-lm's macros, which the app does not use.
LINKED = [
    ("mlx-swift", "mlx-swift", ["LICENSE"]),
    ("MLX (C++), vendored in mlx-swift", "mlx-swift", ["Source/Cmlx/mlx/LICENSE"]),
    ("mlx-c, vendored in mlx-swift", "mlx-swift", ["Source/Cmlx/mlx-c/LICENSE"]),
    ("fmt, vendored in mlx-swift", "mlx-swift", ["Source/Cmlx/fmt/LICENSE"]),
    ("nlohmann/json, vendored in mlx-swift", "mlx-swift", ["Source/Cmlx/json/LICENSE.MIT"]),
    ("metal-cpp, vendored in mlx-swift", "mlx-swift", ["Source/Cmlx/metal-cpp/LICENSE.txt"]),
    ("mlx-swift-lm", "mlx-swift-lm", ["LICENSE"]),
    ("XGrammar, vendored in mlx-swift-lm", "mlx-swift-lm", ["Libraries/MLXCXGrammar/xgrammar/LICENSE", "Libraries/MLXCXGrammar/xgrammar/NOTICE"]),
    ("picojson, vendored in XGrammar", "mlx-swift-lm", ["Libraries/MLXCXGrammar/xgrammar/3rdparty/picojson/picojson.h"]),
    ("swift-numerics", "swift-numerics", ["LICENSE.txt"]),
    ("swift-transformers", "swift-transformers", ["LICENSE"]),
    ("swift-jinja", "swift-jinja", ["LICENSE"]),
    ("swift-huggingface", "swift-huggingface", ["LICENSE"]),
    ("swift-collections", "swift-collections", ["LICENSE.txt"]),
    ("swift-crypto", "swift-crypto", ["LICENSE.txt", "NOTICE.txt"]),
    ("swift-asn1", "swift-asn1", ["LICENSE.txt"]),
    ("yyjson", "yyjson", ["LICENSE"]),
    ("EventSource", "eventsource", ["LICENSE.md"]),
]

def text(path):
    body = path.read_text()
    if path.suffix == ".h":  # the licence is the header's first comment
        body = re.sub(r"^ ?\* ?", "", re.match(r"/\*(.*?)\*/", body, re.S).group(1), flags=re.M)
    return body.strip()

out = ["MindMap AI by xDev uses the following open-source software.", ""]
for title, identity, files in LINKED:
    folder = checkouts / {"eventsource": "EventSource"}.get(identity, identity)
    out += ["=" * 72, f"{title} ({versions[identity]})", "=" * 72, ""]
    for name in files:
        out += [text(folder / name), ""]
target = root / "MindMapAI/Resources/ThirdPartyNotices.txt"
target.write_text("\n".join(out))
print(f"wrote {target.relative_to(root)}")
