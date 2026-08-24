{ config, lib, ... }:

{
  # 启用 mdadm 软 RAID 支持
  boot.swraid = {
    enable = true;
    # mdadm.conf 配置（首次安装后需要填写实际的 UUID）
    mdadmConf = ''
      # ARRAY /dev/md0 level=raid1 num-devices=2 UUID=<your-uuid-here>
      # 使用 mdadm --detail --scan 获取实际配置

      # 必须设置 MAILADDR 或 PROGRAM，否则 mdmon 服务会崩溃
      MAILADDR root
    '';
  };

  # 文件系统挂载点
  # 注意：device/fsType 用 lib.mkForce —— nixos-generate-config 生成的
  # hardware-configuration.nix 会以 by-uuid 声明 / 与 /boot 等挂载点，
  # 与本仓库的 by-label 定义冲突（error: conflicting definition values）。
  # 本仓库以 label 为唯一约定（INSTALL.md 创建磁盘时按此打标），故强制覆盖。
  fileSystems = {
    # 系统盘（256GB SSD）
    "/" = {
      device = lib.mkForce "/dev/disk/by-label/nixos";
      fsType = lib.mkForce "ext4";
    };

    "/boot" = {
      device = lib.mkForce "/dev/disk/by-label/boot";
      fsType = lib.mkForce "vfat";
    };

    # 数据盘（2×3TB HDD RAID1）
    "/srv/data" = {
      device = lib.mkForce "/dev/md0";
      fsType = lib.mkForce "xfs";
      options = [ "defaults" "noatime" ];
    };

    # 缓存盘（1TB SSD）
    "/srv/cache" = {
      device = lib.mkForce "/dev/disk/by-label/cache";
      fsType = lib.mkForce "ext4";
      options = [ "defaults" "noatime" ];
    };

    # 备份盘（2TB HDD）
    "/srv/backup" = {
      device = lib.mkForce "/dev/disk/by-label/backup";
      fsType = lib.mkForce "ext4";
      options = [ "defaults" "noatime" ];
    };
  };

  # 启用定期 SSD Trim
  services.fstrim = {
    enable = true;
    interval = "weekly";
  };

  # Swap 配置（可选，8GB 内存可能不需要）
  swapDevices = [ ];
  # swapDevices = [{
  #   device = "/var/swapfile";
  #   size = 4096;  # 4GB
  # }];
}
