{ config, lib, inputs, ... }:

{
  imports = [
    # 路由 VM 消费端模块（定义 microvm.router 选项；
    # 镜像 release 的 tag+sha256 在 microvm-router-image 仓库内，升级只 flake update）
    inputs.microvm-router-image.nixosModules.router
  ];
}
