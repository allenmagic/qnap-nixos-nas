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

      # ── 路由 VM 密钥（services.router-vm 的 deploy 通道）──────────
      # 文件名必须与 router-image 模块的 secretsDir 约定一致
      # （<secretsDir>/ssh-public-key 等，默认 /run/secrets）。
      # secrets.yaml 内容示例：
      #   ssh-public-key: |
      #     ssh-ed25519 AAAA... deploy-key
      #   tailscale-auth-key: tskey-auth-xxxxxxxxxxxxxxxx
      #   cloudflared-token: eyJhIjoi...
      # 注入语义：router-vm-deploy 在每次 VM 启动后自动 scp 进 guest
      # /run（guest 无状态，重启即清、重新注入）；tailscale 登录为手动
      # 触发：ssh root@192.168.10.1 'tailscale up'
      # ssh-public-key = {
      #   owner = "root";
      #   mode = "0400";
      # };
      # tailscale-auth-key = {
      #   owner = "root";
      #   mode = "0400";
      # };
      # cloudflared-token = {
      #   owner = "root";
      #   mode = "0400";
      # };
    };
  };
}
