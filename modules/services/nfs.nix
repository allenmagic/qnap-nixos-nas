{ config, lib, ... }:

{
  # NFS 服务器配置
  services.nfs.server = {
    enable = true;

    # 导出的共享目录
    exports = ''
      # 数据共享
      /srv/data   192.168.10.0/24(rw,sync,no_subtree_check,no_root_squash,fsid=0)

      # 缓存共享
      /srv/cache  192.168.10.0/24(rw,sync,no_subtree_check,no_root_squash)

      # 备份共享
      /srv/backup 192.168.10.0/24(rw,sync,no_subtree_check,no_root_squash)
    '';

    # 启用 NFSv4
    nproc = 8;
  };

  # 防火墙配置（NFS 端口已在 network/default.nix 中配置）
  # networking.firewall.allowedTCPPorts = [ 2049 ];
}
