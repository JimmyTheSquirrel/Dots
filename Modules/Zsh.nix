{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    oh-my-zsh = {
      enable = true;
      theme = "agnosterzak";
      plugins = [ "git" "sudo" "z" ];
    };

    shellAliases = {
      ll = "ls -lh";
      la = "ls -lha";
      gs = "git status";
    };

    # initExtra is deprecated on your HM; use initContent
    initContent = ''
      # --------------------------------
      # --- Dots helpers ---------------
      # --------------------------------
      # In your Zsh.nix (or wherever your shell functions live)

system-rebuild() {
  (
    cd ~/Dots || exit 1

    echo -e "\n\033[1;34m==> Rebuilding NixOS system...\033[0m"
    sudo nixos-rebuild switch --flake . || {
      echo -e "\033[1;31mNixOS rebuild failed\033[0m"
      exit 1
    }

    echo -e "\n\033[1;34m==> Rebuilding Home Manager...\033[0m"
    home-manager switch --flake . || {
      echo -e "\033[1;31mHome Manager rebuild failed\033[0m"
      exit 1
    }

    echo -e "\n\033[1;32m==> All done!\033[0m"
  )
}


      # ------------------------------------------------------------------------

      # One-shot Git sync in ~/Dots.
      # - If a message is given: add+commit first
      # - If tree is dirty: stash (including untracked), pull --rebase, then pop
      # - Finally push
      git-sync() {
        (
          set -e
          cd ~/Dots || exit 1

          # optional commit
          if [[ -n "$1" ]]; then
            git add -A
            git commit -m "$1" || echo "Nothing to commit."
          fi

          # detect any changes (tracked or untracked)
          if [[ -n "$(git status --porcelain=2 --untracked-files=all)" ]]; then
            STASH_MSG="autosync-$(date +%Y%m%d-%H%M%S)"
            echo "↪ repo dirty — stashing as $STASH_MSG"
            git stash push -u -m "$STASH_MSG"
            HAD_STASH=1
          fi

          echo "↪ pulling (rebase)…"
          git pull --rebase

          if [[ -n "$HAD_STASH" ]]; then
            echo "↪ restoring stashed changes…"
            git stash pop || echo "⚠ stash pop had conflicts; resolve and continue"
          fi

          echo "↪ pushing…"
          git push
        )
      }

      # ------------------------------------------------------------------------

      # Show Fastfetch on startup (only in Kitty)
      if [[ $- == *i* ]] && [[ -n "$KITTY_WINDOW_ID" ]]; then
        command -v fastfetch >/dev/null && fastfetch
      fi

      # ------------------------------------------------------------------------

      # Override 'clear' so it re-runs Fastfetch (Kitty only)
      clear() {
        command clear "$@"
        if [[ $- == *i* ]] && [[ -n "$KITTY_WINDOW_ID" ]]; then
          command -v fastfetch >/dev/null && fastfetch
        fi
      }

      # ------------------------------------------------------------------------
    '';
  };
}
