{ config, pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    # NvChad doesn't really need extraConfig here, we just clone it if missing
  };

  home.activation.installNvChad = pkgs.lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "$HOME/.config/nvim" ]; then
      git clone https://github.com/NvChad/NvChad "$HOME/.config/nvim" --depth 1
    fi
  '';
}
