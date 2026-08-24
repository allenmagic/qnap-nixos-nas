{ config, lib, ... }:

{
  # NFS 服务器配置
  services.nfs.server = {
    enable = true;

    # 固定端口（配合 network/default.nix 防火墙放行；NFSv3 需要 rpcbind/mountd/statd/lockd）
    mountdPort = 20048;
    lockdPort = 4001;
    statdPort = 4000;

    # 导出的共享目录
    # root_squash：客户端 root 映射为 nobody，避免局域网内任何设备以 root 身份读写
    # 客户端以普通用户（uid 与 nas 一致）挂载即可正常读写
    exports = ''
      # 数据共享
      /srv/data   192.168.8.0/24(rw,sync,no_subtree_check,root_squash,fsid=0)

      # 缓存共享
      /srv/cache  192.168.8.0/24(rw,sync,no_subtree_check,root_squash)

      # 备份共享
      /srv/backup 192.168.8.0/24(rw,sync,no_subtree_check,root_squash)
    '';

    # 启用 NFSv4
    nproc = 8;
  };

  # 防火墙配置（NFS 端口已在 network/default.nix 中配置）
  # networking.firewall.allowedTCPPorts = [ 2049 ];
}
