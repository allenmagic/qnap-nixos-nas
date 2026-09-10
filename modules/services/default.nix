{ config, lib, ... }:

{
  imports = [
    ./samba.nix
    ./nfs.nix
    ./syncthing.nix
    ./music.nix
    # ./cockpit.nix   # 剔除（不引用）：配置文件保留在 services/cockpit.nix，
    #                 # 需要恢复时取消注释；注意 network/default.nix 里的
    #                 # 9090 端口放行是独立的，目前仍保留
    ./yunshu.nix
  ];
}
