# Alpine Router MicroVM 客户机内核
# 采用 Alpine 官方 virt 内核（vmlinuz-virt）：
#   - 上游为虚拟化环境裁剪（virtio 引导驱动内置、物理硬件驱动砍掉）——相当于官方维护的精简内核
#   - 与 initramfs-virt / modloop-virt / Alpine rootfs 同源同版本，全链路零错配
# 版本固定为 3.24.1（netboot-3.24.1）；升级时 bump URL 与 sha256
{ pkgs, ... }:

let
  src = pkgs.fetchurl {
    url = "https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/x86_64/netboot-3.24.1/vmlinuz-virt";
    sha256 = "1e6bf9027720c75c3ed0d79171f21b5791ee40ca9795d07c7c6e04dc5ea2ae90";
  };
in

# microvm 的 qemu runner 从内核包的 $out/bzImage 读取镜像，包装成期望布局
pkgs.runCommand "vmlinuz-virt" { } ''
  mkdir -p $out
  cp ${src} $out/bzImage
''
