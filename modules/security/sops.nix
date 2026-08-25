{ config, lib, ... }:

{
  # sops-nix 密钥管理配置
  sops = {
    # 默认密钥文件位置
    defaultSopsFile = ../../secrets/secrets.yaml;

    # age 密钥文件路径
    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      # 首次部署时需要生成：
      # mkdir -p /var/lib/sops-nix
      # age-keygen -o /var/lib/sops-nix/key.txt
      # 然后用公钥加密 secrets.yaml
    };

    # 定义密钥（示例，实际使用时取消注释并配置）
    secrets = {
      # nas 系统密码 hash（Cockpit/sudo/内网与 Tailscale SSH 密码登录共用）
      # secrets.yaml 内容：nas-password: $6$...（mkpasswd -m sha-512 生成）
      # nas-password = {
      #   neededForUsers = true;  # 用户激活前解密，配合 hashedPasswordFile 使用
      #   owner = "root";
      #   mode = "0400";
      # };

      # Samba 密码
      # samba-password = {
      #   owner = "nas";
      #   mode = "0400";
      # };

      # Syncthing GUI 密码
      # syncthing-password = {
      #   owner = "nas";
      #   mode = "0400";
      # };

      # Tailscale 认证密钥
      # tailscale-authkey = {
      #   owner = "root";
      #   mode = "0400";
      # };
    };
  };
}
