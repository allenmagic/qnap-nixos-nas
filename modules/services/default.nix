{ config, lib, ... }:

{
  imports = [
    ./samba.nix
    ./nfs.nix
    ./syncthing.nix
    ./navidrome.nix
    ./cockpit.nix
  ];
}
