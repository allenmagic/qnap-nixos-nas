{ config, lib, pkgs, ... }:

let
  # 图标自托管。Glance 的图标默认由浏览器从 cdn.jsdelivr.net 拉取，国内不稳；
  # 官方文档明确说 assets-path 就是为「Monitor 这类要填图标 URL 的 widget」
  # 准备的自托管方案——该目录由 Glance 挂在 URL /assets/ 下，icon 写根相对
  # 路径即可，内网直连与 cloudflared 公网访问都能取到。
  #
  # 哈希由 NAS 上 `nix store prefetch-file --json <url>` 实测得出，不是估的。
  iconUrls = {
    glance = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/glance.svg";
    qbittorrent = "https://cdn.jsdelivr.net/npm/simple-icons@latest/icons/qbittorrent.svg";
    aria2 = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/aria2.svg";
    musicbrainz = "https://cdn.jsdelivr.net/npm/simple-icons@latest/icons/musicbrainz.svg";
    music-circle = "https://cdn.jsdelivr.net/npm/@mdi/svg@latest/svg/music-circle.svg";
    syncthing = "https://cdn.jsdelivr.net/npm/simple-icons@latest/icons/syncthing.svg";
    beszel = "https://cdn.jsdelivr.net/gh/selfhst/icons/svg/beszel.svg";
    folder-network = "https://cdn.jsdelivr.net/npm/@mdi/svg@latest/svg/folder-network.svg";
  };

  iconHashes = {
    glance = "sha256-t03iDtzzCmOriIhhsrfNXT4IQA/1I4OjpnRFckxJOzI=";
    qbittorrent = "sha256-nbIJuY+U/hlnnDWN/mwcjT58BruE2U7G2nd9R84mLgo=";
    aria2 = "sha256-sKUGe/EZZ96jMILKWWPdwTijLuF055VBB2wPu+hv3NQ=";
    musicbrainz = "sha256-aDjUxyKtWWgPSmjnYnewz6SFpkcCjJICDUSZm21nzos=";
    music-circle = "sha256-Jh5SJmtFAIph0keeOXkeZ32nf8x6LobKOQdLZuwfqDM=";
    syncthing = "sha256-pM0RXKp6K9hJz8QIjv55Z9JqCYIRPbvgIEHqAUR5zL0=";
    beszel = "sha256-X/VJcBAOH/ykwWmYfliJl+u951SzwKiCSotSMXt8Qgo=";
    folder-network = "sha256-JQ9MFPO4tlPrPQj5zTB9UGdGSqnWKpotZeUCet4chgo=";
  };

  # 拷成真实文件而非 linkFarm 建符号链接，避免服务端处理软链的差异
  glanceAssets = pkgs.runCommand "glance-assets" { } ''
    mkdir -p $out/icons
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: url: ''
        cp ${pkgs.fetchurl { inherit url; hash = iconHashes.${name}; }} $out/icons/${name}.svg
      '') iconUrls
    )}
  '';
in
{
  # Glance 仪表盘（glanceapp/glance）：起始页，汇总本机各 Web 服务入口与在线状态。
  # 公网访问经路由 VM 的 cloudflared 隧道回源到 192.168.10.2:8080，
  # 隧道 ingress 在 Cloudflare Zero Trust 面板配置（见 README）。
  services.glance = {
    enable = true;

    settings = {
      server = {
        host = "192.168.10.2"; # 只绑 br-lan，不在 br-wan 暴露
        port = 8080;
        # 经 cloudflared 回源：按 X-Forwarded-For 认客户端 IP。Glance 自带的
        # 暴力破解防护（5 次失败封 IP 5 分钟）依赖它，不加则所有请求同源。
        proxied = true;
        # 自托管图标目录，由 Glance 挂在 URL /assets/ 下
        assets-path = glanceAssets;
      };

      # 自带认证（公网暴露必需）。两个值都走 sops，由模块的 ExecStartPre
      # （以 root 跑 jq）替换进 /run/glance/glance.yaml，不进 nix store。
      # ⚠️ sops 里的值不能带尾换行：secret-key 多 1 字节即长度校验失败，
      #    password-hash 多 \n 则 bcrypt 比对恒失败。
      auth = {
        secret-key = {
          _secret = config.sops.secrets.glance-secret-key.path;
        };
        users.nas.password-hash = {
          _secret = config.sops.secrets.glance-password-hash.path;
        };
      };

      pages = [
        {
          name = "Home";
          columns = [
            {
              size = "full";
              widgets = [
                # 用 monitor 而非 bookmarks：一样可点击跳转，但额外显示在线状态，
                # 正好解决「记不住端口 / 不知道还活着没」。
                #
                # alt-status-codes 是实测值，不是猜的：Glance 自身(8080) 与
                # gonic(4533) 探测返回 303（重定向到登录页），WebDAV(4918) 返回
                # 401，不列进来会被误判成「挂了」。
                {
                  type = "monitor";
                  title = "NAS 服务";
                  # 图标走自托管的 /assets/icons/（见文件开头说明），不再用
                  # si:/sh:/mdi: 前缀——那些是要浏览器去 jsdelivr 取的。
                  # 文件名沿用取回时的名字：aria2.svg 给 AriaNg（它自己库里没有），
                  # music-circle.svg / folder-network.svg 是 gonic 与 WebDAV 的
                  # 泛用替代（这两者在图库里没有专用图标）。
                  sites = [
                    # 内网地址：Glance 自身走公网访问时这些链接点不开，
                    # 需要时再补一组走 Cloudflare 子域名的「公网」链接。
                    { title = "Glance"; url = "http://192.168.10.2:8080"; icon = "/assets/icons/glance.svg"; alt-status-codes = [ 302 303 ]; same-tab = true; }
                    { title = "qBittorrent"; url = "http://192.168.10.2:8081"; icon = "/assets/icons/qbittorrent.svg"; same-tab = true; }
                    { title = "AriaNg"; url = "http://192.168.10.2:6880"; icon = "/assets/icons/aria2.svg"; same-tab = true; }
                    { title = "Feishin"; url = "http://192.168.10.2:9180"; icon = "/assets/icons/musicbrainz.svg"; same-tab = true; }
                    { title = "gonic"; url = "http://192.168.10.2:4533"; icon = "/assets/icons/music-circle.svg"; alt-status-codes = [ 302 303 ]; same-tab = true; }
                    { title = "Syncthing"; url = "http://192.168.10.2:8384"; icon = "/assets/icons/syncthing.svg"; same-tab = true; }
                    { title = "Beszel"; url = "http://192.168.10.2:8090"; icon = "/assets/icons/beszel.svg"; same-tab = true; }
                    { title = "WebDAV"; url = "http://192.168.10.2:4918"; icon = "/assets/icons/folder-network.svg"; alt-status-codes = [ 401 ]; same-tab = true; }
                  ];
                }
                { type = "clock"; }
                { type = "weather"; location = "Beijing"; }
                { type = "server-stats"; servers = [ { type = "local"; name = "NAS"; } ]; }
              ];
            }
          ];
        }
      ];
    };
  };
}
