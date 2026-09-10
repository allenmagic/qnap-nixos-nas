{ config, pkgs, lib, ... }:

let
  configFile = pkgs.writeText "photofield-configuration.yaml" ''
    collections:
      - name: 照片
        layout: timeline
        dirs:
          - /srv/data/photos
  '';
in
{
  # 相册服务。选 photofield：
  #   - photoprism 的 TensorFlow 是 CGO 编译期链接，其预编译 wheel 要求 AVX，
  #     而 N5095（Tremont）无 AVX —— 实测连 --version 都 SIGILL，配置绕不过
  #   - photoview 已停更且 libheif 绑定编译不过
  #   - immich 需 Postgres + Redis，过重
  # photofield 是 Go 单二进制 + SQLite，无 AI、无外部数据库。
  # exiftool / ffmpeg 由包的 wrapper 加进 PATH，运行期工具，不进二进制。
  systemd.services.photofield = {
    description = "Photofield photo viewer";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    environment = {
      PHOTOFIELD_ADDRESS = "192.168.10.2:9080";
      PHOTOFIELD_DATA_DIR = "/var/lib/photofield";
    };

    # 配置与缓存都在 StateDirectory；配置是只读的 store 文件，先拷进去
    preStart = ''
      cp -f ${configFile} /var/lib/photofield/configuration.yaml
    '';

    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.photofield}";
      DynamicUser = true;
      StateDirectory = "photofield";
      WorkingDirectory = "/var/lib/photofield";
      Restart = "on-failure";
      RestartSec = 5;

      # 原图只读
      ReadOnlyPaths = [ "/srv/data/photos" ];

      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      SystemCallArchitectures = "native";
    };
  };
}
