{ config, pkgs, ... }:

{
  # 启用 KVM 虚拟化
  virtualisation.libvirtd = {
    enable = true;

    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = false;

      # 启用 UEFI 支持
      ovmf = {
        enable = true;
        packages = [ pkgs.OVMFFull.fd ];
      };

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
