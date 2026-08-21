#!/bin/sh
#
# lib/service.sh —— OpenRC 服务注册与启动
#   被 install.sh source 调用
#   定义 enable_and_start_services()
#

# 注册开机自启
_enable_service() {
    _svc="$1"
    _rl="${2:-default}"
    if [ -f "/etc/init.d/${_svc}" ]; then
        rc-update add "${_svc}" "${_rl}" 2>/dev/null || true
        echo "  [enable] ${_svc} (${_rl})"
    else
        echo "  [skip] ${_svc}: /etc/init.d/${_svc} 不存在"
    fi
}

# 立即启动：已运行则 restart（重载配置），未运行则 start
_start_service() {
    _svc="$1"
    if [ -f "/etc/init.d/${_svc}" ]; then
        if rc-service "${_svc}" status >/dev/null 2>&1; then
            rc-service "${_svc}" restart
        else
            rc-service "${_svc}" start
        fi
        echo "  [start] ${_svc}"
    fi
}

enable_and_start_services() {
    echo "[service] === 注册开机自启 ==="

    _enable_service sysctl boot
    _enable_service local
    _enable_service networking

    _enable_service nftables
    _enable_service dnsmasq
    _enable_service sshd
    _enable_service chronyd
    _enable_service tailscale
    _enable_service cloudflared
    _enable_service network-watchdog

    echo "[service] === 立即启动 ==="

    # 防火墙规则最先加载
    nft -f /etc/nftables.nft && echo "  [start] nftables 规则已加载"

    _start_service dnsmasq
    _start_service chronyd
    _start_service sshd
    _start_service cloudflared
    _start_service tailscale
    _start_service network-watchdog

    # 网络重启（谨慎：可能断开 SSH，默认不执行）
    if [ "${RESTART_NETWORK:-no}" = "yes" ]; then
        echo "[service] 重启网络（SSH 可能断开）..."
        rc-service networking restart
    fi

    echo "[service] === 完成 ==="
}
