# YunShu 代理容器（内网代理模式）
#
# yunshu-headless 二进制不支持透明网关（TPROXY/策略路由）——它只有隧道 + 隧道
# DNS + 3proxy 混合代理端口。故用 private_proxy 模式：开 7890 混合 HTTP/SOCKS
# 代理，内网设备显式设代理经 YunShu 隧道翻墙。
#
# 网络接入：veth 挂 br-lan，静态 192.168.10.3（避开 .1 VM / .2 宿主）。
# 不再持浮动网关 .254（keepalived 关闭，.254 由路由 VM 兜底持有）。
{ inputs, lib, ... }:

{
  imports = [ inputs.yunshu-router.nixosModules.container ];

  yunshu.container = {
    name = "yunshu-router";
    mode = lib.mkForce "private_proxy";
    networkMode = "bridge";
    bridge = "br-lan";                # 接入内网桥
    lanAddress = "192.168.10.3/24";   # 容器静态 IP（代理监听于此）
  };
}
