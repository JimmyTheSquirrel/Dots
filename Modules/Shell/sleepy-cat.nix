# A small animated sleeping cat for the terminal.
#
# Nothing in nixpkgs fits — nyancat, cbonsai, asciiquarium and terminal-parrot
# are all the wrong animal or the wrong mood — so it is a few frames of ASCII
# and a sleep loop.
#
# ⚠ The art deliberately contains NO apostrophes. Two in a row ('') terminate a
# Nix indented string, so classic ASCII cats (which are full of them) cannot be
# pasted in as-is without escaping every pair as '''. Tildes read the same and
# avoid the whole problem.
#
# Two entry points:
#   sleepy-cat         loop until Ctrl-C (a toy)
#   sleepy-cat --once  one breath cycle then exit — used as the shell greeting.
#                      It does hold the prompt for that one cycle: four frames
#                      at 0.45 s, ~1.8 s, before the shell is usable.
{ ... }: {
  flake.nixosModules.sleepy-cat = { pkgs, activeUser, ... }: {
    home-manager.users.${activeUser}.home.packages = [
      (pkgs.writeShellScriptBin "sleepy-cat" ''
        C=$(printf "\033[38;5;180m")
        R=$(printf "\033[0m")

        # Frames differ only in the drifting Z, which reads as breathing.
        frame() {
          printf "%s       |\\      _,,,---,,_%s\n"      "$C" "$R"
          printf "%s %-5s /,\`.-~~-.  ;-;;,_%s\n"        "$C" "$1" "$R"
          printf "%s      |,4-  ) )-,_. ,\\ (%s\n"       "$C" "$R"
          printf "%s     ---~~(_/--~  \`-~\\_)%s\n"      "$C" "$R"
        }

        rewind() { printf "\033[4A"; }

        cycle() {
          for z in "z" " z" "  Z" " z"; do
            frame "$z"
            sleep 0.45
            rewind
          done
        }

        if [ "''${1:-}" = "--once" ]; then
          cycle
          frame "z"
          exit 0
        fi

        # Hide the cursor while looping, and always put it back — otherwise
        # Ctrl-C leaves the terminal with an invisible cursor.
        printf "\033[?25l"
        trap 'printf "\033[?25h\n"; exit 0' INT TERM
        while true; do cycle; done
      '')
    ];
  };
}
