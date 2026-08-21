{ config, lib, ... }:

{
  # Syncthing 文件同步服务
  services.syncthing = {
    enable = true;
    user = "nas";
    group = "nas";
    dataDir = "/srv/data/syncthing";
    configDir = "/srv/data/syncthing/.config";

    # 开放默认端口
    openDefaultPorts = true;

    # Web UI 配置
    guiAddress = "192.168.10.2:8384";

    # 配置
    settings = {
      gui = {
        user = "nas";
        # 密码需要在首次启动后通过 Web UI 设置
        # 或使用 sops-nix 管理加密密码
      };

      options = {
        urAccepted = -1;  # 禁用使用统计报告
        globalAnnounceEnabled = true;
        localAnnounceEnabled = true;
        relaysEnabled = true;
      };

      # 设备和文件夹配置需要在 Web UI 中添加
      # 或通过 settings.devices 和 settings.folders 声明式配置
    };
  };

  # 确保数据目录存在且权限正确
  systemd.tmpfiles.rules = [
    "d /srv/data/syncthing 0755 nas nas -"
  ];
}
