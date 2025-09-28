{ config, pkgs, ... }:

{
  # bring in your per-app modules
  imports = [
    ./Modules/Brave.nix
    ./Modules/Kitty.nix
  ];

  # user basics
  home.username = "rock";
  home.homeDirectory = "/home/rock";
  home.stateVersion = "25.05";

  # user packages (add more if you want HM to install them)
  home.packages = with pkgs; [
    # example: bat ripgrep fd
  ];

  # dotfiles managed by HM (leave commented unless you have the file)
  home.file = {
    # ".screenrc".source = "${config.home.homeDirectory}/dotfiles/screenrc";
  };

  # env vars if you need any
  home.sessionVariables = { };

  # zsh + oh-my-zsh
programs.zsh = {
  enable = true;
  enableCompletion = true;
  enableAutosuggestions = true;   # <-- fix
  syntaxHighlighting.enable = true;

  oh-my-zsh = {
    enable = true;
    theme = "agnoster";
    plugins = [ "git" "sudo" "z" ];
  };

  shellAliases = {
    ll = "ls -lh";
    la = "ls -lha";
    gs = "git status";
  };
};


  # let Home Manager manage itself
  programs.home-manager.enable = true;
}
