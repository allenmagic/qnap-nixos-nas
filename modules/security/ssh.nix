{ config, lib, ... }:

{
  # SSH 服务配置
  services.openssh = {
    enable = true;

    settings = {
      # 安全设置
      PermitRootLogin = "prohibit-password";  # 禁止 root 密码登录，只允许密钥
      PasswordAuthentication = false;  # 默认禁用密码认证；仅内网通过下方 Match 放行
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

    # 内网与 Tailscale 网段允许密码登录（内网设备配置密钥麻烦；Tailscale 自带
    # 加密隧道与设备认证，密码登录风险可控）；其余来源保持默认禁用密码、只认密钥。
    extraConfig = ''
      Match Address 192.168.10.0/24,100.64.0.0/10
        PasswordAuthentication yes
    '';
  };

  # SSH 密钥管理
  # 用户密钥在 users 模块中配置
}
