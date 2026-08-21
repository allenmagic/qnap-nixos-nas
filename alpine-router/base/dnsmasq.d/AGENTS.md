# dnsmasq.d 知识库

## 概述
dnsmasq 同时承担 LAN 的 **DHCP** 与 **DNS 转发**：既给内网设备下发地址，又作为内网 DNS 服务器（转发到上游公网 DNS）。

## 关键文件
| 文件 | 作用 | 关键点 |
|------|------|--------|
| `../dnsmasq.conf` | 全局监听与加载 | `interface=eth1` 仅监听 LAN；`bind-dynamic` 适配虚拟化接口时序；`conf-dir=/etc/dnsmasq.d/,*.conf` 加载本目录 |
| `00-base.conf` | DHCP 基础配置 | `dhcp-authoritative`；租约文件 `/var/lib/misc/dnsmasq.leases` |
| `10-dhcp-eth1.conf` | LAN 口 DHCP 地址池 | 占位符由 Nix 构建时替换（见 `modules/virtualization/alpine-router.nix`） |
| `10-static.conf` | 固定 IP 分配 | 格式：`dhcp-host=MAC地址,IP地址,设备名,租期(可选)` |
| `20-upstream-dns.conf` | 上游 DNS 服务器 | 阿里云 `223.5.5.5`/`223.6.6.6`、腾讯 `119.29.29.29` 等 |

## DHCP 行为（基于 10-dhcp-eth1.conf）
- **权威 DHCP**：`dhcp-authoritative` 加速客户端获取 IP。
- **地址池**：`192.168.8.100-192.168.8.200`，租期 24 小时。
- **下发网关**：`dhcp-option=…,3,192.168.8.1`（option 3 = router）。
- **下发 DNS**：`dhcp-option=…,6,192.168.8.1`（指向路由器自身 dnsmasq）。
- **广播地址**：`dhcp-option=…,28,192.168.8.255`。
- **classless 路由**：`dhcp-option=…,121,0.0.0.0/0,192.168.8.1`。
- **租约文件**：`/var/lib/misc/dnsmasq.leases`。

## 约定
- LAN 接口固定为 `eth1`，WAN 接口固定为 `eth0`（与 nftables 变量、`modules/virtualization/alpine-router.nix` 常量保持一致）。
- 网段为 `192.168.8.0/24`，多处硬编码（见 `CLAUDE.md`「当前状态与坑」），改网段需全局同步。
- dnsmasq **同时提供 DHCP 与 DNS**，请勿关闭 DNS 监听（NAS 宿主机把 DNS 指向本机 `192.168.8.1`）。

## 反模式（本项目）
- 不要在 dnsmasq 中关闭 DNS（没有 `port=0`，本项目 DNS 由 dnsmasq 而非 sing-box 提供）。
- 不要在 WAN 口开启 DHCP（`interface=eth1` 已限定只监听 LAN）。
- 修改地址池/网段时，需同步 `modules/network/bridges.nix` 与 `modules/virtualization/alpine-router.nix`。
