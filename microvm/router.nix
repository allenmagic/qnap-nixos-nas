# Alpine Router MicroVM 声明（POC）
#
# 用法（测试时在配置里临时开启）：
#   microvm.router.enable = true;   # 镜像资产默认从 alpine-router-image release 拉取
#
# 供应链（2026-08-26 重构，纯 fetchurl）：
#   - 镜像资产全部由 alpine-router-image 仓库 CI 生产（release asset）：
#     vmlinuz-virt / initrd（注入 ext4 依赖链）/ alpine-router-rootfs.qcow2
#   - 本模块只 fetchurl 拉取 + 声明 VM，无任何本地镜像构建
#   - disk-prep 服务把 release 镜像复制到 /var/lib/alpine-router（可写状态目录；
#     store 只读，qemu 无法直接读写打开；autoCreate 语义是创建空盘而非复制模板）
#     release 升级（store 路径变化）时自动重装状态
#   - 配置：alpine-router-deploy 是唯一覆盖通道（r3s 出厂配置在部署时被
#     NAS 权威版覆盖）；密钥 env 注入，绝不进入 release 产物与镜像
#   - 网络拓扑：tap 直接挂进 br-wan / br-lan（microvm 的 bridge 类型接口）
{ config, lib, pkgs, ... }:

let
  cfg = config.microvm.router;

  # alpine-router-image 仓库 CI release（升级时同步改 tag 与三处 sha256，
  # 真实值取 release 的 SHA256SUMS asset）
  imageRelease = "alpine-router-image-20260826";
  releaseBase = "https://github.com/allenmagic/alpine-router-image/releases/download/${imageRelease}";
  # release 尚未产出，fakeSha256 占位（构建报错信息会显示真实值）
  fakeSha = lib.fakeSha256;
in

{
  options.microvm.router = {
    enable = lib.mkEnableOption "Alpine Router MicroVM（POC，与 libvirt 方案二选一）";

    kernelFile = lib.mkOption {
      type = lib.types.path;
      default = pkgs.fetchurl {
        url = "${releaseBase}/vmlinuz-virt";
        sha256 = fakeSha;
      };
      description = ''
        Alpine 官方 vmlinuz-virt（alpine-router-image release asset）。
        本地调试可用 image/assemble.sh 产物的 vmlinuz-virt 覆盖。
      '';
    };

    initrd = lib.mkOption {
      type = lib.types.path;
      default = pkgs.fetchurl {
        url = "${releaseBase}/initrd";
        sha256 = fakeSha;
      };
      description = ''
        装配后的 initramfs（已注入 ext4 依赖链，alpine-router-image release asset）。
      '';
    };

    rootfsImage = lib.mkOption {
      type = lib.types.path;
      default = pkgs.fetchurl {
        url = "${releaseBase}/alpine-router-rootfs.qcow2";
        sha256 = fakeSha;
      };
      description = ''
        VM 根磁盘 qcow2（rootfs + modloop 模块，alpine-router-image release asset）。
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # 首次启动 / release 升级时把镜像复制到可写状态目录
    systemd.services.alpine-router-disk = {
      wantedBy = [ "multi-user.target" ];
      requiredBy = [ "microvm@alpine-router.service" ];
      before = [ "microvm@alpine-router.service" ];
      serviceConfig.Type = "oneshot";
      script = ''
        STATE_DIR=/var/lib/alpine-router
        STATE_IMG="$STATE_DIR/rootfs.qcow2"
        SRC=${cfg.rootfsImage}
        MARK="$STATE_DIR/.src-path"
        mkdir -p "$STATE_DIR"
        if [ ! -f "$STATE_IMG" ] || [ "$(cat "$MARK" 2>/dev/null)" != "$SRC" ]; then
          echo "初始化/更新 VM 根磁盘: $SRC"
          install -m 0644 "$SRC" "$STATE_IMG"
          printf '%s' "$SRC" > "$MARK"
        fi
      '';
    };

    microvm.vms.alpine-router = {
      hypervisor = "qemu";
      vcpu = 2;
      mem = 512;   # MB

      # 客户机内核：官方 vmlinuz-virt（qemu runner 要求 $out/bzImage 文件名）
      kernel = pkgs.runCommand "vmlinuz-virt" { } ''
        mkdir -p $out
        cp ${cfg.kernelFile} $out/bzImage
      '';

      # 官方 initramfs-virt（装配时已注入 ext4 依赖链）
      initrdPath = "${cfg.initrd}";
      # rootfstype=ext4：initramfs 的 "Loading boot drivers" 会据此 modprobe ext4
      kernelParams = [ "root=/dev/vda" "rootfstype=ext4" "rw" ];

      volumes = [{
        # vda：根卷（disk-prep 服务维护的可写状态副本，qcow2）
        image = "/var/lib/alpine-router/rootfs.qcow2";
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
