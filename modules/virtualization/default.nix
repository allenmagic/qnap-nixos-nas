{ config, lib, inputs, ... }:

{
  imports = [
    # 路由 VM 消费端模块（定义 services.router-vm 选项；cloud-hypervisor
    # 直管不依赖 microvm.nix。镜像 release 的 tag+sha256 在 router-image
    # 仓库内，升级只 flake update）
    inputs.router-image.nixosModules.router
  ];

  # ============================================================
  # 路由 VM（cloud-hypervisor 直管；见 docs/router-vm.md）
  #
  # guest 无状态运行（rootfs 只读），密钥由 sops-nix 解密到
  # /run/secrets，router-vm-deploy 在每次 VM 启动后自动注入
  # （modules/security/sops.nix 里配置四个密钥文件）。
  # 持久身份（SSH host key / authorized_keys / 双 tailscale 节点）经
  # stateDisk 落宿主 /var/lib/router-vm/state.raw——VM 重启身份固定，
  # 官方 Tailscale 免重复 approve；删 state.raw 即重置全部身份。
  # ============================================================
  services.router-vm = {
    enable = true;
    os = "gentoo";

    cpu = 0;                 # isolcpus 独占核：vcpu0 pin 到此核，宿主不用
    vcpus = 2;               # 1 独占 + 1 动态调度
    mem = 256;               # guest 内存上限 MB（全量服务含 tailscale/cloudflared ~160M，256 足够）
    initialBalloonMem = 0;   # 不启动充气（充气会从 mem 扣可用内存；宿主侧回收未实现）

    # 持久状态盘（第二块 virtio-blk → guest /dev/vdb → /run/router-vm/state）：
    # 内容 = SSH host key + authorized_keys + 两个 tailscaled.state（各 ~100K），
    # 默认 64M 绰绰有余；首次启动自动 truncate+mkfs
    stateDisk = { };

    wanBridge = "br-wan";    # 物理口 enp2s0(WAN)（modules/network/bridges.nix）
    lanBridge = "br-lan";    # 物理口 enp3s0(LAN)
    vmIp = "192.168.10.1";   # 与 bridges.nix 的网关/DNS 指向一致
  };
}
