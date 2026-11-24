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
  # empty. The one declarative piece is `starterRecipes` below, written in
  # ONLY when there is no state file at all — so deleting a starter sticks.
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
    seed = pkgs.writeText "shopping-starter-recipes.json" (builtins.toJSON starterRecipes);
  in
  {
    systemd.services.shopping-list = {
      description = "Shared shopping list + recipes for the Glance dashboards";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        SHOP_PORT = toString port;
        SHOP_SEED = "${seed}";
        # Same list as ha-bridge, eclipse-control and network-panel.
        DASH_ORIGINS = lib.concatStringsSep "," (import ./_origins.nix config.asgard);
      };
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${../../Resources/Shopping-List/shopping-list.py}";
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
  };
}
