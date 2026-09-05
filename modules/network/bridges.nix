{ config, lib, ... }:

{
  # 启用 systemd-networkd
  systemd.network = {
    enable = true;

    # 创建网络桥接设备
    netdevs = {
      # WAN 桥接（连接到 Alpine VM 的 WAN 侧）
      "10-br-wan" = {
        netdevConfig = {
          Kind = "bridge";
          Name = "br-wan";
        };
        bridgeConfig = {
          STP = false;
        };
      };

      # LAN 桥接（连接到 Alpine VM 的 LAN 侧）
      "10-br-lan" = {
        netdevConfig = {
          Kind = "bridge";
          Name = "br-lan";
        };
        bridgeConfig = {
          STP = false;
        };
      };
    };

    # 网络配置
    networks = {
      # 物理网口 enp2s0 绑定到 br-wan
      "20-enp2s0-wan" = {
        matchConfig.Name = "enp2s0";
        networkConfig = {
          Bridge = "br-wan";
          # 宿主机不在 WAN 口配置 IP（由 Alpine VM 管理）
          DHCP = "no";
          LinkLocalAddressing = "no";
          IPv6AcceptRA = "no";
        };
      };

      # 物理网口 enp3s0 绑定到 br-lan
      "20-enp3s0-lan" = {
        matchConfig.Name = "enp3s0";
        networkConfig = {
          Bridge = "br-lan";
          DHCP = "no";
          LinkLocalAddressing = "no";
          IPv6AcceptRA = "no";
        };
      };

      # br-wan：宿主管理 IP（setup 阶段直连上级 192.168.8.1）。
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
      };

      # br-lan 配置 NAS 自身的内网 IP
      "30-br-lan" = {
        matchConfig.Name = "br-lan";
        networkConfig = {
          Address = "192.168.10.2/24";
          # setup 阶段默认路由走 br-wan（192.168.8.1）；此处仅保留 192.168.10 网段连接路由，
          # 供访问路由 VM 与未来下游 LAN。接好 LAN 后可改回经路由 VM。
        };
      };
    };
  };
}
