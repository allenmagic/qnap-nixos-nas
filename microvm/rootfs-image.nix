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
  # cp -r 会把 store 目录的只读权限一并复制，先恢复写权限
  chmod -R u+w rootfs/lib/modules

  # nixpkgs 的模块是 .ko.xz——Alpine 的 busybox modprobe 不支持 xz，全部解压
  # （store 文件只读，必须流式解压到新文件，不能原地 xz -d）
  find rootfs/lib/modules -name '*.ko.xz' | while read -r f; do
    xz -d -c "$f" > "''${f%.xz}"
  done
  find rootfs/lib/modules -name '*.ko.xz' -delete

  truncate -s 8G $out
  mkfs.ext4 -q -F -L alpine-rootfs -d rootfs $out
''
