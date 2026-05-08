{ ... }: {
  flake.nixosModules.sunshine = { activeUser, pkgs, ... }: {
    # Sunshine game streaming server
    services.sunshine = {
      enable = true;
      autoStart = false;  # Disabled — we use a system service so it runs during SDDM too
      capSysAdmin = true;  # Sets up KMS capture capabilities on the package
      openFirewall = true;
    };

    # System-level service so Sunshine is reachable via Moonlight from SDDM onwards
    systemd.services.sunshine = {
      description = "Sunshine game streaming server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        User = activeUser;
        ExecStart = "${pkgs.sunshine}/bin/sunshine";
        Restart = "on-failure";
        RestartSec = 3;
        # KMS display capture requires CAP_SYS_ADMIN
        AmbientCapabilities = "CAP_SYS_ADMIN";
        CapabilityBoundingSet = "CAP_SYS_ADMIN";
        # Required for PipeWire audio capture after user logs in
        Environment = "XDG_RUNTIME_DIR=/run/user/1000";
      };
    };

    # uinput for virtual gamepad/keyboard/mouse input from client
    hardware.uinput.enable = true;

    # User needs video + input group access for display/input capture
    users.users.${activeUser}.extraGroups = [ "video" "input" ];
  };
}
