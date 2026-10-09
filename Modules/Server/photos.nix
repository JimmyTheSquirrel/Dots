{ ... }: {
  # Asgard — Immich, with its admin account seeded from sops.
  #
  # Part of `flake.nixosModules.server`: every Modules/Server/*.nix file except
  # home-assistant.nix, marsbar.nix and _lib.nix defines that same module, and the
  # definitions merge. Layout and shared pieces: see default.nix.

  flake.nixosModules.server = { config, pkgs, pkgs-unstable, inputs, lib, ... }:
  let
    inherit (import ./_lib.nix { inherit pkgs; }) waitForHttp;
  in
  {

# ══════════════════════════════════════════════════════════════════════════════
# PHOTOS — Immich photo server
# Native NixOS module — manages its own PostgreSQL and Redis automatically.
# Public URL: photos.bifrost-vault.com (via Cloudflare tunnel)
# Port: 2283
# The admin account is created from sops by immich-admin-seed.service below —
# nothing to click on first visit.
# ══════════════════════════════════════════════════════════════════════════════

    # Immich 3, from nixos-unstable — the module AND the package, the pair
    # nixpkgs tests together. 26.05 still ships 2.7.5, which nixpkgs marked
    # insecure in Oct 2026 (CVE-2026-59258, CVE-2026-82272; 2.x gets no more
    # fixes) and now refuses to build — and this one is open to the internet.
    # 3.x lands in NixOS 26.11: on that release, delete these three lines.
    # (rock, 2026-10-09: "update all my hosts … so they dont have any
    # security things".) The first start on 3.x migrates the database one
    # way — immich-dump-before-upgrade, below, dumps it first.
    disabledModules = [ "services/web-apps/immich.nix" ];
    imports = [ "${inputs.nixpkgs-unstable}/nixos/modules/services/web-apps/immich.nix" ];

    services.immich = {
      enable = true;
      package = pkgs-unstable.immich;
      mediaLocation = "/data/photos";
      host = "0.0.0.0";
      openFirewall = false;
    };

    # Immich 2.7+ expects .immich marker files in each subdirectory — create them
    # before the service starts so verifyReadAccess doesn't fail on fresh /data.
    systemd.services.immich-server.serviceConfig.ExecStartPre = lib.mkBefore [
      (pkgs.writeShellScript "immich-init-dirs" ''
        for dir in encoded-video thumbs upload backups library profile; do
          mkdir -p /data/photos/$dir
          touch /data/photos/$dir/.immich
        done
      '')
      # A safety net for upgrades: the first start of a NEW Immich version
      # migrates its database one way (2.x → 3.x did, 2026-10), and rolling back
      # the NixOS generation doesn't roll the database back. So before the first
      # start on each version it dumps the database beside Immich's own nightly
      # dumps — backups/before-immich-<version>-<when>.sql.gz — and won't start
      # if that fails. A plain restart on the same version does nothing. (It runs
      # as immich, which owns the database: peer auth on /run/postgresql; gzip and
      # pg_dump are on the unit's path, the same ones Immich's backup job uses.)
      (pkgs.writeShellScript "immich-dump-before-upgrade" ''
        set -euo pipefail
        want=${config.services.immich.package.version}
        seen=/var/lib/immich/dumped-for
        [ "$(cat "$seen" 2>/dev/null || true)" = "$want" ] && exit 0
        rm -f /data/photos/backups/before-immich-*.part      # a failed earlier attempt
        out=/data/photos/backups/before-immich-$want-$(date +%Y%m%d-%H%M%S).sql.gz
        echo "Immich $want: dumping the database to $out before its first start"
        pg_dump --clean --if-exists ${config.services.immich.database.name} | gzip > "$out.part"
        mv "$out.part" "$out"
        echo "$want" > "$seen"
      '')
    ];

    # Seeds the Immich admin account from sops on first boot.
    # /api/auth/admin-signup is only available before any admin exists — idempotent.
    systemd.services.immich-admin-seed = {
      description = "Create Immich admin account from sops";
      after    = [ "immich-server.service" "network.target" ];
      wants    = [ "immich-server.service" ];
      wantedBy = [ "multi-user.target" ];
      path     = [ pkgs.curl pkgs.jq ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        USERNAME=$(cat ${config.sops.secrets."admin-username".path})
        PASSWORD=$(cat ${config.sops.secrets."admin-password".path})
        BASE="http://localhost:2283"

        ${waitForHttp { name = "Immich"; url = "$BASE/api/server/ping"; tries = 24; interval = 5; }}

        # Body built by jq from the environment, not spliced by hand — see
        # filebrowser-credentials for why (quotes, /proc/<pid>/cmdline).
        export USERNAME PASSWORD
        CODE=$(jq -n '{email: ($ENV.USERNAME + "@asgard.local"), password: $ENV.PASSWORD, name: $ENV.USERNAME}' \
          | curl -s -o /dev/null -w "%{http_code}" \
              -X POST "$BASE/api/auth/admin-signup" \
              -H "Content-Type: application/json" \
              --data-binary @- 2>/dev/null) || true

        if [ "$CODE" = "201" ]; then
          echo "Immich admin created."
        elif [ "$CODE" = "400" ]; then
          echo "Immich admin already exists — skipping."
        else
          echo "Immich admin-signup returned HTTP $CODE" >&2
        fi
      '';
    };

  };
}
