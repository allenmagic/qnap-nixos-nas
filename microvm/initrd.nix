# Alpine Router MicroVM 最小 initrd：
#   加载 virtio 块设备 + ext4 模块 → 挂载 /dev/vda → switch_root 到 Alpine 的 /sbin/init
# 只含 boot-critical 模块，virtio-net 等由 rootfs 内 mdev 加载。
{ pkgs, kernel }:

let
  # nixpkgs 26.05 起模块在独立的 modules 输出里
  modRoot = "${kernel.modules}/lib/modules/${kernel.modDirVersion}/kernel";

  # busybox 必须静态链接：initramfs 里没有 glibc/ld-linux，
  # 26.05 的 pkgs.busybox 默认是动态链接（执行 /init 时解释器缺失 → ENOENT）
  busyboxStatic = pkgs.busybox.override { enableStatic = true; };
in

pkgs.runCommand "alpine-router-initrd" {
  nativeBuildInputs = [ pkgs.cpio pkgs.gzip pkgs.xz ];
} ''
  mkdir -p root/{proc,sys,dev,newroot,bin,lib/modules/{virtio,block,fs/jbd2,fs/ext4,lib}}
  cp ${busyboxStatic}/bin/busybox root/bin/
  ln -s busybox root/bin/sh
  ln -s busybox root/bin/mount
  ln -s busybox root/bin/switch_root
  ln -s busybox root/bin/insmod

  # boot-critical 模块（nixpkgs 的是 .ko.xz——busybox insmod 不支持 xz，全部解压）
  for f in ${modRoot}/drivers/virtio/*.ko.xz; do
    xz -d -c "$f" > "root/lib/modules/virtio/$(basename "$f" .xz)"
  done
  xz -d -c ${modRoot}/drivers/block/virtio_blk.ko.xz > root/lib/modules/block/virtio_blk.ko 2>/dev/null || true
  # ext4 依赖链：mbcache（注意 6.18 里文件直接位于 fs/ 下，无子目录）
  # → jbd2 → crc16 → ext4
  xz -d -c ${modRoot}/fs/mbcache.ko.xz > root/lib/modules/fs/mbcache.ko 2>/dev/null || true
  xz -d -c ${modRoot}/fs/jbd2/jbd2.ko.xz > root/lib/modules/fs/jbd2/jbd2.ko 2>/dev/null || true
  xz -d -c ${modRoot}/lib/crc/crc16.ko.xz > root/lib/modules/lib/crc16.ko 2>/dev/null || true
  xz -d -c ${modRoot}/fs/ext4/ext4.ko.xz > root/lib/modules/fs/ext4/ext4.ko 2>/dev/null || true
  # 网络/防火墙模块也预加载：r3s 的 modules 服务注册在 default runlevel，
  # 字母序排在 nftables/networking 之后，等它加载时服务早已失败
  mkdir -p root/lib/modules/net/netfilter root/lib/modules/net
  xz -d -c ${modRoot}/net/netfilter/nfnetlink.ko.xz > root/lib/modules/net/netfilter/nfnetlink.ko 2>/dev/null || true
  xz -d -c ${modRoot}/net/netfilter/nf_tables.ko.xz > root/lib/modules/net/netfilter/nf_tables.ko 2>/dev/null || true
  xz -d -c ${modRoot}/net/netfilter/nf_conntrack.ko.xz > root/lib/modules/net/netfilter/nf_conntrack.ko 2>/dev/null || true
  xz -d -c ${modRoot}/net/netfilter/nf_nat.ko.xz > root/lib/modules/net/netfilter/nf_nat.ko 2>/dev/null || true
  xz -d -c ${modRoot}/net/netfilter/nf_flow_table.ko.xz > root/lib/modules/net/netfilter/nf_flow_table.ko 2>/dev/null || true
  xz -d -c ${modRoot}/net/core/failover.ko.xz > root/lib/modules/net/failover.ko 2>/dev/null || true
  xz -d -c ${modRoot}/drivers/net/net_failover.ko.xz > root/lib/modules/net/net_failover.ko 2>/dev/null || true
  xz -d -c ${modRoot}/drivers/net/virtio_net.ko.xz > root/lib/modules/net/virtio_net.ko 2>/dev/null || true

  cat > root/init <<'INITEOF'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

# 按依赖顺序加载（6.18：ring 在核心之前、virtio_pci 同时依赖 modern 与 legacy dev）
insmod_v() { [ -f "$1" ] && { echo "insmod $1"; insmod "$1"; }; }
insmod_v /lib/modules/virtio/virtio_ring.ko
insmod_v /lib/modules/virtio/virtio.ko
insmod_v /lib/modules/virtio/virtio_pci_modern_dev.ko
insmod_v /lib/modules/virtio/virtio_pci_legacy_dev.ko
insmod_v /lib/modules/virtio/virtio_pci.ko
insmod_v /lib/modules/block/virtio_blk.ko
# 根文件系统 ext4 及依赖
insmod_v /lib/modules/fs/mbcache.ko
insmod_v /lib/modules/fs/jbd2/jbd2.ko
insmod_v /lib/modules/lib/crc16.ko
insmod_v /lib/modules/fs/ext4/ext4.ko
# 网络/防火墙（在客户机服务启动前就位）
insmod_v /lib/modules/net/netfilter/nfnetlink.ko
insmod_v /lib/modules/net/netfilter/nf_tables.ko
insmod_v /lib/modules/net/netfilter/nf_conntrack.ko
insmod_v /lib/modules/net/netfilter/nf_nat.ko
insmod_v /lib/modules/net/netfilter/nf_flow_table.ko
insmod_v /lib/modules/net/failover.ko
insmod_v /lib/modules/net/net_failover.ko
insmod_v /lib/modules/net/virtio_net.ko

sleep 1
mount /dev/vda /newroot && echo "rootfs mounted"
# switch_root 后内核不再自动挂 devtmpfs（DEVTMPFS_MOUNT 只作用于初始根），
# 而 Alpine base 的 devfs/sysfs 服务未注册（r3s 只装 openrc），这里显式挂进新根
mount -t devtmpfs devtmpfs /newroot/dev
mount -t proc proc /newroot/proc
mount -t sysfs sysfs /newroot/sys
# 调试开关：cmdline 带 debugshell=1 时直接进客户机 shell（不进 openrc）
# 用纯 shell 内建（精简 busybox 无 grep applet）
read _CMDLINE_ < /proc/cmdline
case "$_CMDLINE_" in
  *debugshell=1*)
    echo "debug shell"
    exec switch_root /newroot /bin/sh
  ;;
esac
exec switch_root /newroot /sbin/init
INITEOF
  chmod +x root/init

  mkdir -p $out
  # 用 gzip 压缩（对照实验确认内核可解；zstd 压缩的 initramfs 在 6.18.44 上解包后内容为空）
  (cd root && find . -print0 | cpio --null -o --format=newc | gzip -9 > $out/initrd)
''
