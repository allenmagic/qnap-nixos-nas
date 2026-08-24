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
    guiAddress = "192.168.8.2:8384";

    # 配置
    settings = {
      gui = {
        user = "nas";
        # ⚠️ 未设置密码时 8384 对 br-lan 完全开放，任何内网设备都可控制同步/删除文件。
        # 建议任选其一：
        #   1. password = "..."        （明文写入 nix store，首次启动后被哈希）
        #   2. services.syncthing.guiPasswordFile = "/run/secrets/..."  （配合 sops-nix，更安全）
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
