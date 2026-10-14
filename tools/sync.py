# Mirrors the desktop FreshFixes addon folder into the WoW Forever AddOns folder
# so changes can be tested in game. Only touches .../AddOns/FreshFixes.
#   python tools/sync.py
import filecmp, os, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "FreshFixes")
DST = r"C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\FreshFixes"

if len(sys.argv) > 1:
    DST = sys.argv[1]

copied = removed = 0
for root, dirs, files in os.walk(SRC):
    rel = os.path.relpath(root, SRC)
    target = os.path.normpath(os.path.join(DST, rel))
    os.makedirs(target, exist_ok=True)
    for f in files:
        s, d = os.path.join(root, f), os.path.join(target, f)
        if not os.path.exists(d) or not filecmp.cmp(s, d, shallow=False):
            shutil.copy2(s, d)
            copied += 1

# remove files that no longer exist in the source
for root, dirs, files in os.walk(DST, topdown=False):
    rel = os.path.relpath(root, DST)
    src_dir = os.path.normpath(os.path.join(SRC, rel))
    for f in files:
        if not os.path.exists(os.path.join(src_dir, f)):
            os.remove(os.path.join(root, f))
            removed += 1
    if not os.path.exists(src_dir):
        os.rmdir(root)

print(f"synced to {DST}: {copied} copied, {removed} removed")
