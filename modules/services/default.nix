{ config, lib, ... }:

{
  imports = [
    ./samba.nix
    ./nfs.nix
    ./syncthing.nix
    ./music.nix
    ./cockpit.nix
  ];
}
