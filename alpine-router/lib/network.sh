#!/bin/sh
#
# lib/network.sh —— 网络配置（ifupdown）
#   被 install.sh source 调用
#   定义 configure_network()
#
#   网络参数默认值由 install.sh 导出（Nix 构建时注入），
#   可通过 env 文件在部署时覆盖。
#

# 占位符兜底替换（主替换已在 Nix 构建时完成，此处保证运行时覆盖生效）
_replace_placeholders() {
    for _f_ in /etc/dnsmasq.d/*.conf; do
        [ -f "${_f_}" ] || continue
        sed -i \
            -e "s|__LAN_IFACE__|${LAN_IFACE}|g" \
            -e "s|__LAN_IP__|${LAN_IP}|g" \
            -e "s|__DHCP_RANGE_START__|${DHCP_RANGE_START}|g" \
            -e "s|__DHCP_RANGE_END__|${DHCP_RANGE_END}|g" \
            -e "s|__DHCP_LEASE_TIME__|${DHCP_LEASE_TIME}|g" \
            -e "s|__LAN_NETMASK__|${LAN_NETMASK}|g" \
            -e "s|__LAN_NETWORK__|${LAN_BROADCAST}|g" \
            "${_f_}"
    done

    _NFT="/etc/nftables.d/00-inet-vars.nft"
    if [ -f "${_NFT}" ]; then
        sed -i \
            -e "s|__WAN_IFACE__|${WAN_IFACE}|g" \
            -e "s|__LAN_IFACE__|${LAN_IFACE}|g" \
            -e "s|__ROUTER_LAN_IP__|${LAN_IP}|g" \
            -e "s|__LAN_NET__|${LAN_NET}|g" \
            "${_NFT}"
    fi
}

configure_network() {
    echo "[network] === 配置网络（ifupdown）==="

    _replace_placeholders

    cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

# WAN 口（${WAN_IFACE} 连接 br-wan）
auto ${WAN_IFACE}
iface ${WAN_IFACE} inet dhcp

# LAN 口（${LAN_IFACE} 连接 br-lan）
auto ${LAN_IFACE}
iface ${LAN_IFACE} inet static
    address ${LAN_IP}
    netmask ${LAN_NETMASK}
EOF

    echo "[network] === 完成 ==="
}
