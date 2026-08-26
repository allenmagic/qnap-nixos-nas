{ config, pkgs, lib, ... }:

let
  # ============================================================
  # 路由 VM 网络参数
  # 与 modules/network/bridges.nix 中的 br-lan 配置保持一致！
  # 修改网段时两边必须同步
  # ============================================================
  wanIface = "eth0";               # VM 的 WAN 口（接 br-wan）
  lanIface = "eth1";               # VM 的 LAN 口（接 br-lan）
  lanIp = "192.168.8.1";           # VM LAN 口 IP（NAS 的网关）
  lanNet = "192.168.8.0/24";
  lanNetmask = "255.255.255.0";
  lanBroadcast = "192.168.8.255";
  dhcpRangeStart = "192.168.8.100";
  dhcpRangeEnd = "192.168.8.200";
  dhcpLeaseTime = "24h";
  tsHostname = "alpine-router";

  # 打包部署文件（install.sh + base/ + lib/ + scripts/）
  # 注：软件包列表（package.list）只在 nanopi-r3s-rootfs 仓库维护，
  #     deploy 依赖的软件包由 r3s 构建产物提供
  alpineRouterDeployPkg = pkgs.stdenv.mkDerivation {
    name = "alpine-router-deploy";
    src = ../../alpine-router;

    # 构建时把 base/ 和 install.sh 中的占位符替换为具体配置
    postPatch = ''
      substituteInPlace base/nftables.d/00-inet-vars.nft \
        --replace-fail '__WAN_IFACE__' ${wanIface} \
        --replace-fail '__LAN_IFACE__' ${lanIface} \
        --replace-fail '__ROUTER_LAN_IP__' ${lanIp} \
        --replace-fail '__LAN_NET__' ${lanNet}

      substituteInPlace base/dnsmasq.d/10-dhcp-eth1.conf \
        --replace-fail '__LAN_IFACE__' ${lanIface} \
        --replace-fail '__LAN_IP__' ${lanIp} \
        --replace-fail '__LAN_NETWORK__' ${lanBroadcast} \
        --replace-fail '__DHCP_RANGE_START__' ${dhcpRangeStart} \
        --replace-fail '__DHCP_RANGE_END__' ${dhcpRangeEnd} \
        --replace-fail '__LAN_NETMASK__' ${lanNetmask} \
        --replace-fail '__DHCP_LEASE_TIME__' ${dhcpLeaseTime}

      substituteInPlace base/dnsmasq.conf \
        --replace-fail '__LAN_IFACE__' ${lanIface}

      substituteInPlace base/tailscale/config.json \
        --replace-fail '__TS_HOSTNAME__' ${tsHostname} \
        --replace-fail '__TS_ADVERTISE_ROUTES__' '"${lanNet}"'

      substituteInPlace install.sh \
        --replace-fail '__LAN_IP__' ${lanIp} \
        --replace-fail '__LAN_NETMASK__' ${lanNetmask} \
        --replace-fail '__LAN_NET__' ${lanNet} \
        --replace-fail '__LAN_BROADCAST__' ${lanBroadcast} \
        --replace-fail '__DHCP_RANGE_START__' ${dhcpRangeStart} \
        --replace-fail '__DHCP_RANGE_END__' ${dhcpRangeEnd} \
        --replace-fail '__DHCP_LEASE_TIME__' ${dhcpLeaseTime}
    '';

    installPhase = ''
      mkdir -p $out
      cp -r base $out/
      cp -r lib $out/
      cp -r scripts $out/
      cp install.sh $out/install.sh
      chmod +x $out/install.sh
    '';
  };

  # 打包为 tarball
  alpineRouterTarball = pkgs.runCommand "alpine-router-deploy.tar.gz" {} ''
    tar czf $out -C ${alpineRouterDeployPkg} .
  '';

in
{
  # 将部署包放到已知路径
  environment.etc."libvirt/alpine-router-deploy.tar.gz".source = alpineRouterTarball;

  # 提供便捷部署命令
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "alpine-router-deploy" ''
      #!/bin/sh
      set -e

      VM_IP="${lanIp}"
      DEPLOY_PKG="/etc/libvirt/alpine-router-deploy.tar.gz"
      ENV_FILE="/etc/libvirt/alpine-router.env"

      echo "Deploying Alpine Router configuration..."

      # 检查 VM 是否在线
      if ! ping -c 1 -W 2 "$VM_IP" >/dev/null 2>&1; then
        echo "Error: VM is offline or not reachable at $VM_IP"
        exit 1
      fi

      # 传输部署包
      echo "Uploading deployment package..."
      scp "$DEPLOY_PKG" "root@$VM_IP:/tmp/alpine-router-deploy.tar.gz"

      # 可选：传输密钥 env 文件（不存在则无密钥部署）
      if [ -f "$ENV_FILE" ]; then
        echo "Uploading env file (secrets)..."
        scp "$ENV_FILE" "root@$VM_IP:/tmp/alpine-router.env"
      else
        echo "Note: $ENV_FILE not found, deploying without secrets"
      fi

      # 执行安装脚本（结束后清理 /tmp 中的 tarball 和明文密钥 env 文件，保留退出码）
      echo "Running install.sh on VM..."
      ssh "root@$VM_IP" 'rm -rf /tmp/alpine-router-deploy && mkdir -p /tmp/alpine-router-deploy && cd /tmp/alpine-router-deploy && tar xzf /tmp/alpine-router-deploy.tar.gz && if [ -f /tmp/alpine-router.env ]; then mv /tmp/alpine-router.env ./env; fi; sh install.sh; _rc=$?; rm -f /tmp/alpine-router-deploy.tar.gz /tmp/alpine-router.env; exit $_rc'

      echo "Deployment complete!"
    '')

    (pkgs.writeShellScriptBin "alpine-router-shell" ''
      #!/bin/sh
      # 快速连接到 Alpine Router VM
      ssh root@${lanIp} "$@"
    '')
  ];
}
