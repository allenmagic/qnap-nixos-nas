{ config, lib, inputs, ... }:

{
  imports = [
    # Alpine Router MicroVM 消费端模块（定义 microvm.router 选项；
    # 镜像 release 的 tag+sha256 在 alpine-router-image 仓库内，升级只 flake update）
    inputs.alpine-router-image.nixosModules.router
  ];
}
