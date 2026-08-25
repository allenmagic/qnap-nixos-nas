{ config, pkgs, lib, ... }:

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

  # Navidrome 以 navidrome 用户运行，给予访问音乐目录的权限
  # （music 目录由 users/nas-user.nix 的 tmpfiles 统一创建）
  users.users.navidrome = {
    extraGroups = [ "nas" ];
  };

  # ===== Feishin Web 客户端 =====
  services.feishin = {
    enable = true;

    # 主访问地址（作为 nginx server_name 主名）
    # 如需同时支持域名访问，在 nginx.virtualHost.serverAliases 追加域名
    domain = "192.168.8.2";

    # 纯内网 HTTP 场景，用 nginx 托管（caddy 的自动 HTTPS 在此无用武之地）
    nginx.enable = true;
    nginx.virtualHost = {
      # 与 Navidrome(4533) 区分，沿用 Feishin 默认端口
      # addr 必填（listen 子模块的 addr 无默认值），与其余服务一致绑定内网 IP
      listen = [ { addr = "192.168.8.2"; port = 9180; } ];
    };

    # 服务器地址不硬编码：内网用户填 http://192.168.8.2:4533，
    # 走 Cloudflare Tunnel 的公网用户填 https://<域名>，浏览器里各自填写即可。
    # 若想硬编码并锁定，可加 SERVER_NAME/SERVER_TYPE/SERVER_URL/SERVER_LOCK。
    settings = {
      ANALYTICS_DISABLED = "true";
    };
  };
}
