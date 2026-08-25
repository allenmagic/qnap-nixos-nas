{ config, lib, ... }:

{
  imports = [
    ./bridges.nix
  ];

  # 基础网络配置
  networking = {
    hostName = "allenmagic-nas";
    useDHCP = false;
    useNetworkd = true;

    # 防火墙配置
    firewall = {
      enable = true;

      # Tailscale 接口（若在 NAS 上直接运行 tailscaled）：
      # 放行 SSH，供远程密钥登录（密码登录仍由 sshd 的 Match 保持禁用）
      interfaces.tailscale0.allowedTCPPorts = [ 22 ];

      # 在 br-lan 上开放服务端口
      interfaces.br-lan = {
        allowedTCPPorts = [
          22      # SSH
          139 445 # Samba
          2049    # NFS (nfsd)
          111     # NFSv3 rpcbind
          20048   # NFSv3 mountd（services/nfs.nix 固定端口）
          4000    # NFSv3 statd
          4001    # NFSv3 lockd
          8384    # Syncthing Web UI
          22000   # Syncthing sync
          4533    # Navidrome
          9180    # Feishin Web
          9090    # Cockpit Web UI
        ];
        allowedUDPPorts = [
          137 138 # Samba (NetBIOS)
          22000   # Syncthing discovery
          21027   # Syncthing discovery
          2049    # NFS (nfsd, UDP 用于 NFSv3)
          111     # NFSv3 rpcbind
          20048   # NFSv3 mountd
          4000    # NFSv3 statd
          4001    # NFSv3 lockd
        ];
      };
    };
  };
}
