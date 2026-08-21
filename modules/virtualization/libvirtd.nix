{ config, pkgs, ... }:

{
  # 启用 KVM 虚拟化
  virtualisation.libvirtd = {
    enable = true;

    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = false;

      # OVMF/UEFI 固件随 QEMU 包默认提供，无需额外配置

      # 启用 TPM 支持（可选）
      swtpm.enable = true;
    };

    # 在引导时启动已标记为 autostart 的 VM
    onBoot = "start";
    onShutdown = "shutdown";
  };

  # 安装 VM 管理工具
  environment.systemPackages = with pkgs; [
    virt-manager
    virt-viewer
    libguestfs
    cloud-utils
  ];
}
