import re
import os
import sys

src_dir = "."
dst_dir = sys.argv[1] if len(sys.argv) > 1 else "dist/QoLify"
files = sys.argv[2:] if len(sys.argv) > 2 else []

for f in files:
    src = open(os.path.join(src_dir, f), encoding="utf-8").read()
    dst = os.path.join(dst_dir, f)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if not f.endswith(".lua"):
        open(dst, "w", encoding="utf-8").write(src)
        continue
    out = []
    for line in src.splitlines():
        line = re.sub(r"\s*--(?!-).*", "", line).rstrip()
        if line:
            out.append(line)
    open(dst, "w", encoding="utf-8").write("\n".join(out) + "\n")

print(f"Minified {len(files)} files into {dst_dir}")
