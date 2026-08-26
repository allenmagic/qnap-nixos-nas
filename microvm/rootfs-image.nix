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
  nativeBuildInputs = [ pkgs.e2fsprogs pkgs.gnutar pkgs.squashfsTools pkgs.fakeroot ];
} ''
  # fakeroot 包裹：nix build 以非 root 运行，直接解包+mkfs.ext4 -d 会把
  # tar 内的 uid 0 记录降级为构建用户 uid（镜像里 /var/empty 等归属错误，
  # sshd 的 chroot 目录校验会拒绝启动）。fakeroot 下 lstat 返回伪 root 属主，
  # 镜像内文件即正确落为 root:root
  fakeroot sh -c "set -e
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

  # 启用 ttyS0 getty：r3s 产物默认注释（Alpine 默认状态）。
  # vmlinuz-virt 内建 8250 串口驱动（QEMU 实测可登录），
  # microvm 控制台/串口访问依赖它（-serial / virsh console）
  sed -i 's|^#ttyS0:|ttyS0:|' rootfs/etc/inittab

  truncate -s 8G \$out
  mkfs.ext4 -q -F -L alpine-rootfs -d rootfs \$out
  "
''
