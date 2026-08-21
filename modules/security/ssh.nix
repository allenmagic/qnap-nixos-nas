{ config, lib, ... }:

{
  # SSH 服务配置
  services.openssh = {
    enable = true;

    settings = {
      # 安全设置
      PermitRootLogin = "prohibit-password";  # 禁止 root 密码登录，只允许密钥
      PasswordAuthentication = false;  # 禁用密码认证
      PubkeyAuthentication = true;     # 启用公钥认证

      # 其他安全选项
      X11Forwarding = false;
      AllowTcpForwarding = "yes";
      GatewayPorts = "no";

      # 性能优化
      UseDns = false;
    };

    # 监听端口（默认 22）
    ports = [ 22 ];

    # 打开防火墙（已在 network/default.nix 中配置）
    openFirewall = true;
  };

  # SSH 密钥管理
  # 用户密钥在 users 模块中配置
}
