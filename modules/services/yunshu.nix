# YunShu 透明网关容器（策略分流 VPN + 透明代理）
#
# 浮动网关（VRRP）MASTER 节点：与 Alpine 路由 VM（BACKUP，见
# router-image 的 base/keepalived/keepalived.conf）组成主备对，
# 共同持有浮动 IP 192.168.10.254（内网设备的 DHCP 网关）：
#   正常：本容器持有 .254——按策略分流（直连→VM NAT，代理→YunShu TUN）
#   容器不可用：VM 接管 .254——降级为纯直连 NAT，保连通优先
#
# 网络接入：veth 挂 br-lan，静态 192.168.10.3（避开 .1 VM / .2 宿主 /
# DHCP 池 100-200）；直连流量默认路由 = VM（192.168.10.1）。
# 修改浮动网关参数（floatIp/vrrpId/authPass）时与 VM 侧同步。
{ inputs, ... }:

{
  imports = [ inputs.yunshu-router.nixosModules.container ];

  yunshu.container = {
    name = "yunshu-router";
    networkMode = "bridge";
    bridge = "br-lan";                # 接入 Alpine 网络（内网桥）
    lanAddress = "192.168.10.3/24";   # 容器静态 IP
    # gateway mode（yunshu-nix ≥06f64bb 后 upstreamGateway 挪入 gateway 子模块）：
    # 直连流量出口 = 路由器 VM（192.168.10.1）。floatIp/vrrpId/authPass 用默认
    # （192.168.10.254/10/alpine-float，与 VM 侧 keepalived.conf 对齐）。
    gateway = {
      upstreamGateway = "192.168.10.1";
    };
  };
}
