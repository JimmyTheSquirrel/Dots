import re, shutil, sys, os

F = "/storage/.kodi/addons/plugin.video.jellyfin/jellyfin_kodi/helper/playutils.py"
ORIG = F + ".orig"

src = open(F).read()

MARK = "VideoRangeType"
if MARK in src:
    print("ALREADY PATCHED - no change")
    sys.exit(0)

if not os.path.exists(ORIG):
    shutil.copy2(F, ORIG)
    print("backed up ->", ORIG)

# Locate get_device_profile, then the ForceTranscode line *inside* it.
start = src.index("def get_device_profile(self):")
anchor = '        if self.info["ForceTranscode"]:'
idx = src.index(anchor, start)

BLOCK = '''        # Dolby Vision Profile 5 has no HDR10 fallback: its base layer is IPT-C2,
        # not YCbCr. Kodi on the Pi 5 has no DV support, so direct-playing one
        # decodes IPT as though it were YUV and the picture comes out green.
        # Refusing direct play for VideoRangeType "DOVI" makes the server
        # tone-map it instead. "DOVIWithHDR10" (profile 8.1), HDR10, HDR10Plus
        # and SDR are unaffected and still direct-play.
        profile["CodecProfiles"].append(
            {
                "Type": "Video",
                "Codec": "hevc",
                "Conditions": [
                    {
                        "Condition": "NotEquals",
                        "Property": "VideoRangeType",
                        "Value": "DOVI",
                        "IsRequired": True,
                    }
                ],
            }
        )

'''

src = src[:idx] + BLOCK + src[idx:]
open(F, "w").write(src)
print("patched OK")
