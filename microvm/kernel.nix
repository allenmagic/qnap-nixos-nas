# Alpine Router MicroVM 客户机内核
# 直接用 nixpkgs 默认内核（与宿主机 boot.kernelPackages 同款）：
#   - 走官方缓存，无需本地编译
#   - 内核升级随 flake 走，宿主/客户机同步
# 引导关键驱动（virtio_pci/virtio_blk）是模块 → 由 initrd 加载；
# ext4 在默认内核中已内置，root=/dev/vda 可直接挂载。
{ pkgs, ... }:

pkgs.linux_6_18
