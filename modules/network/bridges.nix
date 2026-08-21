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
      # 物理网口 eno1 绑定到 br-wan
      "20-eno1-wan" = {
        matchConfig.Name = "eno1";
        networkConfig = {
          Bridge = "br-wan";
          # 宿主机不在 WAN 口配置 IP（由 Alpine VM 管理）
          DHCP = "no";
          LinkLocalAddressing = "no";
          IPv6AcceptRA = "no";
        };
      };

      # 物理网口 eno2 绑定到 br-lan
      "20-eno2-lan" = {
        matchConfig.Name = "eno2";
        networkConfig = {
          Bridge = "br-lan";
          DHCP = "no";
          LinkLocalAddressing = "no";
          IPv6AcceptRA = "no";
        };
      };

      # br-wan 不配置 IP（完全由 Alpine VM 管理）
      "30-br-wan" = {
        matchConfig.Name = "br-wan";
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
          IPv6AcceptRA = "no";
        };
      };

      # br-lan 配置 NAS 自身的内网 IP
      "30-br-lan" = {
        matchConfig.Name = "br-lan";
        networkConfig = {
          Address = "192.168.8.2/24";
          Gateway = "192.168.8.1";  # 指向 Alpine VM 路由器
          DNS = [ "192.168.8.1" ];
        };
      };
    };
  };
}
