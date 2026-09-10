{ config, pkgs, lib, ... }:

# ============================================================================
# Navidrome —— 2026-09 被 gonic 取代（常驻内存 900MB+/峰值 1.1GB 过高）。
#
# 本文件**刻意不在 services/default.nix 里 import**，仅作回退保留。
#
# 回退方法：把 default.nix 里的 ./music.nix 换成 ./music-navidrome.nix
# （feishin.nix 保持不动，两种服务端都用同一个前端）。
#
# ⚠️ 注意：Navidrome 的 /var/lib/navidrome 数据（105MB SQLite）与 gonic 的
# 数据库不兼容，切换回去会重新扫描；反之亦然。播放列表/收藏/播放次数在两者
# 之间无法迁移。切换后 4533 端口仍由同一个服务持有，客户端只需改服务器类型
# （navidrome ↔ subsonic）。
# ============================================================================

{
  # ===== Navidrome 音乐服务端 =====
  services.navidrome = {
    enable = true;

    settings = {
      # 音乐库路径
      MusicFolder = "/srv/data/music";

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

  # Navidrome 以 navidrome 用户运行，给予访问音乐目录的权限
  # （music 目录由 users/nas-user.nix 的 tmpfiles 统一创建）
  users.users.navidrome = {
    extraGroups = [ "nas" ];
  };
}
