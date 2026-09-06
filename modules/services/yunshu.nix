# YunShu 透明网关容器（gateway 模式）
#
# 容器作为内网浮动网关（VRRP MASTER 持有 .254），内网设备默认网关/DNS 指向
# .254，流量经容器三层转发 + YunShu fake-IP 分流：被墙域名走 tun0，内网直连。
#
# headless 版缺两个关键步骤，已由 yunshu-nix 的服务补齐：
#   - yunshu-connect：登录后自动 `yunshu -s all` 连接 pa/ga（登录 ≠ 连接）
#   - yunshu-routes：fake-IP 198.18.0.0/15 路由到 tun0
# 缺这两步，隧道只是空壳、分流失效（表现为只通部分域名/拿到污染 IP）。
#
# 网络接入：veth 挂 br-lan，静态 192.168.10.3；keepalived MASTER 持有浮动 .254。
{ inputs, lib, ... }:

{
  imports = [ inputs.yunshu-router.nixosModules.container ];

  yunshu.container = {
    name = "yunshu-router";
    mode = lib.mkForce "gateway";
    networkMode = "bridge";
    bridge = "br-lan";                # 接入内网桥
    lanAddress = "192.168.10.3/24";   # 容器静态 IP
    upstreamGateway = "192.168.10.1"; # 容器自身 DNS 上游（路由 VM dnsmasq，不依赖隧道）
  };
}
