"""Make the Jellyfin Kodi addon stop turning subtitles off on every play.

THE BUG (diagnosed 2026-11-21, from /storage/.kodi/temp/kodi.log)

  jellyfin-kodi asks the server for PlaybackInfo, and the server answers with
  DefaultSubtitleStreamIndex -- the track it picked from the user's
  SubtitleMode ("Always") and SubtitleLanguagePreference. playutils.py stores
  it on item["SubtitleStreamIndex"] and it reaches the player intact:

      'SubsMapping': {}, 'AudioStreamIndex': 1, 'SubtitleStreamIndex': 2

  ...and then TWO separate things throw it away before it is ever applied.
  onPlayBackStarted() ends with

      if monitor.waitForAbort(2):
          return
      if item["PlayOption"] == "Addon":
          self.set_audio_subs(item["AudioStreamIndex"], item["SubtitleStreamIndex"])

  and set_audio_subs() calls showSubtitles(False) when it is handed None. The
  log shows "Setting audio: 1 subs: None" on every affected play.

  1. detect_audio_subs(), called just before that wait, OVERWRITES the index
     with whatever Kodi currently reports:

         if not subs_enabled or not len(self.getAvailableSubtitleStreams()):
             item["SubtitleStreamIndex"] = None
             return

     Both halves fire at playback start: subs_enabled is False because Kodi
     starts a plain EMBEDDED subtitle track hidden, and
     getAvailableSubtitleStreams() is often still EMPTY because this runs
     ~0.2s BEFORE Kodi's own "Opening stream: 2" (the order varies run to run,
     which is why it looked intermittent).

  2. Even with that fixed, `item` is the SAME dict report_playback() works on
     (self.played[file]), and report_playback() -> detect_audio_subs() fires on
     the server's Player.OnAVChange / ReportProgressRequested *during* the 2s
     wait, wiping the index back to None before set_audio_subs() reads it.

  It only ever worked on files where the addon handed Kodi EXTERNAL subtitle
  files (SubsMapping populated -- the transcode path), because Kodi enables
  those itself, so detect_audio_subs() read a real index back.

  Net effect: the server-side subtitle preference can choose WHICH track, but
  can never turn subtitles ON. No Jellyfin or Kodi setting fixes that from the
  outside, which is why "Subtitles on" in the dashboard looked ignored.

THE FIX (three edits)

  * detect_audio_subs() takes keep_default= and, when set, leaves the server's
    index alone instead of wiping it.
  * onPlayBackStarted() passes keep_default=True and SNAPSHOTS the tracks it
    means to apply into locals, so a progress report during the 2s wait cannot
    take them away.
  * set_audio_subs() is then called with those locals.

  report_playback() keeps the old wiping behaviour on purpose: it has to stay
  honest about what is on screen, or hiding subs mid-film is never reported and
  Jellyfin's RememberSubtitleSelections hands them back on the next play.

  Nothing needs to force visibility -- Kodi's Player.setSubtitleStream() calls
  SetSubtitleVisible(true) itself (xbmc/interfaces/legacy/Player.cpp).

Idempotent. Run on the Pi, then restart Kodi (the dashboard's "Restart Kodi",
or systemctl restart kodi) -- Python is already loaded.

Both dashboards can run this themselves: the Eclipse card's "Repair subtitles"
button pipes THIS FILE to the Pi over ssh and runs it as `python3 -`
(act_subs_patch in Resources/Eclipse-Control/eclipse-control.py), so what runs
is always this repo's copy and nothing stale is left on the Pi. That button
reads the LAST LINE printed below -- RESULT=patched or RESULT=already -- to
decide whether it also has to restart Kodi. Keep both strings if you edit this.

  WARNING: like patch_dv.py, this is CLOBBERED BY EVERY ADDON UPDATE. If
  subtitles stop coming on by themselves, re-run this before anything else.
  The tell is "Setting audio: <n> subs: None" in kodi.log on a file whose
  PlaybackInfo above it shows a DefaultSubtitleStreamIndex.
"""

import os
import shutil
import sys

F = "/storage/.kodi/addons/plugin.video.jellyfin/jellyfin_kodi/player.py"
ORIG = F + ".subs-orig"

src = open(F).read()

