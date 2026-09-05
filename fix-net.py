import re, sys
# --- bridges.nix ---
p = "modules/network/bridges.nix"
s = open(p).read()
old_wan = '''      # br-wan 不配置 IP（完全由 Alpine VM 管理）
      "30-br-wan" = {
        matchConfig.Name = "br-wan";
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
          IPv6AcceptRA = "no";
        };
      };'''
new_wan = '''      # br-wan：宿主管理 IP（setup 阶段直连上级 192.168.8.1）。
      # 路由 VM 的 WAN 仍经此桥 DHCP（共享同一物理口）。
      "30-br-wan" = {
        matchConfig.Name = "br-wan";
        networkConfig = {
          DHCP = "no";
          Address = "192.168.8.10/24";
          Gateway = "192.168.8.1";
          DNS = [ "192.168.8.1" ];
          LinkLocalAddressing = "no";
          IPv6AcceptRA = "no";
        };
      };'''
assert old_wan in s, "br-wan 段未找到"
s = s.replace(old_wan, new_wan)

old_lan_gw = '''          Address = "192.168.10.2/24";
          Gateway = "192.168.10.1";  # 指向 Alpine VM 路由器
          DNS = [ "192.168.10.1" ];'''
new_lan = '''          Address = "192.168.10.2/24";
          # setup 阶段默认路由走 br-wan（192.168.8.1）；此处仅保留 192.168.10 网段连接路由，
          # 供访问路由 VM 与未来下游 LAN。接好 LAN 后可改回经路由 VM。'''
assert old_lan_gw in s, "br-lan 段未找到"
s = s.replace(old_lan_gw, new_lan)
open(p, "w").write(s)
print("bridges.nix OK")

# --- default.nix (firewall) ---
p = "modules/network/default.nix"
s = open(p).read()
old = '''      interfaces.tailscale0.allowedTCPPorts = [ 22 ];'''
new = '''      interfaces.br-wan.allowedTCPPorts = [ 22 ];  # 管理 SSH（192.168.8.10）

      interfaces.tailscale0.allowedTCPPorts = [ 22 ];'''
assert old in s, "消防墙段未找到"
s = s.replace(old, new)
open(p, "w").write(s)
print("default.nix OK")
