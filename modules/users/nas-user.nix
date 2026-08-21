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
      "libvirtd"   # VM 管理
      "storage"    # 存储访问
    ];

    # SSH 公钥（替换为你的实际公钥）
    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... your-key-here"
    ];

    # 禁用密码登录（使用 SSH 密钥）
    hashedPassword = "!";
  };

  # 创建 storage 组
  users.groups.storage = {};

  # 创建服务目录并设置权限
  systemd.tmpfiles.rules = [
    "d /srv/data 0755 nas storage -"
    "d /srv/backup 0755 nas storage -"
    "d /srv/cache 0755 nas storage -"
    "d /srv/app 0755 nas storage -"
  ];

  # sudo 配置（允许 wheel 组成员无密码执行 sudo）
  security.sudo = {
    enable = true;
    wheelNeedsPassword = true;  # 改为 false 可以无密码 sudo
  };
}
