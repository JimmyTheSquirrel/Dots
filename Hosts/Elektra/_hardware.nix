# Elektra hardware — nixos-facter replaces the hand-written hardware block.
# (A plain NixOS module: import-tree skips paths containing "/_".)
#
# facter.json is generated over SSH by the first `apollo-deploy`. It is picked
# up conditionally, so the host still evaluates (and `--vm-test` still works)
# before it exists.
{ lib, ... }:
let
  facterReport = ./facter.json;
  haveFacter = builtins.pathExists facterReport;
in {
  imports = lib.optional haveFacter { hardware.facter.reportPath = facterReport; };

  warnings = lib.optional (!haveFacter) ''
    Hosts/Elektra/facter.json is missing, so this configuration has no hardware
    report: no microcode, no detected kernel modules, no firmware. It is fine to
    `build` or `--vm-test` like this, but do NOT switch it onto real hardware.
    Generate it with: apollo-deploy kitkat-Elektra
  '';
}
