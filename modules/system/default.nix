{ config, lib, ... }:

{
  imports = [
    ./locale.nix
    ./packages.nix
    ./nix-settings.nix
  ];
}
