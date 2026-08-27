{ config, lib, ... }:

{
  # 定义 NAS 服务用户
  users.users.nas = {
    isNormalUser = true;
    description = "NAS service user";
    home = "/home/nas";

    # 用户组
    extraGroups = [
      "wheel"      # sudo 权限
      "storage"    # 存储访问
    ];

    # SSH 公钥（替换为你的实际公钥）
    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... your-key-here"
    ];

    # 系统密码（hash）用途：Cockpit Web 登录（PAM）、sudo、SSH 密码登录
    # （密码仅内网与 Tailscale 网段放行，见 modules/security/ssh.nix 的 Match；
    #   其他来源只认密钥）。
    #
    # ⚠️ 本仓库是公开的：hash 可被离线爆破，密码必须足够强（推荐 4 个以上
    # 随机单词或 16+ 位随机字符）且不要与其他账号复用。改密码时重新生成 hash
    # 替换即可；注意旧 hash 会永久留在 git 历史里，背后的密码务必终身不复用。
    # 生成：mkpasswd -m sha-512（或 openssl passwd -6）
    hashedPassword = "$6$0sMQSWRntUi.eVpe$BDlpZGVvPFbBgNKTV0p4MN178FbvDJE599yhSaaTYFcYYJsxiW.AIwXG8QYLCAHIcB6MOjhrLy.NLDCEH2d0H0";
  };

  # 创建 storage 组
  users.groups.storage = {};

  # 创建服务目录并设置权限
  # 路径约定：性能敏感/可重建的应用状态放 /srv/cache（SSD），
  # 不可再生数据放 /srv/data（Btrfs RAID1），无独立的 /srv/app 目录
  systemd.tmpfiles.rules = [
    "d /srv/data 0755 nas storage -"
    "d /srv/backup 0755 nas storage -"
    "d /srv/cache 0755 nas storage -"

    # /srv/data 下的默认数据分类目录（Samba/NFS 共享 data 时自动可见）
    "d /srv/data/music 0755 nas nas -"
    "d /srv/data/videos 0755 nas nas -"
    "d /srv/data/photos 0755 nas nas -"
    "d /srv/data/documents 0755 nas nas -"
    "d /srv/data/downloads 0755 nas nas -"
    "d /srv/data/projects 0755 nas nas -"
    "d /srv/data/templates 0755 nas nas -"
    "d /srv/data/models 0755 nas nas -"
  ];

  # sudo 配置（允许 wheel 组成员无密码执行 sudo）
  security.sudo = {
    enable = true;
    wheelNeedsPassword = true;  # 改为 false 可以无密码 sudo
  };
}
