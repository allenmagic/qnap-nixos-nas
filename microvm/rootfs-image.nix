# Alpine Router MicroVM 的 ext4 根镜像：
#   r3s 构建的 x86_64 Alpine rootfs tarball（纯用户态）
#   + guest 内核的模块（/lib/modules 版本对齐）
#   → 8G ext4 镜像（与原 qcow2 同规格）
{ pkgs, lib, rootfsTarball }:

let
  kernel = import ./kernel.nix { inherit pkgs lib; };
in

pkgs.runCommand "alpine-router-rootfs.ext4" {
  nativeBuildInputs = [ pkgs.e2fsprogs pkgs.gnutar pkgs.xz ];
} ''
  mkdir -p rootfs
  tar xf ${rootfsTarball} -C rootfs --numeric-owner

  # 内核模块对齐：guest 内核是宿主侧 nixpkgs 出品，rootfs 里必须装对应模块
  # （nixpkgs 26.05 起模块在独立的 modules 输出里）
  mkdir -p rootfs/lib/modules
  cp -r ${kernel.modules}/lib/modules/${kernel.modDirVersion} rootfs/lib/modules/
  # 保持 .ko.xz 原样：modules.dep 指向 .xz 路径，Alpine 的 busybox modprobe
  # 支持 xz 模块（此前尝试解压反而让 modprobe 找不到文件）

  # 引导期自动加载：r3s 的 /etc/modules 只有 af_packet/ipv6（R3S 内核把
  # nftables 编进内核），我们的内核是模块——nftables 服务要求 nf_tables
  # 预先加载，virtio 网卡需要 virtio_net（依赖由 modules.dep 自动解析）
  cat >> rootfs/etc/modules <<'MODULES'
nf_tables
virtio_net
MODULES

  truncate -s 8G $out
  mkfs.ext4 -q -F -L alpine-rootfs -d rootfs $out
''
