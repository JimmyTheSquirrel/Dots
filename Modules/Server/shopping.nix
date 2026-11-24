{ ... }: {
  # ════════════════════════════════════════════════════════════════════════════
  # shopping-list — the shared shopping list and recipe book (port 9558)
  # ════════════════════════════════════════════════════════════════════════════
  # One list for the two of you, live on BOTH dashboards: a tick on her phone
  # in the shop is on rock's screen before her thumb is off the glass. Plus a
  # recipe book — tap a recipe, untick what's already in the cupboard, and
  # everything else lands on the list, filed by aisle.
  #
  #   backend   Resources/Shopping-List/shopping-list.py  (stdlib Python, SSE)
  #   client    Resources/Glance/shopping.js               (shared, both dashboards)
  #   styles    Resources/Glance/cards.css                 (tokens → themed by each)
  #   cards     glance.nix → the Shopping page; marsbar.nix → her Shopping column
  #
  # Reached the same two ways as the other live backends: the admin Glance
  # calls :9558 directly over the tailnet; MarsBar through her own serve mount
  # (/shop-api, marsbar.nix), so she needs no grant on this port. 9558 is not in
  # allowedTCPPorts — tailscale0 is trusted, the LAN is not.
  #
  # ⚠ The list and the recipes are USER DATA, kept in the unit's
  # StateDirectory (/var/lib/private/shopping-list/state.json under
  # DynamicUser). A rebuild never touches it; reinstalling Asgard starts it
  # empty. The declarative pieces are `starterRecipes` and `starterStaples`
  # below, written in ONLY when there is no state file at all (the staples
  # also once onto a list from before they existed) — so deleting one sticks.
  # Full write-up: Claude/shopping.md.
  flake.nixosModules.server = { config, pkgs, lib, ... }:
  let
    port = 9558;

    # Four to show how it works on day one; edit or delete them from either
    # dashboard. `cat` is the aisle (shopping.js → AISLES); left out, the
    # dashboard works it out from the name.
    starterRecipes = [
      {
        name = "Spaghetti bolognese";
        icon = "🍝";
        ingredients = [
          { name = "Beef mince"; qty = "500g"; cat = "meat"; }
          { name = "Onion"; qty = "1"; cat = "produce"; }
          { name = "Garlic"; qty = "2 cloves"; cat = "produce"; }
          { name = "Carrot"; qty = "1"; cat = "produce"; }
          { name = "Chopped tomatoes"; qty = "2 tins"; cat = "pantry"; }
          { name = "Tomato paste"; qty = ""; cat = "pantry"; }
          { name = "Spaghetti"; qty = "500g"; cat = "pantry"; }
          { name = "Parmesan"; qty = ""; cat = "dairy"; }
        ];
        note = "Serves 4. Better the next day.";
      }
      {
        name = "Chicken stir-fry";
        icon = "🥘";
        ingredients = [
          { name = "Chicken thigh"; qty = "500g"; cat = "meat"; }
          { name = "Hokkien noodles"; qty = ""; cat = "pantry"; }
          { name = "Broccoli"; qty = "1"; cat = "produce"; }
          { name = "Capsicum"; qty = "1"; cat = "produce"; }
          { name = "Carrot"; qty = "1"; cat = "produce"; }
          { name = "Ginger"; qty = ""; cat = "produce"; }
          { name = "Soy sauce"; qty = ""; cat = "pantry"; }
        ];
        note = "";
      }
      {
        name = "Tacos";
        icon = "🌮";
        ingredients = [
          { name = "Beef mince"; qty = "500g"; cat = "meat"; }
          { name = "Taco seasoning"; qty = ""; cat = "pantry"; }
          { name = "Tortillas"; qty = "1 pack"; cat = "bakery"; }
          { name = "Lettuce"; qty = ""; cat = "produce"; }
          { name = "Tomatoes"; qty = "2"; cat = "produce"; }
          { name = "Avocado"; qty = "1"; cat = "produce"; }
          { name = "Grated cheese"; qty = ""; cat = "dairy"; }
          { name = "Sour cream"; qty = ""; cat = "dairy"; }
        ];
        note = "";
      }
      {
        name = "Pancakes";
        icon = "🥞";
        ingredients = [
          { name = "Plain flour"; qty = ""; cat = "pantry"; }
          { name = "Milk"; qty = ""; cat = "dairy"; }
          { name = "Eggs"; qty = "2"; cat = "dairy"; }
          { name = "Butter"; qty = ""; cat = "dairy"; }
          { name = "Maple syrup"; qty = ""; cat = "pantry"; }
        ];
        note = "";
      }
    ];
    # The Usuals: things you always keep in, one tap onto the list at their
    # usual amount, sorted into groups you make (these three to start). Generic
    # on purpose — edit, regroup or delete them on either dashboard.
    starterGroups = [ "Cupboard" "Fridge" "Cleaning & paper" ];
    starterStaples = [
      { name = "Cereal"; qty = ""; cat = "pantry"; group = "Cupboard"; }
      { name = "Pasta"; qty = "500g"; cat = "pantry"; group = "Cupboard"; }
      { name = "Rice"; qty = "1kg"; cat = "pantry"; group = "Cupboard"; }
      { name = "Coffee"; qty = ""; cat = "drinks"; group = "Cupboard"; }
      { name = "Tea bags"; qty = ""; cat = "drinks"; group = "Cupboard"; }
      { name = "Cordial"; qty = ""; cat = "drinks"; group = "Cupboard"; }
      { name = "Milk"; qty = "2L"; cat = "dairy"; group = "Fridge"; }
      { name = "Thickened cream"; qty = "300mL"; cat = "dairy"; group = "Fridge"; }
      { name = "Butter"; qty = "250g"; cat = "dairy"; group = "Fridge"; }
      { name = "Eggs"; qty = "1 dozen"; cat = "dairy"; group = "Fridge"; }
      { name = "Toilet paper"; qty = ""; cat = "household"; group = "Cleaning & paper"; }
      { name = "Paper towel"; qty = ""; cat = "household"; group = "Cleaning & paper"; }
      { name = "Tissues"; qty = ""; cat = "household"; group = "Cleaning & paper"; }
      { name = "Dishwashing liquid"; qty = ""; cat = "household"; group = "Cleaning & paper"; }
      { name = "Laundry liquid"; qty = ""; cat = "household"; group = "Cleaning & paper"; }
      { name = "Bin bags"; qty = ""; cat = "household"; group = "Cleaning & paper"; }
    ];
    seed = pkgs.writeText "shopping-starters.json" (builtins.toJSON {
      recipes = starterRecipes;
      groups = starterGroups;
      staples = starterStaples;
    });

    # ── Backups ─────────────────────────────────────────────────────────────
    # The list lives on the NVMe, which is exactly what a reinstall rewrites.
    # The data drives are never formatted (Hosts/Asgard/_disko.nix), so a copy
    # goes to /data/.state — real ext4 on the 8TB, where the arr databases
    # already live — and comes back by itself on a fresh install (restoreOnStart).
    #
    # Paths are env-overridable only so the scripts can be exercised away from
    # Asgard; the units never set them.
    stateDir = "/var/lib/private/shopping-list"; # DynamicUser's real StateDirectory
    backupMount = "/data/.state";
    backupDir = "${backupMount}/backups/shopping-list";
    keep = 60; # distinct versions — an unchanged list makes no new copy
    pathsSh = ''
      state_dir=''${SHOP_STATE_DIR:-${stateDir}}
      backup_mount=''${SHOP_BACKUP_MOUNT:-${backupMount}}
      backup_dir=''${SHOP_BACKUP_DIR:-${backupDir}}
      state="$state_dir/state.json"
    '';
    # A list file worth keeping: parses, and is shaped like one.
    validSh = ''valid() { jq -e '(.items | type == "array") and (.sid | type == "string")' "$1" >/dev/null 2>&1; }'';
    # A fresh sid tells every open dashboard "this replaces what you had", so a
    # restored (older) list isn't ignored as stale (shopping.js → take()).
    newSidSh = ''new_sid() { od -An -tx1 -N5 /dev/urandom | tr -d ' \n'; }'';

    backup = pkgs.writeShellApplication {
      name = "shopping-list-backup";
      runtimeInputs = with pkgs; [ coreutils diffutils findutils jq util-linux ];
      text = ''
        ${pathsSh}
        ${validSh}
        # nofail mounts: with the drive missing, /data/.state is an empty
        # directory on the NVMe, and a "backup" there would vanish with it.
        if ! mountpoint -q "$backup_mount"; then
          echo "$backup_mount is not mounted, so no backup (it would land on the NVMe)"
          exit 0
        fi
        if [ ! -s "$state" ]; then
          echo "no list yet, nothing to back up"
          exit 0
        fi
        if ! valid "$state"; then
          echo "state.json doesn't parse; keeping the last good backup" >&2
          exit 0
        fi
        install -d -m 0700 "$backup_dir"
        if [ -e "$backup_dir/latest.json" ] && cmp -s "$state" "$backup_dir/latest.json"; then
          echo "unchanged since the last backup"
          exit 0
        fi
        dated="$backup_dir/state-$(date +%Y-%m-%dT%H%M%S).json"
        tmp=$(mktemp "$backup_dir/.tmp.XXXXXX")
        cp "$state" "$tmp"
        chmod 0600 "$tmp"
        # Copied once, then linked: a crash can leave a stray .tmp, never a half file.
        ln "$tmp" "$dated"
        mv -f "$tmp" "$backup_dir/latest.json"
        find "$backup_dir" -maxdepth 1 -name 'state-*.json' | sort | head -n -${toString keep} | xargs -r rm -f
        echo "backed up to $dated"
      '';
    };

    # Before the service starts: no list yet (a fresh install, or the file was
    # deleted) but a backup on the data drive → put it back. Anything else, do
    # nothing and let the service seed or load as usual.
    restoreOnStart = pkgs.writeShellApplication {
      name = "shopping-list-restore-on-start";
      runtimeInputs = with pkgs; [ coreutils jq util-linux ];
      text = ''
        ${pathsSh}
        ${validSh}
        ${newSidSh}
        [ -e "$state" ] && exit 0
        if ! mountpoint -q "$backup_mount"; then
          echo "no list and $backup_mount isn't mounted: starting fresh" >&2
          exit 0
        fi
        latest="$backup_dir/latest.json"
        if [ ! -s "$latest" ] || ! valid "$latest"; then
          exit 0
        fi
        jq --arg sid "$(new_sid)" '.sid = $sid' "$latest" > "$state.tmp"
        chmod 0600 "$state.tmp"
        # Root put it there; the DynamicUser must own it to read and replace it.
        chown --reference="$state_dir" "$state.tmp"
        mv -f "$state.tmp" "$state"
        echo "restored the shopping list from $latest"
      '';
    };

    # By hand, on Asgard:
    #   sudo shopping-list-restore           list the backups (newest last)
    #   sudo shopping-list-restore latest    put the newest back
    #   sudo shopping-list-restore <file>    put that one back
    # Stopping the service backs up what's there NOW first (ExecStopPost), so a
    # restore can itself be undone with another restore.
    restore = pkgs.writeShellApplication {
      name = "shopping-list-restore";
      runtimeInputs = with pkgs; [ coreutils findutils jq systemd util-linux ];
      text = ''
        ${pathsSh}
        ${validSh}
        ${newSidSh}
        if [ "$(id -u)" != 0 ]; then
          echo "run it with sudo" >&2
          exit 1
        fi
        # Without the drive, the backup folder is an empty directory on the
        # NVMe: say that, not "there are no backups".
        if ! mountpoint -q "$backup_mount"; then
          echo "$backup_mount isn't mounted, so the backups (on the 8TB drive) can't be reached" >&2
          exit 1
        fi
        if [ $# -eq 0 ]; then
          echo "Backups in $backup_dir (newest last):"
          find "$backup_dir" -maxdepth 1 -name 'state-*.json' 2>/dev/null | sort | while read -r f; do
            printf '  %s  %s\n' "$(basename "$f")" \
              "$(jq -r '"\(.items | map(select(.done | not)) | length) to get, \(.recipes | length) recipes, \(.staples // [] | length) staples"' "$f" 2>/dev/null)"
          done
          echo
          echo "Put one back:  sudo shopping-list-restore latest   (or a file name from above)"
          exit 0
        fi
        src=$1
        [ "$src" = latest ] && src="$backup_dir/latest.json"
        [ -e "$src" ] || src="$backup_dir/$src"
        if [ ! -e "$src" ] || ! valid "$src"; then
          echo "$1: not a shopping-list backup" >&2
          exit 1
        fi
        # Take a copy before stopping: the stop backs up the current list, and
        # that can replace latest.json under our feet.
        pick=$(mktemp)
        trap 'rm -f "$pick"' EXIT
        jq --arg sid "$(new_sid)" '.sid = $sid' "$src" > "$pick"
        systemctl stop shopping-list.service
        install -m 0600 "$pick" "$state"
        chown --reference="$state_dir" "$state"
        systemctl start shopping-list.service
        echo "restored $(basename "$src"); the list you had is in $backup_dir too"
      '';
    };
  in
  {
    systemd.services.shopping-list = {
      description = "Shared shopping list + recipes for the Glance dashboards";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      # Soft, unlike the media units' RequiresMountsFor: the list itself lives
      # on the NVMe and must keep working with a data drive missing. This only
      # orders the start after the mount, so a fresh install's first start can
      # see the backup it should restore.
      unitConfig.WantsMountsFor = [ backupMount ];
      environment = {
        SHOP_PORT = toString port;
        SHOP_SEED = "${seed}";
        # Same list as ha-bridge, eclipse-control and network-panel.
        DASH_ORIGINS = lib.concatStringsSep "," (import ./_origins.nix config.asgard);
      };
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${../../Resources/Shopping-List/shopping-list.py}";
        # "+": these two run as root, outside the sandbox — they read and write
        # the data drive and the DynamicUser's private directory. Both exit 0 on
        # anything short of a real fault, so neither can keep the list from
        # starting or wedge a stop.
        ExecStartPre = "+${restoreOnStart}/bin/shopping-list-restore-on-start";
        # Every stop backs up: each deploy, and the shutdown before a reinstall.
        ExecStopPost = "+${backup}/bin/shopping-list-backup";
        DynamicUser = true;
        # → $STATE_DIRECTORY, where state.json lives. Kept across rebuilds and
        # reboots; DynamicUser puts it under /var/lib/private.
        StateDirectory = "shopping-list";
        Restart = "always";
        RestartSec = 5;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
        LockPersonality = true;
        SystemCallArchitectures = "native";
      };
    };

    # …and every night, for the days nobody deploys.
    systemd.services.shopping-list-backup = {
      description = "Back up the shared shopping list to the data drive";
      unitConfig.WantsMountsFor = [ backupMount ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${backup}/bin/shopping-list-backup";
      };
    };
    systemd.timers.shopping-list-backup = {
      description = "Back up the shared shopping list nightly";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 03:17:00";
        Persistent = true; # missed while Asgard was off → runs at the next boot
      };
    };

    # The one systemPackages outside default.nix: the restore command is built
    # here, from the same paths as the backup it reads.
    environment.systemPackages = [ restore ];
  };
}
