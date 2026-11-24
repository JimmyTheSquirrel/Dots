# Sisyphus — rock's main desktop. AMD, Niri, local GRUB profile "sisyphus".
# Hardware: ./_hardware.nix.
{ self, ... }: {
  flake.nixosConfigurations.rock-Sisyphus = self.lib.mkHost {
    activeUser = "rock";
    hostName = "Sisyphus";
    stateVersion = "25.05";

    modules = [
      ./_hardware.nix

      self.nixosModules.base
      self.nixosModules.desktop
      self.nixosModules.grub
      self.nixosModules.plymouth
      self.nixosModules.sddm
      self.nixosModules.polkit
      self.nixosModules.luciole
      self.nixosModules.niri
      self.nixosModules.audio
      self.nixosModules.locale
      self.nixosModules.steam
      self.nixosModules.sops
      self.nixosModules.zsh
      self.nixosModules.starship
      self.nixosModules.kitty
      self.nixosModules.helium
      self.nixosModules.git
      self.nixosModules.fastfetch
      self.nixosModules.btop
      self.nixosModules.vscodium
      self.nixosModules.noctalia
      self.nixosModules.skwd
      self.nixosModules.navi
      # rock's admin helpers: system-rebuild, git-sync, nix-gc, apollo-*.
      self.nixosModules.deploy-tools
      self.nixosModules.spicetify
      self.nixosModules.discord
      self.nixosModules.tailscale
      self.nixosModules.sunshine
      # Wolf is the live Moonlight host and autostarts. Sunshine stays installed
      # with autoStart = false — the two bind the same Moonlight ports, so at most
      # one may run. See Modules/Gaming/wolf.nix.
      self.nixosModules.wolf
      self.nixosModules.rpcs3
      # Battle.net under Proton with no Steam client in the loop (umu-run).
      # Modules/Gaming/battlenet.nix has the two things about it that are not
      # declarative, and why they cannot be.
      self.nixosModules.battlenet
      # Odysseus — the self-hosted AI workspace. Trialled 2026-11-11 and taken
      # back out; the module stays in the tree (inert while unlisted) so it is
      # one line to bring back. Modules/Apps/odysseus.nix has the full story.
      # self.nixosModules.odysseus

      {
        # NieR: Automata greeter, with FOT-Rodin patched in (Modules/Boot/sddm.nix).
        my.sddm.theme = "nier-automata";

        # ── The HP 330 combo is DEAD TO THIS MACHINE ──────────────────────────
        # `03f0:6341` is an HP 330 Wireless Mouse and Keyboard Combo receiver.
        # It is NOT used — rock types on a Corsair Slipstream and points with a
        # Corsair M65 — and it has produced phantom input twice, on two
        # different axes, each time disguised as something else:
        #
        #   2026-10-01  BTN_MIDDLE + BTN_SIDE + BTN_EXTRA LATCHED down, then the
        #               device went silent. Symptom: Mod+drag stopped working,
        #               because niri will not start an interactive move while a
        #               button is held. Looked like a stuck modifier.
        #   2026-11-14  BTN_LEFT latched AND a relentless REL_HWHEEL +1 /
        #               HI_RES +120 at ~11 events a second, untouched. Symptom:
        #               the view scrolled to the far right forever and fought
        #               Mod+scroll. Looked like a jammed arrow key.
        #
        # ⚠ The dongle was NEVER FOUND. It survived unplugging the entire rear
        # panel, the keyboard dongle and the headset dongle; it sits on the CPU
        # controller (0000:12:00.4, port 1 of 2, nothing else on either CPU
        # controller) and had been connected since the 2026-11-11 boot. It is in
        # a top-panel, front, or internal-header socket somewhere in the case.
        # Since it cannot be unplugged, it is killed in software instead.
        #
        # Rule 1 is the actual nuke: deauthorizing the USB device makes the
        # kernel refuse to configure it, so no interfaces are claimed, usbhid
        # never binds, and NO input nodes are created at all. Nothing downstream
        # can see it, including anything reading evdev directly rather than
        # going through libinput.
        #
        # Rule 2 is deliberate belt-and-braces: if the device is ever manually
        # re-authorized (echo 1 > .../authorized) to test something, libinput
        # still refuses to surface it to niri.
        #
        # ⚠ To undo BOTH, this block has to be removed and the host rebuilt —
        # which is the point.
        services.udev.extraRules = ''
          ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="03f0", ATTR{idProduct}=="6341", ATTR{authorized}="0"
          ENV{ID_VENDOR_ID}=="03f0", ENV{ID_MODEL_ID}=="6341", ENV{LIBINPUT_IGNORE_DEVICE}="1"
        '';
      }
    ];
  };
}
