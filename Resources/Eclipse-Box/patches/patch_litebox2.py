import os, shutil, glob, ast

F = "/storage/.kodi/addons/script.litebox/resources/lib/imageoperations.py"
ORIG = F + ".orig"

src = open(F).read()

OLD = '''class MyGaussianBlur(ImageFilter.Filter):
    NAME = "GaussianBlur"
    def __init__(self, radius=10):
        self.radius = radius
    def filter(self, image):
        return image.gaussian_blur(self.radius)'''

NEW = '''class MyGaussianBlur(ImageFilter.GaussianBlur):
    # Pillow >= 10 changed the private ImagingCore.gaussian_blur signature:
    # argument 1 is now an (xradius, yradius) pair, so the old scalar call
    # raised "argument 1 must be 2-item sequence, not int" on every image.
    # Inheriting Pillow's own GaussianBlur keeps us correct across versions,
    # and as a MultibandFilter it blurs RGB in one C call instead of three.
    NAME = "GaussianBlur"
    def __init__(self, radius=10):
        super().__init__(radius=radius)'''

if "ImageFilter.GaussianBlur" in src:
    print("ALREADY PATCHED")
elif OLD not in src:
    raise SystemExit("ANCHOR NOT FOUND - refusing to patch blindly")
else:
    if not os.path.exists(ORIG):
        shutil.copy2(F, ORIG); print("backed up ->", ORIG)
    src = src.replace(OLD, NEW)
    open(F, "w").write(src)
    print("patched MyGaussianBlur")

removed = 0
for pyc in glob.glob("/storage/.kodi/addons/script.litebox/**/__pycache__/*.pyc", recursive=True):
    os.remove(pyc); removed += 1
print("cleared %d stale .pyc" % removed)

ast.parse(open(F).read())
print("syntax OK")

# prove the real code path works before restarting Kodi
import sys
sys.path.insert(0, "/storage/.kodi/addons/script.litebox/resources/lib")
from PIL import Image
from imageoperations import MyGaussianBlur
im = Image.new("RGB", (320, 180), (120, 30, 200))
out = im.filter(MyGaussianBlur(radius=30))
print("blur through litebox's own class: OK, size", out.size, "mode", out.mode)
