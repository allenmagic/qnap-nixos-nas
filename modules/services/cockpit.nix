{ config, pkgs, lib, ... }:

{
  # Cockpit Web 管理界面（系统级 Web 管理工具）
  services.cockpit = {
    enable = true;

    # 插件列表，可按需添加：
    #   pkgs.cockpit-machines      - 虚拟机管理（依赖 libvirtd 的 dbus.enable）
    #   pkgs.cockpit-podman        - 容器管理
    #   pkgs.cockpit-files         - 文件管理
    #   pkgs.cockpit-zfs           - ZFS 管理
    #   pkgs.cockpit-dockermanager - Docker 管理
    plugins = [
      pkgs.cockpit-machines
    ];

    # 监听端口（默认 9090）
    # 防火墙按接口放行：modules/network/default.nix 中 br-lan 已开放 9090
    port = 9090;
  };
}
