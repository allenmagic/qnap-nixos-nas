{ config, pkgs, lib, ... }:

{
  # Navidrome 音乐流媒体服务
  services.navidrome = {
    enable = true;

    settings = {
      # 音乐库路径
      MusicFolder = "/srv/data/music";

      # 数据存储路径
      DataFolder = "/var/lib/navidrome";

      # 网络配置
      Address = "192.168.8.2";
      Port = 4533;

      # 日志级别
      LogLevel = "info";

      # 扫描配置
      ScanSchedule = "@every 1h";

      # 转码配置（可选）
      # TranscodingCacheSize = "100MB";
    };
  };

  # Navidrome 服务以 navidrome 用户运行，给予访问音乐目录的权限
  # （music 目录由 users/nas-user.nix 的 tmpfiles 统一创建）
  users.users.navidrome = {
    extraGroups = [ "nas" ];
  };
}
