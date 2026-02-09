# Modules/Brrtfetch.nix
{ pkgs, ... }:

let
  brrtfetch = pkgs.rustPlatform.buildRustPackage rec {
    pname = "brrtfetch";
    version = "0.1.0";

    src = pkgs.fetchFromGitHub {
      owner = "ferrebarrat";
      repo = "brrtfetch";
      rev = "cf4fcdde1c2b68e6c05fb05ed8bfbb4f2b65d4c2";  # Latest commit as of repo
      sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";  # You'll need to update this
    };

    cargoHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";  # You'll need to update this

    nativeBuildInputs = [ pkgs.pkg-config ];
    
    buildInputs = [
      pkgs.libGL
      pkgs.xorg.libX11
      pkgs.xorg.libXrandr
    ];

    meta = with pkgs.lib; {
      description = "A system information tool written in Rust";
      homepage = "https://github.com/ferrebarrat/brrtfetch";
      license = licenses.gpl3;
      platforms = platforms.linux;
    };
  };
in
{
  home.packages = [ brrtfetch ];

  # Optional: Create a config file for brrtfetch
  # The tool looks for config in ~/.config/brrtfetch/config.toml
  xdg.configFile."brrtfetch/config.toml".text = ''
    # Brrtfetch configuration
    # Using default settings - customize as needed
    
    [display]
    # Show ASCII logo
    show_logo = true
    
    # Color scheme (you can customize this to match your Gruvbox theme)
    # Available: default, gruvbox, nord, dracula, etc.
    color_scheme = "gruvbox"
    
    [modules]
    # Enable/disable specific info modules
    os = true
    kernel = true
    packages = true
    shell = true
    wm = true
    terminal = true
    cpu = true
    gpu = true
    memory = true
    uptime = true
  '';
}
