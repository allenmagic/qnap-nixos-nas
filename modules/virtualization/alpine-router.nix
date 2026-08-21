{ config, pkgs, lib, ... }:

let
  # 生成 Alpine Router 部署脚本
  installScript = pkgs.writeShellScript "install.sh" ''
    #!/bin/sh
    # Alpine Router 自动化配置脚本
    # 用途：在 Alpine Linux VM 中一键安装软件包并同步配置文件

    set -e  # 遇到错误立即退出

    # 配置目录（脚本所在目录的 base/ 子目录）
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    BASE_DIR="''${SCRIPT_DIR}/base"

    # 颜色输出
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color

    log_info() {
        echo -e "''${GREEN}[INFO]''${NC} $1"
    }

    log_warn() {
        echo -e "''${YELLOW}[WARN]''${NC} $1"
    }

    log_error() {
        echo -e "''${RED}[ERROR]''${NC} $1"
        exit 1
    }

    # 检查是否为 root
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
    fi

    # 检查是否为 Alpine Linux
    if [ ! -f /etc/alpine-release ]; then
        log_error "This script is designed for Alpine Linux only"
    fi

    log_info "Starting Alpine Router configuration..."

    # ============================================================
    # 1. 更新软件仓库并安装必要软件包
    # ============================================================
    log_info "Updating package repositories..."
    apk update

    log_info "Installing required packages..."
    apk add --no-cache \
        iptables \
        ip6tables \
        nftables \
        dnsmasq \
        chrony \
        curl \
        wget \
        tcpdump \
        htop \
        iftop \
        mtr \
        vim \
        nano \
        bash \
        openssh \
        rsync

    # 可选：Tailscale（如果需要 VPN）
    if [ "''${INSTALL_TAILSCALE:-yes}" = "yes" ]; then
        log_info "Installing Tailscale..."
        apk add --no-cache tailscale
    fi

    # ============================================================
    # 2. 同步配置文件
    # ============================================================
    log_info "Syncing configuration files from ''${BASE_DIR}..."

    if [ ! -d "$BASE_DIR" ]; then
        log_error "Configuration directory ''${BASE_DIR} not found"
    fi

    # 2.1 主配置文件
    log_info "  - Copying main config files..."
    [ -f "''${BASE_DIR}/nftables.nft" ] && cp -v "''${BASE_DIR}/nftables.nft" /etc/nftables.nft
    [ -f "''${BASE_DIR}/dnsmasq.conf" ] && cp -v "''${BASE_DIR}/dnsmasq.conf" /etc/dnsmasq.conf
    [ -f "''${BASE_DIR}/chrony.conf" ] && cp -v "''${BASE_DIR}/chrony.conf" /etc/chrony/chrony.conf

    # 2.2 模块化配置目录
    log_info "  - Syncing modular config directories..."

    sync_dir() {
        local src="$1"
        local dest="$2"
        if [ -d "$src" ]; then
            mkdir -p "$dest"
            rsync -av --delete "''${src}/" "''${dest}/"
            log_info "    Synced: ''${src} -> ''${dest}"
        else
            log_warn "    Skipped: ''${src} (not found)"
        fi
    }

    sync_dir "''${BASE_DIR}/conf.d" "/etc/conf.d"
    sync_dir "''${BASE_DIR}/dnsmasq.d" "/etc/dnsmasq.d"
    sync_dir "''${BASE_DIR}/nftables.d" "/etc/nftables.d"
    sync_dir "''${BASE_DIR}/sysctl.d" "/etc/sysctl.d"
    sync_dir "''${BASE_DIR}/modules-load.d" "/etc/modules-load.d"
    sync_dir "''${BASE_DIR}/init" "/etc/init.d"
    sync_dir "''${BASE_DIR}/local.d" "/etc/local.d"
    sync_dir "''${BASE_DIR}/tailscale" "/etc/tailscale"

    # 确保脚本可执行
    chmod +x /etc/init.d/* 2>/dev/null || true
    chmod +x /etc/local.d/*.start 2>/dev/null || true

    # ============================================================
    # 3. 网络配置（适配 VM 环境）
    # ============================================================
    log_info "Configuring network interfaces..."

    cat > /etc/network/interfaces <<'EOF'
    auto lo
    iface lo inet loopback

    # WAN 口（eth0 连接 br-wan）
    auto eth0
    iface eth0 inet dhcp
        hostname alpine-router

    # LAN 口（eth1 连接 br-lan）
    auto eth1
    iface eth1 inet static
        address 192.168.8.1
        netmask 255.255.255.0
    EOF

    # 如果需要自定义 IP，可以通过环境变量传入
    if [ -n "$LAN_IP" ]; then
        sed -i "s|address 192.168.8.1|address $LAN_IP|" /etc/network/interfaces
        log_info "  - LAN IP set to $LAN_IP"
    fi

    # ============================================================
    # 4. 应用系统参数
    # ============================================================
    log_info "Applying sysctl parameters..."
    sysctl -p /etc/sysctl.d/*.conf 2>/dev/null || true

    log_info "Loading kernel modules..."
    if [ -d /etc/modules-load.d ]; then
        for conf in /etc/modules-load.d/*.conf; do
            [ -f "$conf" ] && while read -r module; do
                [ -n "$module" ] && [ "''${module#\#}" = "$module" ] && modprobe "$module" 2>/dev/null || true
            done < "$conf"
        done
    fi

    # ============================================================
    # 5. 启用并启动服务
    # ============================================================
    log_info "Enabling services..."

    enable_service() {
        local service=$1
        if rc-service "$service" status >/dev/null 2>&1 || [ -f "/etc/init.d/$service" ]; then
            rc-update add "$service" default 2>/dev/null || rc-update add "$service" boot 2>/dev/null || true
            log_info "  - Enabled: $service"
        else
            log_warn "  - Service not found: $service"
        fi
    }

    # 基础服务
    enable_service networking
    enable_service nftables
    enable_service dnsmasq
    enable_service chronyd
    enable_service sshd
    enable_service local

    # 可选服务
    [ "''${INSTALL_TAILSCALE:-yes}" = "yes" ] && enable_service tailscale

    # ============================================================
    # 6. 启动服务
    # ============================================================
    log_info "Starting services..."

    start_service() {
        local service=$1
        if rc-service "$service" status >/dev/null 2>&1; then
            rc-service "$service" restart
            log_info "  - Started: $service"
        fi
    }

    # 重启网络（谨慎：可能断开 SSH）
    if [ "''${RESTART_NETWORK:-no}" = "yes" ]; then
        log_warn "Restarting network (SSH may disconnect)..."
        rc-service networking restart
    fi

    # 启动防火墙
    nft -f /etc/nftables.nft && log_info "  - nftables rules loaded"

    # 启动其他服务
    start_service dnsmasq
    start_service chronyd
    start_service sshd

    # ============================================================
    # 7. Tailscale 配置（可选）
    # ============================================================
    if [ "''${INSTALL_TAILSCALE:-yes}" = "yes" ] && [ -n "$TAILSCALE_AUTHKEY" ]; then
        log_info "Configuring Tailscale..."
        tailscale up --authkey="$TAILSCALE_AUTHKEY" --advertise-routes=192.168.8.0/24 --accept-routes
    fi

    # ============================================================
    # 8. 最终检查
    # ============================================================
    log_info "Configuration complete! Summary:"
    echo ""
    echo "Services status:"
    rc-status

    echo ""
    echo "Network interfaces:"
    ip -brief addr

    echo ""
    echo "nftables rules:"
    nft list ruleset | head -20

    echo ""
    log_info "Alpine Router is ready!"
    log_info "Access LAN interface at: 192.168.8.1"
    log_warn "Remember to save changes: lbu commit -d"
  '';

  # 打包部署文件（install.sh + base 配置）
  alpineRouterDeployPkg = pkgs.stdenv.mkDerivation {
    name = "alpine-router-deploy";
    src = ../../alpine-router/base;

    installPhase = ''
      mkdir -p $out/base
      # 复制 base 配置目录（src 即 base 目录本身，源文件在构建根目录）
      cp -r . $out/base/
      # 复制安装脚本
      cp ${installScript} $out/install.sh
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

      VM_NAME="alpine-router"
      VM_IP="192.168.8.1"
      DEPLOY_PKG="/etc/libvirt/alpine-router-deploy.tar.gz"

      echo "Deploying Alpine Router configuration..."

      # 检查 VM 是否在线
      if ! ping -c 1 -W 2 "$VM_IP" >/dev/null 2>&1; then
        echo "Error: VM is offline or not reachable at $VM_IP"
        exit 1
      fi

      # 传输部署包
      echo "Uploading deployment package..."
      scp "$DEPLOY_PKG" "root@$VM_IP:/tmp/alpine-router-deploy.tar.gz"

      # 执行安装脚本
      echo "Running install.sh on VM..."
      ssh "root@$VM_IP" 'cd /tmp && tar xzf alpine-router-deploy.tar.gz && sh install.sh'

      echo "Deployment complete!"
    '')

    (pkgs.writeShellScriptBin "alpine-router-shell" ''
      #!/bin/sh
      # 快速连接到 Alpine Router VM
      ssh root@192.168.8.1 "$@"
    '')
  ];
}
