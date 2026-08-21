#!/bin/sh
# ============================================================
# Alpine Router 自动化安装脚本（VM 内以 root 执行）
#
# 通常由宿主机 `alpine-router-deploy` 调用：
#   上传 tarball（install.sh + base/ + lib/ + scripts/ + package.list）
#   → 上传可选密钥 env 文件（重命名为 ./env）
#   → 解包后执行本脚本，结束后自动删除 env 文件
#
# 可选环境变量（来自 env 文件，见 env.example）：
#   TAILSCALE_AUTH_KEY / CLOUDFLARED_TOKEN  密钥（不提供则跳过对应功能）
#   LAN_IP / LAN_NETMASK / LAN_NET          网络参数覆盖
#   RESTART_NETWORK                         首次部署时是否重启网络（默认 no）
#
# 网络参数默认值在 Nix 构建时注入（modules/virtualization/alpine-router.nix）
# ============================================================
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="${SCRIPT_DIR}/base"
LIB_DIR="${SCRIPT_DIR}/lib"

# ---- 网络参数默认值（Nix 构建时注入）----
WAN_IFACE="${WAN_IFACE:-eth0}"
LAN_IFACE="${LAN_IFACE:-eth1}"
LAN_IP="${LAN_IP:-__LAN_IP__}"
LAN_NETMASK="${LAN_NETMASK:-__LAN_NETMASK__}"
LAN_NET="${LAN_NET:-__LAN_NET__}"
LAN_BROADCAST="${LAN_BROADCAST:-__LAN_BROADCAST__}"
DHCP_RANGE_START="${DHCP_RANGE_START:-__DHCP_RANGE_START__}"
DHCP_RANGE_END="${DHCP_RANGE_END:-__DHCP_RANGE_END__}"
DHCP_LEASE_TIME="${DHCP_LEASE_TIME:-__DHCP_LEASE_TIME__}"
export WAN_IFACE LAN_IFACE LAN_IP LAN_NETMASK LAN_NET LAN_BROADCAST \
       DHCP_RANGE_START DHCP_RANGE_END DHCP_LEASE_TIME

# ---- 可选密钥 env 文件（deploy 脚本上传为 ./env）----
if [ -f "${SCRIPT_DIR}/env" ]; then
    echo "[install] 加载 env 文件..."
    . "${SCRIPT_DIR}/env"
fi
# 退出时清理密钥文件
trap 'rm -f "${SCRIPT_DIR}/env"' EXIT

# ---- 日志工具 ----
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ---- 预检 ----
[ "$(id -u)" -eq 0 ] || log_error "必须以 root 执行"
[ -f /etc/alpine-release ] || log_error "仅支持 Alpine Linux"
[ -d "${BASE_DIR}" ] || log_error "配置目录 ${BASE_DIR} 不存在"

log_info "开始配置 Alpine Router（脚本目录: ${SCRIPT_DIR}）"

# ============================================================
# 1. 安装软件包（package.list）
# ============================================================
. "${LIB_DIR}/packages.sh"
install_packages "${SCRIPT_DIR}/package.list"

# ============================================================
# 2. 部署配置文件（base/ → /etc）
# ============================================================
log_info "部署配置文件..."

sync_dir() {
    _src="$1"; _dest="$2"
    if [ -d "${_src}" ]; then
        mkdir -p "${_dest}"
        rsync -av --delete "${_src}/" "${_dest}/"
    else
        log_warn "  跳过 ${_src}（不存在）"
    fi
}

# 主配置文件
for _f_ in nftables.nft dnsmasq.conf chrony.conf; do
    [ -f "${BASE_DIR}/${_f_}" ] && cp -v "${BASE_DIR}/${_f_}" "/etc/${_f_}"
done

# 模块化配置目录
sync_dir "${BASE_DIR}/conf.d" "/etc/conf.d"
sync_dir "${BASE_DIR}/dnsmasq.d" "/etc/dnsmasq.d"
sync_dir "${BASE_DIR}/nftables.d" "/etc/nftables.d"
sync_dir "${BASE_DIR}/sysctl.d" "/etc/sysctl.d"
sync_dir "${BASE_DIR}/modules-load.d" "/etc/modules-load.d"
sync_dir "${BASE_DIR}/init.d" "/etc/init.d"
sync_dir "${BASE_DIR}/local.d" "/etc/local.d"
sync_dir "${BASE_DIR}/tailscale" "/etc/tailscale"

# 确保脚本可执行
chmod +x /etc/init.d/* 2>/dev/null || true
chmod +x /etc/local.d/*.start 2>/dev/null || true

# 运行时脚本 → /usr/local/bin/
install -m 0755 "${SCRIPT_DIR}/scripts/network-watchdog.sh" /usr/local/bin/network-watchdog

# 清理文档/示例文件
find /etc \( -name '*.md' -o -name '*.example' \) -exec rm -f {} + 2>/dev/null || true

# ============================================================
# 3. 网络配置（占位符兜底替换 + 生成 interfaces）
# ============================================================
. "${LIB_DIR}/network.sh"
configure_network

# ============================================================
# 4. 内核参数与模块
# ============================================================
log_info "应用 sysctl 参数..."
sysctl -p /etc/sysctl.d/*.conf 2>/dev/null || true

log_info "加载内核模块..."
for _conf_ in /etc/modules-load.d/*.conf; do
    [ -f "${_conf_}" ] || continue
    while read -r _mod_; do
        [ -n "${_mod_}" ] && [ "${_mod_#\#}" = "${_mod_}" ] && modprobe "${_mod_}" 2>/dev/null || true
    done < "${_conf_}"
done

# ============================================================
# 5. 服务注册与启动
# ============================================================
. "${LIB_DIR}/service.sh"
enable_and_start_services

# ============================================================
# 6. 密钥注入 + Tailscale 登录
# ============================================================
. "${LIB_DIR}/secrets.sh"
inject_secrets
tailscale_up

# ============================================================
# 7. 完整性检查
# ============================================================
. "${LIB_DIR}/check.sh"
check_system

# ============================================================
# 8. 汇总
# ============================================================
log_info "配置完成！服务状态:"
rc-status

echo ""
log_info "网络接口:"
ip -brief addr

echo ""
log_info "Alpine Router 就绪，LAN 地址: ${LAN_IP}"
log_warn "若为首次部署，请重启 VM 使网络配置完全生效"
