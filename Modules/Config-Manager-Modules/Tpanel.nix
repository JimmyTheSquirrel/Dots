{ config, pkgs, lib, ... }:

environment.systemPackages = [
    inputs.tpanel.packages.${system}.default

     ];