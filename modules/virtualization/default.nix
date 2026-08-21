{ config, lib, ... }:

{
  imports = [
    ./libvirtd.nix
    ./alpine-router.nix
  ];
}
