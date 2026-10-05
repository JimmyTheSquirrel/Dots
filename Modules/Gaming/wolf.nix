{ self, ... }: {
  # ============================================================
  # WOLF — multi-session Moonlight server (games-on-whales/wolf)
  # ============================================================
  # Added 2026-09-28 as a trial against Sunshine; proven end-to-end the same day
  # and now the LIVE streaming host — it auto-starts (autoStart at the bottom),
  # while Modules/Gaming/sunshine.nix stays installed with autoStart = false as
  # the fallback. Read Claude/streaming.md and Claude/wolf.md first.
  #
  # WHY: Sunshine *captures an existing output*, so a stream necessarily occupies
  # a real monitor and shares the desktop's single input focus — someone playing
  # on the TV fights the person using the PC. Wolf instead *creates virtual
  # desktops on demand* ("no monitor or dummy plug"), one per session, each with
  # its own virtual input devices, inside containers. That removes the need for
  # the EDID-injection + multi-seat design in Claude/next-up.md item 7 entirely.
  #
  # ⚠️ WOLF AND SUNSHINE CANNOT RUN AT THE SAME TIME *ON THE DEFAULT PORTS*.
  # Both implement the Moonlight protocol, so on stock settings they collide and
  # whichever starts second fails to bind. Wolf now DOES auto-start (see autoStart
  # at the bottom of this file), which is only safe because
  # Modules/Gaming/sunshine.nix has autoStart = false — a matched pair, never set
  # both true while they share a port base.
  #
  # Measured 2026-10-05 with `ss -tlnp`/`-ulnp` against a running Wolf, because the
  # list above was partly wrong: Wolf actually binds TCP 47984, 47989, 48010 and
  # UDP 47999, 48100, 48200. It does NOT bind 47998, 48000 or 47990 — so the
  # 47998 and 48000 entries in allowedUDPPorts below are dead weight. The real
  # overlap with Sunshine is four ports: TCP 47984/47989/48010 + UDP 47999.
  #
  # Sunshine's `port` is a single BASE and everything else is an offset from it,
  # so moving Sunshine to 48989 removes the overlap entirely and both can run at
  # once (Moonlight takes a manual host:port and learns the HTTPS port from
  # serverinfo). Offset SUNSHINE, not Wolf: Wolf keeps the defaults that every
  # already-paired client — including the TV box's one-tap tile, whose host/game
  # ids are positional indices — is pointed at. Not yet done; see Claude/wolf.md.
  #
  # ⚠️ DOCKER, NOT PODMAN — deliberate divergence from Asgard.
  # `virtualisation.oci-containers.backend` is "podman" in Modules/Server/default.nix,
  # but Wolf is Docker-first and *spawns child containers through the mounted
  # socket* (one per running game). Podman's Docker-compatible socket is not a
  # guaranteed match for that nested-spawn path, and this began as a trial —
  # don't debug two unfamiliar things at once. Wolf itself is proven now, so
  # podman could be revisited; nothing currently needs it to be.
  flake.nixosModules.wolf = { pkgs, lib, config, ... }:
  let
    # Probe for the stuck-pad reaper below — read that comment first, it
    # explains why this shape and not a log scrape.
    #
    # Exits 0 (act) only when some "Wolf * virtual *" input device reports
    # buttons held via EVIOCGKEY **and** emits nothing for the whole window.
    # Exits 1 (do nothing) in every other case, including when no Wolf pad
    # exists at all, so the common path is cheap.
    #
    # EVIOCGKEY is the only thing that can see a latched button: the device
    # emits no events, so every ordinary input test shows a perfectly healthy
    # pad. Same ioctl as the probe in Claude/niri.md — but note that file's
    # *fix* (injecting a release) does NOT work here: these pads are uhid-backed
    # and the HID driver owns the state, so the write is accepted and changes
    # nothing. Tried 2026-10-03 on event256; the pad must be destroyed instead.
    stuckPadProbe = pkgs.writeText "wolf-stuck-pad-probe.py" ''
      import fcntl, os, select, sys

      SIZE = 96
      EVIOCGKEY = (2 << 30) | (SIZE << 16) | (0x45 << 8) | 0x18
      WINDOW = 60.0           # seconds of required silence

      def wolf_pads():
          """Event nodes of every Wolf virtual input device."""
          try:
              blocks = open("/proc/bus/input/devices").read().split("\n\n")
          except OSError:
              return []
          found = []
          for block in blocks:
              name, evs = None, []
              for line in block.splitlines():
                  if line.startswith("N: Name="):
                      name = line.split("=", 1)[1].strip('"')
                  elif line.startswith("H: Handlers="):
                      evs = [w for w in line.split("=", 1)[1].split()
                             if w.startswith("event")]
              # Matches the same device-name glob as the udev rules above.
              if name and name.startswith("Wolf ") and "virtual" in name:
                  found += ["/dev/input/" + e for e in evs]
          return found

      def held(path):
          """Codes the kernel currently believes are held down."""
          fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
          try:
              buf = bytearray(SIZE)
              fcntl.ioctl(fd, EVIOCGKEY, buf)
              return frozenset(c for c in range(SIZE * 8)
                               if buf[c // 8] >> (c % 8) & 1)
          finally:
              os.close(fd)

      # Pass 1 — anything held anywhere?
      suspects = {}
      for path in wolf_pads():
          try:
              h = held(path)
          except OSError:
              continue
          if h:
              suspects[path] = h
      if not suspects:
          sys.exit(1)

      # Pass 2 — stay open across the window and drop any pad that speaks.
      # A real player holding buttons still produces a constant event stream;
      # the orphaned pad is completely silent.
      fds = {}
      for path in suspects:
          try:
              fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
          except OSError:
              continue
          try:                      # drain anything already queued
              while os.read(fd, 4096):
                  pass
          except BlockingIOError:
              pass
          except OSError:
              os.close(fd)
              continue
          fds[fd] = path

      alive = set()
      deadline = os.times()[4] + WINDOW
      while True:
          remaining = deadline - os.times()[4]
          if remaining <= 0 or not fds:
              break
          ready, _, _ = select.select(list(fds), [], [], remaining)
          for fd in ready:
              # It emitted something, so it is being driven -> not latched.
              # Drop it from the set rather than just recording it, or a
              # chatty pad would spin this loop for the whole window.
              alive.add(fds.pop(fd))
              os.close(fd)

      for fd in fds:
          os.close(fd)

      # Still held, same codes, and silent for the whole window.
      for path, before in suspects.items():
          if path in alive:
              continue
          try:
              if held(path) == before:
                  print("latched: %s codes=%s" % (path, sorted(before)))
                  sys.exit(0)
          except OSError:
              pass
      sys.exit(1)
    '';
  in {
    # MUST be set explicitly. NixOS defaults this to "podman", which would build
    # a `podman-wolf.service` that runs Wolf under podman while it mounts and
    # drives the *Docker* socket to spawn its per-game children — the exact
    # mismatch the header warns about. Safe to set here: Sisyphus does not
    # import nixosModules.server, so this cannot conflict with Asgard's podman.
    virtualisation.oci-containers.backend = "docker";

    virtualisation.docker = {
      enable = true;
      # Reclaim disk from the per-game images Wolf pulls. 806 GB of Steam
      # library leaves only ~285 GB free on this box, so unattended growth
      # matters more here than on a server.
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
    };

    # ============================================================
    # 🔑 DESKTOP INPUT ISOLATION — the load-bearing part of this module
    # ============================================================
    # Verbatim copy of upstream's 85-wolf.rules (stable branch). Inlined rather
    # than curl'd because a network fetch in a derivation is impure; re-check it
    # against upstream when bumping the image:
    #   https://github.com/games-on-whales/wolf/blob/stable/85-wolf.rules
    #
    # ⚠️ DO NOT trim this to just the uinput/uhid lines. Wolf's virtual gamepads
    # are created inside its container but appear as REAL devices in the HOST
    # kernel, so without the last three rules logind hands the active-seat
    # desktop user a uaccess ACL on them — and the streamed controller drives
    # the niri desktop as well as the game. Upstream issue #451.
    #
    # That is precisely the failure we already hit with Sunshine, whose
    # "Mouse passthrough (absolute)" device pinned the desktop cursor to the
    # captured monitor (see Claude/streaming.md). Sunshine has no equivalent
    # fix; Wolf's is these rules.
    #
    # How they work: park every "Wolf * virtual *" device on a phantom **seat9**
    # that no session owns, and strip the uaccess tag so logind cannot ACL it to
    # the desktop user. The container still gets the devices via the
    # `c 13:* rmw` device-cgroup rule, so the game is unaffected.
    #
    # Nothing niri- or NixOS-specific is needed on top of this: the isolation is
    # enforced by udev/logind below the compositor, so libinput never offers the
    # devices to niri in the first place.
    services.udev.extraRules = ''
      # Allows Wolf to access /dev/uinput (needed to create the virtual gamepad)
      KERNEL=="uinput", SUBSYSTEM=="misc", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput", TAG+="uaccess"

      # Allows Wolf to access /dev/uhid (needed for DualSense emulation)
      KERNEL=="uhid", MODE="0660", GROUP="input", TAG+="uaccess"

      # Wolf virtual controllers: gamepads (Xbox / DualSense / Nintendo), the
      # DualSense's "Touchpad" and "Motion Sensors" child devices, and its
      # /dev/hidraw* node. Matched on the "Wolf *virtual*" name glob. Both the
      # device's own name (ATTR, uinput pads) and any ancestor's (ATTRS, uhid
      # child devices) are matched; hidraw has no name in its parent chain, so
      # it matches the parent uevent's HID_NAME.
      SUBSYSTEM=="input",  ATTR{name}=="Wolf *virtual*",  MODE="0660", GROUP="input", ENV{ID_SEAT}="seat9", TAG-="uaccess"
      SUBSYSTEMS=="input", ATTRS{name}=="Wolf *virtual*", MODE="0660", GROUP="input", ENV{ID_SEAT}="seat9", TAG-="uaccess"
      KERNEL=="hidraw*",   ATTRS{uevent}=="*HID_NAME=Wolf *virtual*", MODE="0660", GROUP="input", ENV{ID_SEAT}="seat9", TAG-="uaccess"
    '';

    # uhid is not autoloaded on this kernel; uinput usually is, but be explicit
    # so a fresh install cannot come up without them.
    boot.kernelModules = [ "uinput" "uhid" ];

    # ============================================================
    # 🎮 GPU CLOCK GOVERNOR — required for smooth 4K streaming
    # ============================================================
    # Measured 2026-09-29 streaming Stray at 4K60: with the default `auto`
    # governor the RX 9060 XT sat at clock step 1 of 3 (1668 MHz) drawing 83 W
    # of a 182 W cap at 50 °C — nowhere near any limit, it simply never ramped.
    # The render+encode workload is bursty enough that the heuristic doesn't
    # trip. The result is frame starvation, NOT a bandwidth problem:
    #
    #   auto : 999-1820 MHz,  40-75 W,  stream TX 76-82 Mbps  (choppy)
    #   high : 2519-2779 MHz, 88-154 W, stream TX 95-117 Mbps (smooth)
    #
    # TX falling *below* the requested bitrate is the fingerprint — the encoder
    # isn't being fed enough frames. Packet loss stayed at zero throughout, so
    # raising the bitrate would have done nothing. ⚠️ Don't misdiagnose this as
    # a link problem; check `pp_dpm_sclk` before touching bitrate.
    #
    # `high` only pins the existing top DPM state — it does not overclock or
    # raise the power cap, and thermal/power limits are still enforced, so it
    # cannot hurt the card (measured under load: 70 °C junction against a
    # 110-115 °C throttle point, cooler than review samples). But it also holds
    # max clocks at IDLE, which wastes power and spins fans for nothing — hence
    # this is scoped to when a game session is actually running rather than
    # being set permanently.
    systemd.services.wolf-gpu-perf = {
      description = "Force high GPU clocks while a Wolf game session runs";
      after = [ "docker.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.docker ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "15s";
      };
      script = ''
        # Resolve the card that owns renderD128 — the dGPU. card0/card1
        # enumeration is NOT stable across boots, so this must not be
        # hardcoded. Kept deliberately consistent with WOLF_RENDER_NODE below;
        # if that ever changes, change this too.
        LEVEL=""
        for d in /sys/class/drm/card*/device; do
          if [ -e "$d/drm" ] && ls "$d/drm/" 2>/dev/null | grep -q '^renderD128$'; then
            LEVEL="$d/power_dpm_force_performance_level"
            break
          fi
        done
        if [ -z "$LEVEL" ] || [ ! -w "$LEVEL" ]; then
          echo "renderD128 perf-level knob not found; nothing to do" >&2
          exec sleep infinity
        fi

        want=auto
        while :; do
          # A Wolf *game* container means a session is live: those are named
          # WolfSteam_<uuid>, WolfRetroarch_<uuid>, ... The menu container is
          # Wolf-UI_<uuid>, and the hyphen means it can never match
          # ^Wolf[A-Za-z]+_ — so the menu alone correctly leaves clocks on auto.
          if docker ps --format '{{.Names}}' 2>/dev/null | grep -qE '^Wolf[A-Za-z]+_'; then
            want=high
          else
            want=auto
          fi
          cur=$(cat "$LEVEL" 2>/dev/null || echo unknown)
          if [ "$cur" != "$want" ]; then
            echo "$want" > "$LEVEL" 2>/dev/null \
              && echo "GPU perf level: $cur -> $want"
          fi
          sleep 15
        done
      '';
    };

    # ============================================================
    # 🧹 STUCK-PAD REAPER — the Wolf/Steam input-bleed fix
    # ============================================================
    # DIAGNOSED 2026-10-03, after "the Wolf session is bleeding into my Steam":
    # controller input flashing, intermittent keyboard/mouse lockups, and a
    # generally glitchy desktop Steam.
    #
    # WHAT HAPPENS. Moonlight's own quit-stream shortcut is the controller chord
    # L1 + R1 + Select + Start. Quit a stream that way and Moonlight sends the
    # four presses, then tears the connection down *before* the matching
    # releases arrive. Wolf never reaps the session, so its virtual DualSense
    # stays alive with all four buttons held — verified via EVIOCGKEY:
    #
    #   event256 "Wolf DualSense (virtual) pad"
    #     -> BTN_TL, BTN_TR, BTN_SELECT, BTN_START  held, emitting nothing
    #
    # 🔑 WHY THE seat9 RULES DO NOT SAVE US HERE. They park the pads on seat9
    # and strip `uaccess`, which correctly hides them from niri (confirmed: niri
    # holds no FD on the pad). But the nodes remain `crw-rw---- root:input` and
    # `rock` is in `input`, and **Steam does not ask logind — it scans
    # /dev/input and /dev/hidraw* directly.** Desktop Steam therefore adopts the
    # stuck virtual pad as its own Controller 0; its log is unambiguous:
    #
    #   Product: DualSense Wireless Controller
    #   Controller using HIDAPI driver, vid=0x054c, pid=0x0ce6
    #   ConfigSet - found config set file on-disk: .../configset_controller_ps5.vdf
    #
    # ...with no physical DualSense attached to Sisyphus at all. Steam then
    # re-emits it as `Microsoft X-Box 360 pad 0` (28de:11ff) to the running
    # game, propagating the stuck chord. A permanently-held chord means Steam
    # Input never settles, so it re-adopts bindings every ~30 s ("adopting
    # binding 101, 102, 103, ...") — that is the flashing — and the same layer
    # synthesises keyboard/mouse from a controller it believes is active, which
    # is the lockups.
    #
    # ⚠️ PERMISSIONS CANNOT FIX THIS, so don't try. Both Steams run as uid 1000:
    # the container holds gid 174 (`input`) via its own supplementary groups,
    # and niri reads the *real* mouse through that same group (there is no
    # `user:rock` ACL on /dev/input/event15). Tightening mode/group breaks niri
    # and the container together, and removing `rock` from `input` breaks niri.
    #
    # ⚠️ Because autoStart is true, Wolf is always up, so a left-open session
    # coexists with desktop Steam BY DEFAULT. That is also the shared-steamapps
    # hazard in Claude/wolf.md ("only one Steam may touch steamapps at a time"),
    # not just an input problem.
    #
    # ❌ REJECTED: counting `[ENET] Failed to send packet`. Wolf spams this when
    # it is still sending to a client that has gone, so it looks like the ideal
    # orphan signal — and it is not. Measured over the real 15.6 h orphaned
    # session: only **75 minutes** contained any failures at all, median 3/min,
    # p90 13. A *healthy* stream hits 3-4 in a minute too. The spam is bursty,
    # not sustained, so no count-per-window threshold separates the two. Don't
    # re-propose it.
    #
    # ✅ WHAT THIS DETECTS INSTEAD: the harm itself, not a proxy for it. A Wolf
    # virtual pad that (a) reports buttons held via EVIOCGKEY, and (b) emits
    # nothing at all for a full 60 s window, is latched. Both halves are needed:
    # a real player holding buttons still produces a constant event stream (the
    # DualSense reports continuously, and its Motion Sensors child device even
    # more so), whereas the orphaned pad is completely silent — a 3 s raw read
    # of event256 returned zero bytes while four buttons were held. That makes
    # the signature tight enough to act on, and it is independent of any
    # upstream log message.
    #
    # ACTION: restart docker-wolf, which ends the session and takes the virtual
    # pads with it — verified 2026-10-03: stopping the unit removed
    # event256-258, hidraw16 and js1-js3, leaving only the real js0. Restarting
    # rather than stopping the app container alone, because the pads belong to
    # Wolf's *session*, not to the game container, so stopping the child is not
    # guaranteed to clear them.
    systemd.services.wolf-stuck-pad-reaper = {
      description = "Reap Wolf virtual pads left latched by a quit-chord disconnect";
      after = [ "docker.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.systemd ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "30s";
      };
      script = ''
        while :; do
          sleep 60
          if ${pkgs.python3}/bin/python3 ${stuckPadProbe}; then
            echo "latched Wolf pad confirmed -> restarting docker-wolf to clear the session"
            # This unit is not part of docker-wolf, so restarting it cannot
            # kill this reaper.
            systemctl restart docker-wolf || echo "restart failed" >&2
            # Let Wolf come back before probing again.
            sleep 120
          fi
        done
      '';
    };

    # 🎮 Don't let DESKTOP Steam adopt Wolf's virtual DualSense. Belt-and-braces
    # for the same stuck-pad bleed — the reaper above is the actual fix; this
    # only narrows the window. Lives here rather than in
    # Modules/Gaming/steam.nix because it is purely a Wolf concern: on a host
    # without Wolf it would do nothing but ignore a real pad. steam.nix feeds
    # my.steam.extraEnv into Steam's FHS environment, so it reaches Steam and
    # the games it launches and nothing else — which also means this module
    # requires steam.nix to be imported (true wherever Wolf runs: a Wolf host
    # without desktop Steam has no bleed to prevent, and would fail eval here
    # loudly rather than silently).
    #
    # Wolf creates its virtual pads in its container, but they appear as
    # REAL devices in the host kernel. Wolf's udev rules park them on a
    # phantom seat9, which hides them from niri — but NOT from Steam, which
    # scans /dev/input and /dev/hidraw* directly instead of asking logind.
    # So desktop Steam picks up a streaming session's pad as its own
    # Controller 0 (its log: "Controller using HIDAPI driver, vid=0x054c,
    # pid=0x0ce6" with nothing physically attached), and if that pad was
    # left mid-chord by Moonlight's L1+R1+Select+Start quit shortcut, the
    # held buttons propagate into whatever is running on the desktop.
    #
    # 0x054c/0x0ce6 is Sony's DualSense. ⚠️ This is a VID/PID match, so it
    # ignores a GENUINE DualSense plugged into Sisyphus too — accepted
    # because the real pad lives on Eclipse (couch/TV box) and reaches
    # games through the stream, never through desktop Steam. If you ever
    # want to use a DualSense directly at the desk, remove this line and
    # rely on the reaper alone. (Steam only: RPCS3 and anything else started
    # outside Steam never see this variable.)
    #
    # ⚠️ UNVERIFIED as of 2026-10-03: this is the documented SDL ignore
    # list and games inherit it, but whether Steam's bundled SDL honours it
    # for Steam's OWN controller enumeration (the HIDAPI path above) has
    # not been confirmed live. To check: start a Wolf session, then start
    # desktop Steam, and confirm no new `vid=0x054c` line appears in
    # ~/.local/share/Steam/logs/controller.txt.
    my.steam.extraEnv.SDL_GAMECONTROLLER_IGNORE_DEVICES = "0x054c/0x0ce6";

    # Host side of Wolf's XDG_RUNTIME_DIR bind mount (see volumes below).
    # Docker would create this itself, but declaring it keeps the ownership and
    # mode defined rather than inherited from whatever ran first. /run is tmpfs,
    # so it is correctly empty of stale sockets on every boot.
    systemd.tmpfiles.rules = [ "d /run/wolf 0755 root root -" ];

    # 🧹 wolf-bridge — list Wolf's sessions and stop a stuck one from the
    # Eclipse panel on Asgard's Glance (Resources/Wolf-Bridge/wolf-bridge.py has
    # the API details). Wolf's own API is /run/wolf/wolf.sock, which only root
    # can write to, on THIS machine; the dashboard lives on Asgard. This exposes
    # exactly two operations (GET /sessions, POST /sessions/<id>/stop) on :9560.
    #
    # Reachability: :9560 is NOT in allowedTCPPorts, so the LAN can't reach it;
    # tailscale0 is a trusted interface (Modules/Core/tailscale.nix), so every
    # tailnet node can. Two layers narrow that to Asgard: systemd's IP firewall
    # (IPAddressAllow/Deny below) and the bridge's own peer allowlist.
    systemd.services.wolf-bridge = let
      allowed = [ "127.0.0.1" "::1" self.lib.tailnet.asgard ];
    in {
      description = "HTTP bridge to Wolf's session API for the Eclipse panel";
      after = [ "docker-wolf.service" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        WOLF_SOCKET = "/run/wolf/wolf.sock";
        WOLF_BRIDGE_PORT = "9560";
        WOLF_BRIDGE_ALLOW = lib.concatStringsSep "," allowed;
      };
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${../../Resources/Wolf-Bridge/wolf-bridge.py}";
        Restart = "always";
        RestartSec = 5;
        # Holds first-seen.json: Wolf's API has no session start time, so the
        # bridge records when it first saw each one. Survives a bridge restart,
        # not a reboot — neither do Wolf's sessions.
        RuntimeDirectory = "wolf-bridge";
        RuntimeDirectoryPreserve = "restart";

        # Root only because the socket is root-owned 0755 (connect() needs
        # write). No capabilities at all: as the socket's owner, uid 0 needs
        # none to connect.
        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ "/run/wolf" ];
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
        IPAddressDeny = "any";
        IPAddressAllow = allowed;
      };
    };

    # The Moonlight protocol ports. Same set Sunshine opens in Modules/Gaming/sunshine.nix
    # — harmless to declare twice since only one daemon runs at a time.
    networking.firewall.allowedTCPPorts = [ 47984 47989 48010 ];
    networking.firewall.allowedUDPPorts = [ 47998 47999 48000 48100 48200 ];

    virtualisation.oci-containers.containers.wolf = {
      image = "ghcr.io/games-on-whales/wolf:stable";

      # host networking: Moonlight does its own port handling and client
      # discovery, and Wolf hands those ports to child containers.
      extraOptions = [
        "--network=host"
        # major 13 is the input subsystem — lets Wolf hand /dev/input/event*
        # through to the containers it spawns.
        "--device-cgroup-rule=c 13:* rmw"
        "--device=/dev/dri"
        "--device=/dev/uinput"
        "--device=/dev/uhid"
      ];

      volumes = [
        # Wolf's own state: pairing certs, config.toml, and per-profile Steam
        # data under profile_data/<id>/WolfSteam/.
        "/etc/wolf:/etc/wolf:rw"
        # Wolf spawns a container per running game through this socket.
        "/var/run/docker.sock:/var/run/docker.sock:rw"
        # Upstream mounts all of /dev plus udev's runtime dir so hotplugged
        # controllers reach the session containers.
        "/dev/:/dev/:rw"
        "/run/udev:/run/udev:rw"
        # 🔑 XDG_RUNTIME_DIR. Holds BOTH wolf.sock (the API) and pulse-socket
        # (the audio server), and Wolf must mount both into every per-game
        # child container it spawns. To do that it translates its own container
        # paths to host paths by reading its own mount list — see the log line
        # "Detected mounted /etc/wolf in the host as /etc/wolf". An unmounted
        # runtime dir therefore cannot be handed to children, and Wolf logs
        # "ERROR | Unable to find docker mount for path: ..." at startup.
        #
        # /run/user/wolf is the image's own ENV XDG_RUNTIME_DIR (it also
        # declares VOLUME /run/user/wolf/). Do NOT override that env var — an
        # earlier revision set it to /tmp/sockets, which produced exactly the
        # error above and would have left games with no audio and no API.
        #
        # The host side must be /run/wolf specifically: the default config.toml
        # mounts the API socket into the Wolf-UI app as
        # '/var/run/wolf/wolf.sock:/var/run/wolf/wolf.sock', and /var/run is a
        # symlink to /run, so /run/wolf/wolf.sock is precisely the host path
        # that entry already expects. Pick anything else and config.toml has to
        # be hand-edited, which is imperative state we don't want.
        "/run/wolf:/run/user/wolf:rw"
      ];

      environment = {
        # Render on the RX 9060 XT (renderD128), NOT the Ryzen iGPU
        # (renderD129). Render nodes are shared and not seat-bound — verified
        # 2026-09-27 with 8 processes holding renderD128 at once — so this does
        # not take the GPU away from the niri desktop.
        WOLF_RENDER_NODE = "/dev/dri/renderD128";
        WOLF_ENCODER_NODE = "/dev/dri/renderD128";
        WOLF_LOG_LEVEL = "INFO";
        # NOTE: XDG_RUNTIME_DIR is deliberately NOT set here. The image already
        # sets it to /run/user/wolf and declares a VOLUME for it; we bind-mount
        # that path instead (see volumes above). Overriding it breaks the
        # container-path → host-path translation Wolf needs to pass wolf.sock
        # and pulse-socket into the game containers it spawns.
        HOST_APPS_STATE_FOLDER = "/etc/wolf";

        # 🎮 Disable fake-udev. REQUIRED for gamepads to work inside Proton
        # games — see upstream issue #81 ("Fix Steam input in unprivileged
        # containers").
        #
        # The image ships a `fake-udev` binary (/etc/wolf/fake-udev) and points
        # this variable at it by default, which is why we can't just leave it
        # unset: Wolf's check is
        #   use_fake_udev = !path.empty() || exists(path)
        # so an empty string is the only way to turn it off.
        #
        # THE BUG IT FIXES: Steam Input creates its virtual controller through
        # /dev/uinput, and games enumerate gamepads through **udev** — but
        # fake-udev does not relay those udev events into the container. The
        # kernel events exist, the udev ones don't. Steam itself is unaffected
        # because it also scans /dev/input directly, which is exactly why the
        # pad works in Big Picture and is invisible to the game. Verified here
        # 2026-09-28: raw reads of the virtual pad on the host returned a full
        # event stream with no exclusive grab, so the devices were never the
        # problem — only their discoverability.
        #
        # TRADE-OFF, ACCEPTED 2026-09-28: this exposes input devices across
        # containers, so concurrent streaming sessions would see each other's
        # pads. User confirmed Eclipse is a single-seat TV/couch box and there
        # will never be a second simultaneous streamer, so this costs nothing.
        #
        # Note this does NOT weaken what Wolf is actually bought for here: the
        # stream still gets its own virtual display instead of occupying a real
        # monitor and fighting the desktop for input focus, which is what
        # Sunshine could not do. Only the concurrent-streamers case is given up.
        # It also does NOT touch the seat9 rules in this module — those isolate
        # the pads from the *host niri desktop*, which is a different boundary
        # and still enforced.
        WOLF_DOCKER_FAKE_UDEV_PATH = "";
      };

      # Starts on boot, so the TV box is always ready without touching the PC.
      #
      # Changed false → true on 2026-09-28 once Wolf was proven end-to-end. This
      # is only safe because `Modules/Gaming/sunshine.nix` now has `autoStart = false`
      # — the two CANNOT both run (identical Moonlight ports). Those two
      # settings are a matched pair: never set both true.
      autoStart = true;
    };

    # Not in nixpkgs, so the image is pulled at runtime rather than pinned in the
    # store. That makes this the one genuinely non-reproducible piece here —
    # `:stable` can move under you. Now that Wolf is the live host rather than a
    # trial, pinning a digest is the outstanding fix for that.
  };
}
