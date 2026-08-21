{ config, pkgs, lib, ... }:

{
  # Navidrome 音乐流媒体服务
  services.navidrome = {
    enable = true;

    settings = {
      # 音乐库路径
      MusicFolder = "/srv/data/media/music";

      # 数据存储路径
      DataFolder = "/var/lib/navidrome";

      # 网络配置
      Address = "192.168.10.2";
      Port = 4533;

      # 日志级别
      LogLevel = "info";

      # 扫描配置
      ScanSchedule = "@every 1h";

      # 转码配置（可选）
      # TranscodingCacheSize = "100MB";
    };
  };

  # 确保音乐目录存在
  systemd.tmpfiles.rules = [
    "d /srv/data/media 0755 nas nas -"
    "d /srv/data/media/music 0755 nas nas -"
  ];

  # Navidrome 服务以 navidrome 用户运行，给予访问音乐目录的权限
  users.users.navidrome = {
    extraGroups = [ "nas" ];
  };
}
