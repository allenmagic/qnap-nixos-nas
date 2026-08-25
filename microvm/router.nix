# Alpine Router MicroVM 声明（POC）
#
# 用法（测试时在配置里临时开启）：
#   microvm.router.enable = true;
#   microvm.router.rootfsTarball = /path/to/alpine-x86_64-rootfs.tar.xz;
#
# 与 libvirt 方案的关系：
#   - 网络拓扑不变：tap 直接挂进 br-wan / br-lan（microvm 的 bridge 类型接口）
#   - 配置分发不变：alpine-router-deploy 仍走 ssh + tarball，与 hypervisor 无关
#   - 差异：VM 声明式（重装随 flake 重建）、内核由宿主侧 nixpkgs 出品、
#     无 Cockpit 管理（Cockpit 只见 libvirt 域）
{ config, lib, pkgs, ... }:

let
  cfg = config.microvm.router;
in

{
  options.microvm.router = {
    enable = lib.mkEnableOption "Alpine Router MicroVM（POC，与 libvirt 方案二选一）";

    rootfsTarball = lib.mkOption {
      type = lib.types.path;
      description = ''
        nanopi-r3s-rootfs 构建的 x86_64 Alpine rootfs tarball
        （ARCH=x86_64 PACK=1 ./distros/alpine/build.sh 产物）。
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    microvm.vms.alpine-router = {
      hypervisor = "qemu";
      vcpu = 2;
      mem = 512;   # MB

      # 客户机内核（nixpkgs 默认内核，缓存零编译）与最小 initrd
      kernel = import ./kernel.nix { inherit pkgs; };
      initrdPath = "${import ./initrd.nix { inherit pkgs kernel; }}/initrd";
      kernelParams = [ "root=/dev/vda" "rw" ];

      volumes = [{
        image = "${import ./rootfs-image.nix {
          inherit pkgs lib;
          rootfsTarball = cfg.rootfsTarball;
        }}";
        mountPoint = "/";
        autoCreate = false;
      }];

      # tap 由 microvm 创建并自动挂进宿主桥（与 bridges.nix 的 br-wan/br-lan 对接）
      interfaces = [
        { type = "bridge"; id = "router-wan"; bridge = "br-wan"; mac = "02:00:00:01:00:01"; }
        { type = "bridge"; id = "router-lan"; bridge = "br-lan"; mac = "02:00:00:01:00:02"; }
      ];
    };
  };
}
