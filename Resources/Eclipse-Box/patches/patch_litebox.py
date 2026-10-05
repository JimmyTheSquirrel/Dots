import os, shutil, glob

F = "/storage/.kodi/addons/script.litebox/resources/lib/utils.py"
ORIG = F + ".orig"

src = open(F).read()
n = src.count("Image.ANTIALIAS")

if n == 0:
    print("ALREADY PATCHED - no Image.ANTIALIAS left")
else:
    if not os.path.exists(ORIG):
        shutil.copy2(F, ORIG)
        print("backed up ->", ORIG)
    # Pillow removed Image.ANTIALIAS in 10.0. LANCZOS is the SAME filter under
    # its modern name (they were the same constant), so this is behaviour-identical.
    src = src.replace("Image.ANTIALIAS", "Image.LANCZOS")
    open(F, "w").write(src)
    print("replaced %d occurrence(s) of Image.ANTIALIAS -> Image.LANCZOS" % n)

# Stale bytecode would shadow the edit
removed = 0
for pyc in glob.glob("/storage/.kodi/addons/script.litebox/**/__pycache__/*.pyc", recursive=True):
    os.remove(pyc); removed += 1
print("cleared %d stale .pyc" % removed)

import ast
ast.parse(open(F).read())
print("syntax OK")
