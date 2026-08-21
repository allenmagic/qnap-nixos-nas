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

    # libvirt-dbus 服务：供 cockpit-machines 等 D-Bus 客户端使用
    dbus.enable = true;

    # 在引导时启动已标记为 autostart 的 VM
    onBoot = "start";
    onShutdown = "shutdown";
  };

  # 安装 VM 命令行管理工具
  # （图形界面工具已移除，改用 Cockpit Web UI，见 ./cockpit.nix）
  environment.systemPackages = with pkgs; [
    libguestfs
    cloud-utils
  ];
}
