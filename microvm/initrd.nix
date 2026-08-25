# Alpine Router MicroVM initrd
# 以官方 initramfs-virt 为基础（与 vmlinuz-virt / modloop-virt 同源），
# 注入 ext4 依赖链（crc16/mbcache/jbd2/ext4）：
#   - netboot 版 initramfs 不含 ext4（靠 modloop），而 root= 模式下
#     initramfs 不会挂 modloop、直接挂根 → 必须把 ext4 编进来
#   - 官方安装系统的 initramfs 由 mkinitfs 做了同样的事，这里是等效操作
# 版本固定为 3.24.1（netboot-3.24.1）；升级时 bump URL 与 sha256
{ pkgs, ... }:

let
  initramfs = pkgs.fetchurl {
    url = "https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/x86_64/netboot-3.24.1/initramfs-virt";
    sha256 = "6d80a739fedeeb6cd63e24dd208845e22199c41a5fb2054941ef61ec30264fa9";
  };
  modloop = pkgs.fetchurl {
    url = "https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/x86_64/netboot-3.24.1/modloop-virt";
    sha256 = "78907e7cc812d555f08d4e1133d090cf11fa197370882adfe67b0a5986ccb3f9";
  };
in

pkgs.runCommand "initramfs-virt-ext4" {
  nativeBuildInputs = [ pkgs.cpio pkgs.gzip pkgs.squashfsTools pkgs.kmod ];
} ''
  mkdir -p root modloop-x
  zcat ${initramfs} | (cd root && cpio -id 2>/dev/null)

  unsquashfs -d modloop-x ${modloop} >/dev/null
  # modules/ 下同时有 firmware 与版本目录，取数字开头的版本目录
  MV="$(ls modloop-x/modules/ | grep -E '^[0-9]')"
  D="root/lib/modules/$MV/kernel"

  # 注入 ext4 依赖链（模块来自配套 modloop，版本精确一致）
  mkdir -p "$D/fs/ext4" "$D/fs/jbd2" "$D/lib"
  cp modloop-x/modules/$MV/kernel/fs/ext4/ext4.ko "$D/fs/ext4/"
  cp modloop-x/modules/$MV/kernel/fs/jbd2/jbd2.ko "$D/fs/jbd2/"
  cp modloop-x/modules/$MV/kernel/fs/mbcache.ko "$D/fs/"
  cp modloop-x/modules/$MV/kernel/lib/crc/crc16.ko "$D/lib/"

  # 重建模块索引：modprobe 读 modules.dep.bin（二进制索引），
  # 只追加文本 modules.dep 会被无视——必须用 depmod 重新生成
  depmod -b root "$MV"

  mkdir -p $out
  (cd root && find . -print0 | cpio --null -o --format=newc | gzip -9 > $out/initrd)
''
