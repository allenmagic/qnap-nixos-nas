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
#     store 只读无法直接读写打开）——release 升级（store 路径变化）自动重装状态
#   - 配置：alpine-router-deploy 是唯一覆盖通道（r3s 出厂配置在部署时被
#     NAS 权威版覆盖）；密钥 env 注入，绝不进入 release 产物与镜像
#
# 后端与资源（cloud-hypervisor，2026-08-26）：
#   - N5095 4 核：cpu3 经 isolcpus 隔离给路由器 VM 独占，vcpu0 pin 到 cpu3，
#     vcpu1 无约束动态调度
#   - 动态内存：virtio-balloon（CH 128M 对齐粒度），初始 balloon 256M，
#     宿主 OOM 时放气归还
#   - 网络：CH 不支持 qemu 的 bridge 接口类型，用 tap 接口 +
#     systemd-networkd 在 tap 出现时自动加入 br-wan/br-lan
{ config, lib, pkgs, ... }:

let
  cfg = config.microvm.router;

  # alpine-router-image 仓库 CI release（升级时同步改 tag 与三处 sha256，
  # 真实值取 release 的 SHA256SUMS asset）
  imageRelease = "alpine-router-image-20260826";
  releaseBase = "https://github.com/allenmagic/alpine-router-image/releases/download/${imageRelease}";

  # 客户机内核包装：CH runner（x86_64 分支）取 ${kernel.dev}/vmlinux——
  # 内容实为 bzImage（官方 vmlinuz-virt），CH 按文件头自动识别加载
  alpineKernel = pkgs.runCommand "vmlinuz-virt" { outputs = [ "out" "dev" ]; } ''
    mkdir -p $out $dev
    cp ${cfg.kernelFile} $out/bzImage
    cp ${cfg.kernelFile} $dev/vmlinux
  '';
in

{
  options.microvm.router = {
    enable = lib.mkEnableOption "Alpine Router MicroVM（POC，与 libvirt 方案二选一）";

    kernelFile = lib.mkOption {
      type = lib.types.path;
      default = pkgs.fetchurl {
        url = "${releaseBase}/vmlinuz-virt";
        sha256 = "1e6bf9027720c75c3ed0d79171f21b5791ee40ca9795d07c7c6e04dc5ea2ae90";
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
        sha256 = "e32522f9ae486522348e69343941a1d01a194945604d8fa7518b11346953002c";
      };
      description = ''
        装配后的 initramfs（已注入 ext4 依赖链，alpine-router-image release asset）。
      '';
    };

    rootfsImage = lib.mkOption {
      type = lib.types.path;
      default = pkgs.fetchurl {
        url = "${releaseBase}/alpine-router-rootfs.qcow2";
        sha256 = "7b5810ed4a6ac1371a51f7d4d0043242add3f513ab2220fd79c22d6b515b0dd5";
      };
      description = ''
        VM 根磁盘 qcow2（rootfs + modloop 模块，alpine-router-image release asset）。
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # CPU 独占：cpu3 隔离给路由器 VM（宿主调度器不再使用该核）。
    # 注意：isolcpus 影响整个宿主——修改核数时同步此处与 affinity
    boot.kernelParams = [ "isolcpus=3" "rcu_nocbs=3" ];

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

    # CH 的 tap 接口由 microvm 在 VM 启动时创建，networkd 在接口出现时
    # 自动将其加入对应桥（bridge 接口类型是 qemu 特有，CH 不支持）
    systemd.network.networks = {
      "50-router-wan" = {
        matchConfig.Name = "router-wan";
        networkConfig.Bridge = "br-wan";
      };
      "50-router-lan" = {
        matchConfig.Name = "router-lan";
        networkConfig.Bridge = "br-lan";
      };
    };

    microvm.vms.alpine-router = {
      autostart = true;
      # 注意：config 是单个 NixOS 模块（非列表），VM 内选项挂在 microvm.* 下
      config = {
        microvm.hypervisor = "cloud-hypervisor";

        # vsock（0=hypervisor 1=loopback 2=host 保留，guest 从 3 起）。
        # 注：microvm -s 的 vsock SSH 需要 guest 侧监听 vsock 的 sshd
        # （Alpine 默认只监听 TCP），此处先占 CID 供将来扩展
        microvm.vsock.cid = 3;

        microvm.vcpu = 2;   # vcpu0 独占 cpu3；vcpu1 动态
        microvm.mem = 512;  # MB，guest 内存上限

        # 动态内存：virtio-balloon（CH 要求 128M 对齐粒度）。
        # 初始 balloon 256M（guest 可用 256M），宿主 OOM 时自动放气归还。
        # 备选：virtio-mem 热插拔（hotplugMem=256），可 ch-remote 手动伸缩
        microvm.balloon = true;
        microvm.initialBalloonMem = 256;
        microvm.deflateOnOOM = true;

        # vcpu0 affinity（--cpus boot=N 由 microvm 生成，affinity 经 extraArgs 合并）
        # 语法：CH v53 用 vcpu@[host_cpus] 格式（WSL 实测验证；
        # JSON 形式 [{vcpu=0,cpus=[3]}] 在 v53 会解析失败）
        microvm.cloud-hypervisor.extraArgs = [ "--cpus" "affinity=[0@[3]]" ];

        # 客户机内核 / initramfs（官方 virt 三件套，装配时注入 ext4 依赖链）
        microvm.kernel = alpineKernel;
        microvm.initrdPath = "${cfg.initrd}";
        # rootfstype=ext4：initramfs 的 "Loading boot drivers" 会据此 modprobe ext4
        microvm.kernelParams = [ "root=/dev/vda" "rootfstype=ext4" "rw" ];

        microvm.volumes = [{
          # vda：根卷（disk-prep 服务维护的可写状态副本）
          image = "/var/lib/alpine-router/rootfs.qcow2";
          mountPoint = "/";
          autoCreate = false;
          imageType = "qcow2";   # CH 的 --disk 默认 image_type=raw，必须显式声明
        }];

        # tap 由 microvm 创建，networkd 挂进 br-wan/br-lan
        microvm.interfaces = [
          { type = "tap"; id = "router-wan"; mac = "02:00:00:01:00:01"; }
          { type = "tap"; id = "router-lan"; mac = "02:00:00:01:00:02"; }
        ];
      };
    };
  };
}
