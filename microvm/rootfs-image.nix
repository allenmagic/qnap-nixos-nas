# Alpine Router MicroVM 的 ext4 根镜像：
#   r3s 构建的 x86_64 Alpine rootfs tarball（纯用户态）
#   + Alpine 官方 modloop-virt 的模块（/lib/modules 与 vmlinuz-virt 精确配套）
#   → 8G ext4 镜像（与原 qcow2 同规格）
{ pkgs, lib, rootfsTarball }:

let
  # 与 vmlinuz-virt 同源同版本的模块集（squashfs 镜像）
  modloop = pkgs.fetchurl {
    url = "https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/x86_64/netboot-3.24.1/modloop-virt";
    sha256 = "78907e7cc812d555f08d4e1133d090cf11fa197370882adfe67b0a5986ccb3f9";
  };
in

pkgs.runCommand "alpine-router-rootfs.ext4" {
  nativeBuildInputs = [ pkgs.e2fsprogs pkgs.gnutar pkgs.squashfsTools ];
} ''
  mkdir -p rootfs
  tar xf ${rootfsTarball} -C rootfs --numeric-owner

  # 内核模块：modloop-virt 里是 modules/<ver>/（注意非 lib/modules），
  # 平移到 rootfs/lib/modules/<ver>，供 openrc/mdev 的 modprobe 使用
  mkdir -p rootfs/lib/modules
  unsquashfs -d modloop-x ${modloop} >/dev/null
  cp -r modloop-x/modules/* rootfs/lib/modules/

  # 引导期自动加载：r3s 的 modules 服务注册在 default runlevel，
  # 字母序排在 nftables/networking 之后；nf_tables 必须提前就位
  cat >> rootfs/etc/modules <<'MODULES'
nf_tables
virtio_net
MODULES

  truncate -s 8G $out
  mkfs.ext4 -q -F -L alpine-rootfs -d rootfs $out
''
