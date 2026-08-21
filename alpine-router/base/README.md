# Alpine Router base/ 配置目录

本目录是 Alpine 路由 VM 的配置源：`modules/virtualization/alpine-router.nix` 在构建时把它打包为部署 tarball，`install.sh` 在 VM 内将其 rsync 到 `/etc`。

## 来源

最初从 [nanopi-r3s-rootfs](https://github.com/allenmagic/nanopi-r3s-rootfs) 仓库（rev `0ce5ca8`）导入，现独立在本仓库维护，与 NanoPi R3S 设备配置解耦。

## 结构

| 路径 | 作用 | VM 内部署目标 |
|---|---|---|
| `nftables.nft` | 防火墙主配置 | `/etc/nftables.nft` |
| `nftables.d/` | 防火墙规则模块 | `/etc/nftables.d/` |
| `dnsmasq.conf`、`dnsmasq.d/` | DNS/DHCP 配置 | `/etc/dnsmasq.conf`、`/etc/dnsmasq.d/` |
| `chrony.conf` | NTP 时间同步 | `/etc/chrony/chrony.conf` |
| `sysctl.d/` | 内核参数 | `/etc/sysctl.d/` |
| `modules-load.d/` | 内核模块自动加载 | `/etc/modules-load.d/` |
| `init/` | 服务脚本（多 init 系统） | `/etc/init.d/` |
| `local.d/` | 本地启动脚本 | `/etc/local.d/` |
| `tailscale/` | Tailscale 配置 | `/etc/tailscale/` |

## 占位符与构建时替换

`nftables.d/00-inet-vars.nft` 和 `dnsmasq.d/10-dhcp-eth1.conf` 中的 `__XXX__` 占位符由 **Nix 构建时替换**（`modules/virtualization/alpine-router.nix` 的 `postPatch`），网络参数常量定义在同文件的 `let` 块中，**必须与 `modules/network/bridges.nix` 的 br-lan 配置保持一致**。

## ⚠️ R3S 环境遗留，待处理

- `nftables.d/00-inet-vars.nft`：`PROXY_SERVER_IP = 192.168.8.180` 为 R3S 环境遗留（被 20-inet-filter.nft 引用）
- `local.d/00-leds.start`：R3S 硬件 LED 控制（`/sys/class/leds/wan_led` 等），VM 中无效
- `local.d/99-hw-tweak.start`：R3S 网卡调优（UDP GRO、RPS、CPU 调度），VM 环境需重新评估
- `modules-load.d/r3s-router.conf`：文件名含 r3s，内容（tun、wireguard）在 VM 中仍适用

## 修改后生效流程

```bash
sudo nixos-rebuild switch --flake .#default   # 重新生成部署包
alpine-router-deploy                          # 部署到 VM
```
