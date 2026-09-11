{ config, lib, ... }:

{
  imports = [
    ./samba.nix
    ./nfs.nix
    ./syncthing.nix
    # 音乐服务端：gonic（低内存）。前端 feishin 独立成文件，两种服务端共用。
    # 回退到 Navidrome：把下面这行换成 ./music-navidrome.nix
    #                 （注意两者的数据库互不兼容，切换后会重新扫描）
    ./music.nix
    ./feishin.nix
    ./beszel.nix
    ./webdav.nix
    # ./cockpit.nix   # 剔除（不引用）：配置文件保留在 services/cockpit.nix，
    #                 # 需要恢复时取消注释；注意 network/default.nix 里的
    #                 # 9090 端口放行是独立的，目前仍保留
    ./yunshu.nix
  ];
}
