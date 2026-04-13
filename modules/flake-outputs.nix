{ lib, ... }:
let
  inherit (lib) mkOption types;
in {
  options.flake = {
    homeModules = mkOption {
      type = types.lazyAttrsOf types.unspecified;
      default = {};
      description = "Home Manager modules";
    };
  };
}
