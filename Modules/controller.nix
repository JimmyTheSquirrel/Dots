{ self, inputs, ... }: {
  flake.nixosModules.controller = { pkgs, ... }: let
    controllerScript = pkgs.writeText "controller-mapper.py" ''
      """DualSense controller mapper for Niri desktop navigation via Sunshine/Moonlight.

      Touchpad handles mouse — no cursor emulation here.

      PS button   -> toggle desktop mode on/off (default: on)

      -- Desktop mode only --
      Left stick  -> arrow keys (menu/list navigation, with auto-repeat)
      D-Pad       -> Super+Arrow (Niri window/workspace focus)
      X (South)   -> Enter
      Circle (East)   -> Escape
      Triangle (North) -> close focused window
      Square (West)    -> app launcher
      L1          -> wallpaper picker
      R1          -> toggle overview
      Options     -> power menu
      """
      import evdev
      from evdev import ecodes as e, UInput
      import subprocess
      import threading
      import time

      DEADZONE = 8000       # Stick deadzone (axis range is -32767 to 32767)
      INITIAL_DELAY = 0.40  # Seconds before auto-repeat kicks in
      REPEAT_INTERVAL = 0.12  # Seconds between repeated arrow keys while held

      # Stick direction -> arrow key
      DIR_KEYS = {
          "left":  e.KEY_LEFT,
          "right": e.KEY_RIGHT,
          "up":    e.KEY_UP,
          "down":  e.KEY_DOWN,
      }

      # D-Pad -> Super+Arrow key (Niri window/workspace focus via existing binds)
      DPAD_KEYS = {
          ("x", -1): e.KEY_LEFT,
          ("x",  1): e.KEY_RIGHT,
          ("y", -1): e.KEY_UP,
          ("y",  1): e.KEY_DOWN,
      }

      # Button press -> shell command
      BUTTON_COMMANDS = {
          e.BTN_NORTH: "niri msg action close-window",
          e.BTN_WEST:  "noctalia-shell ipc call launcher toggle",
          e.BTN_TL:    "skwd wall toggle",
          e.BTN_TR:    "niri msg action toggle-overview",
          e.BTN_START: "noctalia-shell ipc call sessionMenu toggle",
      }

      # Face buttons -> key presses
      FACE_KEYS = {
          e.BTN_SOUTH: e.KEY_RETURN,
          e.BTN_EAST:  e.KEY_ESCAPE,
      }


      def run(cmd):
          subprocess.Popen(
              cmd, shell=True,
              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
          )


      def notify(msg):
          run(f"notify-send -t 1500 -i input-gaming 'Controller' '{msg}'")


      def get_direction(lx, ly, deadzone):
          """Dominant axis direction from analog stick, or None if in deadzone."""
          ax, ay = abs(lx), abs(ly)
          if ax <= deadzone and ay <= deadzone:
              return None
          if ax >= ay:
              return "right" if lx > 0 else "left"
          else:
              return "down" if ly > 0 else "up"


      def find_gamepad():
          while True:
              for path in evdev.list_devices():
                  try:
                      dev = evdev.InputDevice(path)
                      caps = dev.capabilities()
                      keys = caps.get(e.EV_KEY, [])
                      if e.BTN_SOUTH in keys:
                          return dev
                  except Exception:
                      pass
              print("No gamepad found, waiting for Moonlight client...", flush=True)
              time.sleep(3)


      def main():
          vdev = UInput(
              {
                  e.EV_KEY: [
                      e.KEY_LEFT, e.KEY_RIGHT, e.KEY_UP, e.KEY_DOWN,
                      e.KEY_RETURN, e.KEY_ESCAPE,
                      e.KEY_LEFTMETA,
                  ],
              },
              name="controller-mapper",
          )

          lx = ly = 0
          lock = threading.Lock()
          desktop_mode = True

          def tap_key(key):
              """Send a single key press + release."""
              vdev.write(e.EV_KEY, key, 1)
              vdev.write(e.EV_KEY, key, 0)
              vdev.syn()

          def send_super_arrow(key):
              """Super+Arrow combo for Niri focus binds."""
              vdev.write(e.EV_KEY, e.KEY_LEFTMETA, 1)
              vdev.write(e.EV_KEY, key, 1)
              vdev.syn()
              time.sleep(0.05)
              vdev.write(e.EV_KEY, key, 0)
              vdev.write(e.EV_KEY, e.KEY_LEFTMETA, 0)
              vdev.syn()

          def stick_loop():
              """Converts left stick deflection into repeating arrow key taps."""
              direction = None
              dir_start = 0.0
              last_fire = 0.0

              while True:
                  if desktop_mode:
                      with lock:
                          cur_lx, cur_ly = lx, ly
                      now = time.monotonic()
                      cur_dir = get_direction(cur_lx, cur_ly, DEADZONE)

                      if cur_dir != direction:
                          direction = cur_dir
                          dir_start = now
                          last_fire = 0.0
                          if cur_dir is not None:
                              tap_key(DIR_KEYS[cur_dir])
                              last_fire = now
                      elif cur_dir is not None:
                          held = now - dir_start
                          if held >= INITIAL_DELAY and (now - last_fire) >= REPEAT_INTERVAL:
                              tap_key(DIR_KEYS[cur_dir])
                              last_fire = now

                  time.sleep(0.016)

          threading.Thread(target=stick_loop, daemon=True).start()

          prev_hx = prev_hy = 0

          while True:
              device = find_gamepad()
              print(f"Gamepad connected: {device.name}", flush=True)
              try:
                  for event in device.read_loop():
                      if event.type == e.EV_KEY:
                          # PS button toggles desktop mode
                          if event.code == e.BTN_MODE and event.value == 1:
                              desktop_mode = not desktop_mode
                              if desktop_mode:
                                  notify("Desktop mode ON")
                                  print("Desktop mode ON", flush=True)
                              else:
                                  notify("Game mode (desktop nav off)")
                                  print("Game mode ON", flush=True)
                              continue

                          if not desktop_mode:
                              continue

                          # X / Circle -> Enter / Escape (press + release)
                          face_key = FACE_KEYS.get(event.code)
                          if face_key is not None:
                              if event.value == 1:
                                  tap_key(face_key)
                          elif event.value == 1:
                              cmd = BUTTON_COMMANDS.get(event.code)
                              if cmd:
                                  run(cmd)

                      elif event.type == e.EV_ABS:
                          if event.code == e.ABS_X:
                              with lock:
                                  lx = event.value
                          elif event.code == e.ABS_Y:
                              with lock:
                                  ly = event.value

                          elif event.code == e.ABS_HAT0X:
                              if desktop_mode and event.value != 0 and event.value != prev_hx:
                                  key = DPAD_KEYS.get(("x", event.value))
                                  if key:
                                      threading.Thread(
                                          target=send_super_arrow, args=(key,), daemon=True
                                      ).start()
                              prev_hx = event.value
                          elif event.code == e.ABS_HAT0Y:
                              if desktop_mode and event.value != 0 and event.value != prev_hy:
                                  key = DPAD_KEYS.get(("y", event.value))
                                  if key:
                                      threading.Thread(
                                          target=send_super_arrow, args=(key,), daemon=True
                                      ).start()
                              prev_hy = event.value

              except OSError:
                  print("Gamepad disconnected.", flush=True)
                  with lock:
                      lx = ly = 0

      if __name__ == "__main__":
          main()
    '';

    controllerMapper = pkgs.writeShellApplication {
      name = "controller-mapper";
      runtimeInputs = [
        (pkgs.python3.withPackages (ps: [ ps.evdev ]))
        pkgs.libnotify
      ];
      text = "exec python3 ${controllerScript}";
    };
  in {
    users.users.rock.extraGroups = [ "input" "uinput" ];

    environment.systemPackages = [ controllerMapper ];

    home-manager.users.rock.systemd.user.services.controller-mapper = {
      Unit = {
        Description = "DualSense controller mapper for Niri (Moonlight/Sunshine)";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${controllerMapper}/bin/controller-mapper";
        Restart = "on-failure";
        RestartSec = "5s";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
