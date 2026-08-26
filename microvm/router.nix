# Alpine Router MicroVM 声明（POC）
#
# 用法（测试时在配置里临时开启）：
#   microvm.router.enable = true;   # rootfs 默认从 r3s CI release 拉取
#
# 供应链与配置链（单一通道，无双重覆盖）：
#   - rootfs：nanopi-r3s-rootfs 的 GitHub Actions release asset
#     （CI 构建、包已装齐；默认 fetchurl 固定 tag+sha256）
#   - 配置：alpine-router-deploy 是唯一覆盖通道——r3s 烙入的出厂配置
#     在部署时被 NAS 权威版（alpine-router/base）覆盖，构建镜像时不做覆盖
#   - 密钥：deploy 的 env 文件注入，绝不进入 release 产物与镜像
#   - 网络拓扑不变：tap 直接挂进 br-wan / br-lan（microvm 的 bridge 类型接口）
#   - 差异 vs libvirt：VM 声明式（重装随 flake 重建）；内核/initrd/模块为
#     Alpine 官方 virt 三件套（netboot-3.24.1，全链路同源）；无 Cockpit 管理
#     （Cockpit 只见 libvirt 域）
{ config, lib, pkgs, ... }:

let
  cfg = config.microvm.router;
in

{
  options.microvm.router = {
    enable = lib.mkEnableOption "Alpine Router MicroVM（POC，与 libvirt 方案二选一）";

    rootfsTarball = lib.mkOption {
      type = lib.types.path;
      default = pkgs.fetchurl {
        # nanopi-r3s-rootfs CI release（alpine / base infra / x86_64）
        # 升级：r3s 新 release 后替换 tag 与 sha256（sha256 取同名 .sha256 asset）
        # 注意：GitHub 直连不稳时可临时用代理构建，产物固定 sha256 不随网络变化
        url = "https://github.com/allenmagic/nanopi-r3s-rootfs/releases/download/nanopi-r3s-rootfs-20260825/alpine-base-x86_64-rootfs.tar.xz";
        sha256 = "75f8079b4863ce8fc8260b7c5700bdc180005f786123205cc96dd913810c7fda";
      };
      description = ''
        Alpine x86_64 rootfs tarball。默认取 nanopi-r3s-rootfs 的 CI release asset；
        本地调试可用 r3s 构建产物覆盖（ARCH=x86_64 PACK=1 ./distros/alpine/build.sh）。
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    microvm.vms.alpine-router = {
      hypervisor = "qemu";
      vcpu = 2;
      mem = 512;   # MB

      # 客户机内核（Alpine 官方 vmlinuz-virt）与官方 initramfs-virt（注入 ext4）
      kernel = import ./kernel.nix { inherit pkgs; };
      initrdPath = "${import ./initrd.nix { inherit pkgs; }}/initrd";
      # rootfstype=ext4：initramfs 的 "Loading boot drivers" 会据此 modprobe ext4
      kernelParams = [ "root=/dev/vda" "rootfstype=ext4" "rw" ];

      volumes = [{
        # vda：ext4 根卷（r3s rootfs + modloop 模块）
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
