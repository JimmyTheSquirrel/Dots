{ ... }: {
  # Asgard — ttyd, the web terminal behind Glance's "Terminal" page (port 7681).
  #
  # Part of `flake.nixosModules.server`: every Modules/Server/*.nix file except
  # home-assistant.nix, marsbar.nix and _lib.nix defines that same module, and the
  # definitions merge. Layout and shared pieces: see default.nix.

  flake.nixosModules.server = { config, pkgs, lib, activeUser, ... }:
  {

    # ── ttyd — web terminal (port 7681, Tailscale-only) ─────────────────────────
    # Embedded as the "Terminal" page in Glance. Default entrypoint is `login`
    # (runs as root), so the browser gets a real login prompt — no unauthenticated
    # shell exposed to the tailnet.
    services.ttyd = {
      enable = true;
      port = 7681;
      writeable = true;
    };

    # ttyd sessions die when the browser tab loses focus or closes — the websocket
    # drops and ttyd kills the shell. Detect a ttyd-spawned shell by walking up the
    # process tree, then exec into a persistent tmux session: disconnecting then only
    # kills the tmux client, not the session, so reconnecting reattaches exactly where
    # it left off.
    #
    # This lives HERE, in the Asgard-only server module, and deliberately NOT in the
    # shared Modules/Shell/zsh.nix — that one is imported by every host and this behaviour is
    # only wanted on the server. `programs.zsh.initContent` is a `lines` option, so this
    # concatenates with the shared definition rather than replacing it.
    # tmux itself is installed via environment.systemPackages in default.nix.
    home-manager.users.${activeUser}.programs.zsh.initContent = lib.mkAfter ''
      if [[ $- == *i* ]] && [[ -z "$TMUX" ]]; then
        __pid=$$
        for __i in 1 2 3 4 5 6; do
          __ppid=$(ps -o ppid= -p "$__pid" 2>/dev/null | tr -d ' ')
          [[ -z "$__ppid" || "$__ppid" -eq 1 ]] && break
          if [[ "$(ps -o comm= -p "$__ppid" 2>/dev/null)" == "ttyd" ]]; then
            exec tmux new-session -A -s ttyd
          fi
          __pid=$__ppid
        done
        unset __pid __ppid __i
      fi
    '';

  };
}
