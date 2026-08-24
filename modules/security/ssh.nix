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

    # 不在全局放行 22 端口：br-lan 已在 network/default.nix 显式放行，
    # openFirewall = true 会把 22 加到全局 allowedTCPPorts（作用于 br-wan 等所有接口）
    openFirewall = false;
  };

  # SSH 密钥管理
  # 用户密钥在 users 模块中配置
}
