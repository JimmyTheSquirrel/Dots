{ lib, flake-parts-lib, ... }: {
  # flake-parts leaves undeclared flake outputs as `types.raw`, which refuses to
  # merge — so a second module defining `flake.lib.<name>` fails the eval with
  # "Define the value only once" (hit when Modules/steam.nix joined
  # Modules/btop.nix in exporting a matugen template).
  #
  # Declaring it as lazyAttrsOf lets each module contribute its own key.
  options.flake = flake-parts-lib.mkSubmoduleOptions {
    lib = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.raw;
      default = { };
      description = ''
        Flake-level values shared between modules — currently the matugen
        template + theme-name pairs exported by `btop.nix` and `steam.nix`,
        which `skwd-wall.nix` installs as matugen templates. Keeps each
        template defined once, next to the static fallback it must match.
      '';
    };
  };
}
