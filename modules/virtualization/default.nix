{ config, lib, ... }:

{
  imports = [
    ./libvirtd.nix
    ./alpine-router.nix
    ../../microvm/router.nix
  ];
}
