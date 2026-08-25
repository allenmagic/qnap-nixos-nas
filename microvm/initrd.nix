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

sleep 1
mount /dev/vda /newroot && echo "rootfs mounted"
exec switch_root /newroot /sbin/init
INITEOF
  chmod +x root/init

  mkdir -p $out
  # 用 gzip 压缩（对照实验确认内核可解；zstd 压缩的 initramfs 在 6.18.44 上解包后内容为空）
  (cd root && find . -print0 | cpio --null -o --format=newc | gzip -9 > $out/initrd)
''
