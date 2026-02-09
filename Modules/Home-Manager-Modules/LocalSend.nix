{
  config,
  pkgs,
  ...
}: {
  # Enable the LocalSend application
  programs.localsend.enable = true;
  # Optionally open the firewall to allow discovery
  programs.localsend.openFirewall = true;
}
