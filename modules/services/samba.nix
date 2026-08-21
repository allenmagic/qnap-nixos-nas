{ config, lib, ... }:

{
  # Samba 文件共享服务
  services.samba = {
    enable = true;

    # 安全配置
    securityType = "user";

    # 额外配置
    extraConfig = ''
      # 全局设置
      workgroup = WORKGROUP
      server string = QNAP TS-564 NAS
      netbios name = TS564

      # 安全设置
      server min protocol = SMB3
      smb encrypt = desired

      # 性能优化
      socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=524288 SO_SNDBUF=524288
      read raw = yes
      write raw = yes
      max xmit = 65536
      dead time = 15

      # 访问控制
      hosts allow = 192.168.10.0/24 127.0.0.1
      hosts deny = 0.0.0.0/0

      # 日志
      log level = 1
      max log size = 1000

      # 其他
      load printers = no
      printing = bsd
      printcap name = /dev/null
      disable spoolss = yes
    '';

    # 共享目录配置
    shares = {
      # 数据共享（主要存储）
      data = {
        path = "/srv/data";
        browseable = "yes";
        "read only" = "no";
        "valid users" = "nas";
        "create mask" = "0664";
        "directory mask" = "0775";
        "force user" = "nas";
        "force group" = "nas";
        comment = "Main data storage";
      };

      # 缓存共享（临时/高速存储）
      cache = {
        path = "/srv/cache";
        browseable = "yes";
        "read only" = "no";
        "valid users" = "nas";
        "create mask" = "0664";
        "directory mask" = "0775";
        "force user" = "nas";
        "force group" = "nas";
        comment = "Cache storage (SSD)";
      };

      # 备份共享（只读更安全）
      backup = {
        path = "/srv/backup";
        browseable = "yes";
        "read only" = "no";
        "valid users" = "nas";
        "create mask" = "0664";
        "directory mask" = "0775";
        "force user" = "nas";
        "force group" = "nas";
        comment = "Backup storage";
      };
    };

    # 启用 WINS 支持（可选）
    enableWinbindd = false;
  };

  # 在防火墙中开放 Samba 端口（已在 network/default.nix 中配置）
  # networking.firewall.allowedTCPPorts = [ 139 445 ];
  # networking.firewall.allowedUDPPorts = [ 137 138 ];
}