MARK = "keep_default"
if MARK in src:
    print("ALREADY PATCHED - no change")
    print("RESULT=already")
    sys.exit(0)

OLD_DEF = "    def detect_audio_subs(self, item):"

OLD_CALL = (
    "        # Detect current audio/subtitle state from Kodi player\n"
    "        self.detect_audio_subs(item)\n"
)

OLD_APPLY = (
    '        if item["PlayOption"] == "Addon":\n'
    '            self.set_audio_subs(item["AudioStreamIndex"], item["SubtitleStreamIndex"])\n'
)

OLD_BLOCK = (
    "        if not subs_enabled or not len(self.getAvailableSubtitleStreams()):\n"
    '            item["SubtitleStreamIndex"] = None\n'
    "\n"
    "            return\n"
)

for name, needle in (
    ("def", OLD_DEF),
    ("call", OLD_CALL),
    ("apply", OLD_APPLY),
    ("block", OLD_BLOCK),
):
    if src.count(needle) != 1:
        sys.exit(
            "ABORT: expected exactly one %s anchor, found %d. The addon changed "
            "upstream -- re-read player.py before patching." % (name, src.count(needle))
        )

NEW_DEF = "    def detect_audio_subs(self, item, keep_default=False):"

NEW_CALL = (
    "        # Detect current audio/subtitle state from Kodi player.\n"
    "        # keep_default: do NOT wipe the server's DefaultSubtitleStreamIndex\n"
    "        # when Kodi has no enabled subtitle yet - see detect_audio_subs().\n"
    "        self.detect_audio_subs(item, keep_default=True)\n"
    "        # Snapshot the tracks we mean to apply. `item` is the same dict\n"
    "        # report_playback() works on (self.played[file]), and that fires on\n"
    "        # Player.OnAVChange during the 2s wait below and wipes\n"
    "        # SubtitleStreamIndex back to None before we get to use it.\n"
    '        start_audio = item["AudioStreamIndex"]\n'
    '        start_subs = item["SubtitleStreamIndex"]\n'
)

NEW_APPLY = (
    '        if item["PlayOption"] == "Addon":\n'
    "            # The snapshot above, not item[...]: see there.\n"
    "            self.set_audio_subs(start_audio, start_subs)\n"
)

NEW_BLOCK = (
    "        if not subs_enabled or not len(self.getAvailableSubtitleStreams()):\n"
    "            # At playback start (keep_default) leave the index the server\n"
    '            # already picked from the user\'s SubtitleMode ("Always").\n'
    "            # Kodi starts a plain EMBEDDED track hidden, and this runs\n"
    "            # ~0.2s before Kodi even opens the streams, so the old\n"
    "            # unconditional wipe to None made set_audio_subs() call\n"
    "            # showSubtitles(False) 2s later - subtitles off on every play,\n"
    "            # with no server or Kodi setting able to override it.\n"
    "            # set_audio_subs() waits 2s, by which time the streams exist,\n"
    "            # and Kodi's Player.setSubtitleStream() makes them visible.\n"
    "            #\n"
    "            # report_playback() must still wipe: it has to stay honest\n"
    "            # about what is on screen, or hiding subs mid-film is never\n"
    "            # reported and RememberSubtitleSelections brings them back.\n"
    "            if keep_default:\n"
    "                return\n"
    "\n"
    '            item["SubtitleStreamIndex"] = None\n'
    "\n"
    "            return\n"
)

if not os.path.exists(ORIG):
    shutil.copy2(F, ORIG)
    print("backed up ->", ORIG)

src = src.replace(OLD_DEF, NEW_DEF)
src = src.replace(OLD_CALL, NEW_CALL)
src = src.replace(OLD_APPLY, NEW_APPLY)
src = src.replace(OLD_BLOCK, NEW_BLOCK)

open(F, "w").write(src)

# Stale bytecode would shadow the edit on the next import.
cache = os.path.join(os.path.dirname(F), "__pycache__")
for name in os.listdir(cache) if os.path.isdir(cache) else []:
    if name.startswith("player."):
        os.remove(os.path.join(cache, name))
        print("dropped stale bytecode:", name)

print("patched OK - now restart Kodi")
print("RESULT=patched")
