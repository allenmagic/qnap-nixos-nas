{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disks.nix
  ];

  # 系统基础配置
  system.stateVersion = "26.05";

  networking.hostName = "allenmagic-nas";

  # 启用 Flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # 启用 QNAP 硬件支持
  hardware.qnap8528 = {
    enable = true;
    preserveLeds = true;
  };

  # 时区和本地化
  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_TIME = "zh_CN.UTF-8";
  };

  # 控制台配置
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # Boot loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
