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
  # guest 完全无状态：rootfs 只读挂载，密钥由 sops-nix 解密到
  # /run/secrets，router-vm-deploy 在每次 VM 启动后自动注入
  # （modules/security/sops.nix 里配置三个密钥文件）。
  # ============================================================
  services.router-vm = {
    enable = true;
    os = "alpine";

    cpu = 0;                 # isolcpus 独占核：vcpu0 pin 到此核，宿主不用
    vcpus = 2;               # 1 独占 + 1 动态调度
    mem = 512;               # guest 内存上限 MB
    initialBalloonMem = 256; # virtio-balloon，128M 对齐；宿主 OOM 自动放气

    wanBridge = "br-wan";    # 物理口 eno1（modules/network/bridges.nix）
    lanBridge = "br-lan";    # 物理口 eno2
    vmIp = "192.168.10.1";   # 与 bridges.nix 的网关/DNS 指向一致
  };
}
