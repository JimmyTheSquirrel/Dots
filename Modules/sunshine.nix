{ ... }: {
  flake.nixosModules.sunshine = { activeUser, ... }: {
    # Sunshine game streaming server
    services.sunshine = {
      enable = true;
      autoStart = true;
      capSysAdmin = true;  # Required for KMS display capture on Wayland
      openFirewall = true;
    };

    # uinput for virtual gamepad/keyboard/mouse input from client
    hardware.uinput.enable = true;

    # User needs video + input group access for display/input capture
    users.users.${activeUser}.extraGroups = [ "video" "input" ];
  };
}
