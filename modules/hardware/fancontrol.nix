{ config, pkgs, inputs, ... }:

{
  # 使用 qnap8528 仓库中的 fancontrol 配置
  hardware.fancontrol = {
    enable = true;
    # 直接使用 qnap8528 仓库中针对 TS-564 的配置
    config = builtins.readFile "${inputs.qnap8528}/examples/fancontrol.conf";
  };

  # 确保 lm_sensors 已安装
  environment.systemPackages = with pkgs; [
    lm_sensors
  ];
}
