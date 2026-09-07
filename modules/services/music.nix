{ config, pkgs, lib, ... }:

let
  # feishin-web 前端静态文件 + 预生成 settings.js（逻辑与 nixpkgs
  # services.feishin 模块相同：window.<KEY> = "<VALUE>"）。
  # settings.js 优先（buildEnv 后者覆盖包内同名文件）。
  feishinSettingsJs = pkgs.writeTextDir "settings.js" ''
    "use strict";
    window.ANALYTICS_DISABLED = "true";
  '';
  feishinWebRoot = pkgs.buildEnv {
    name = "feishin-web-root";
    paths = [ pkgs.feishin-web feishinSettingsJs ];
  };
in
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

  # ===== Feishin Web 客户端（darkhttpd 托管静态文件）=====
  # 2026-09 从 nginx 方案切换：feishin-web 是 HashRouter 单页应用（深链为
  # /#/ 形式，无需服务端 tryFiles fallback），nginx 的其余职责（vhost/gzip/
  # no-store 响应头）在内网 HTTP 场景均非必需，darkhttpd 几 KB 即可承载。
  # 公网入口由 Cloudflare Tunnel 提供（VM 内 cloudflared ingress →
  # http://192.168.10.2:9180，HTTPS/域名在 Cloudflare 侧终结；用子域名
  # 而非子路径，避免 hash 路由下 assets 绝对路径在子路径下 404）。
  # 服务器地址不硬编码：内网用户填 http://192.168.10.2:4533，
  # 公网用户填 https://<域名>，浏览器里各自填写。
  services.darkhttpd = {
    enable = true;
    port = 9180;
    # darkhttpd 1.17 里 --ipv6（由 networking.enableIPv6 触发）与 IPv4 --addr
    # 冲突（报 malformed --addr argument）。改用 IPv6 通配 ::，dual-stack 下
    # 同时接受 IPv4（br-wan 无 IP，实际只暴露 br-lan 内网）。
    address = "::";
    rootDir = "${feishinWebRoot}";
  };
}
