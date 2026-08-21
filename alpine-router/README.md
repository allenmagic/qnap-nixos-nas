# Alpine Router 部署目录

本目录用于管理 Alpine Linux 路由器 VM 的配置和部署（最初从 nanopi-r3s-rootfs 导入，现已解耦独立维护）。

## 目录结构

```
alpine-router/
├── base/                        # 配置源（Nix 构建时打包，占位符构建时替换）
│   ├── nftables.nft / nftables.d/    # 防火墙
│   ├── dnsmasq.conf / dnsmasq.d/     # DNS/DHCP
│   ├── chrony.conf                   # NTP 时间同步
│   ├── sysctl.d/                     # 内核参数调优
│   ├── modules-load.d/               # 内核模块自动加载
│   ├── init.d/                       # OpenRC 服务脚本
│   ├── local.d/                      # 本地启动脚本
│   └── tailscale/                    # Tailscale 配置
├── lib/                         # install.sh 的功能组件（source 使用）
│   ├── packages.sh              # package.list 解析 + 安装
│   ├── network.sh               # 占位符兜底替换 + interfaces 生成
│   ├── service.sh               # OpenRC 服务注册与启动
│   ├── secrets.sh               # Tailscale/Cloudflared 密钥注入
│   └── check.sh                 # 部署完整性检查
├── scripts/
│   └── network-watchdog.sh      # 网络看门狗运行时脚本（→ /usr/local/bin/）
├── install.sh                   # 主安装脚本（VM 内 root 执行）
├── package.list                 # 声明式软件包列表（[pm]/[dl@] 语法）
├── env.example                  # 部署密钥模板
└── README.md
```

## 密钥注入（env 文件）

Tailscale / Cloudflared 的密钥通过 env 文件注入，**不写入部署包**：

```bash
# 在 NAS 宿主机上
sudo cp /etc/nixos/alpine-router/env.example /etc/libvirt/alpine-router.env
sudo chmod 600 /etc/libvirt/alpine-router.env
# 编辑填入密钥：
#   TAILSCALE_AUTH_KEY=tskey-auth-...
#   CLOUDFLARED_TOKEN=eyJhIjoi...
```

`alpine-router-deploy` 会把该文件 scp 到 VM 并重命名为 `./env`，install.sh source 后：

- `TAILSCALE_AUTH_KEY` → `/etc/tailscale/authkey`（config.json 通过 `authKey: file:` 引用），随后自动 `tailscale up`
- `CLOUDFLARED_TOKEN` → `/etc/cloudflared/config.yml`

install.sh 结束（含失败）时删除 env 文件。不提供密钥则跳过对应功能。

## 部署流程

### 1. 创建 Alpine VM

```bash
# 下载 Alpine virt ISO（3.24-stable 分支）
wget https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/x86_64/alpine-virt-3.24.1-x86_64.iso

# 创建虚拟磁盘
sudo qemu-img create -f qcow2 /var/lib/libvirt/images/alpine-router.qcow2 8G

# 安装 VM
sudo virt-install \
  --name alpine-router \
  --memory 512 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/alpine-router.qcow2,format=qcow2 \
  --cdrom alpine-virt-3.24.1-x86_64.iso \
  --network bridge=br-wan,model=virtio \
  --network bridge=br-lan,model=virtio \
  --graphics none \
  --console pty,target_type=serial \
  --os-variant alpinelinux3.23 \
  --autostart
```

### 2. 基础 Alpine 安装

在 VM 控制台中执行：

```bash
# 运行安装向导
setup-alpine

# 配置选项：
# - Keyboard: us us
# - Hostname: alpine-router
# - Network:
#   - eth0: dhcp (WAN)
#   - eth1: 192.168.8.1/24 (LAN)
# - Root password: 设置密码
# - Timezone: Asia/Shanghai
# - Proxy: none
# - NTP: chrony
# - APK mirror: 选择国内镜像
# - SSH: openssh
# - Disk: sda
# - Mode: sys (安装到磁盘)

# 重启 VM
reboot
```

### 3. 部署配置

从 NixOS 宿主机执行：

```bash
# 使用提供的便捷命令（自动上传部署包 + 可选 env 密钥文件）
alpine-router-deploy

# 或手动执行
scp /etc/libvirt/alpine-router-deploy.tar.gz root@192.168.8.1:/tmp/
ssh root@192.168.8.1 'mkdir -p /tmp/alpine-router-deploy && cd /tmp/alpine-router-deploy \
  && tar xzf /tmp/alpine-router-deploy.tar.gz && sh install.sh'
```

> 首次部署后建议重启 VM（`sudo virsh reboot alpine-router`），使网络接口配置完全生效。服务本身会立即启动。

### 4. 验证配置

```bash
# SSH 进入 VM
alpine-router-shell

# 检查服务状态
rc-status

# 检查网络
ip -brief addr

# 检查防火墙规则
nft list ruleset

# 检查 DNS/DHCP
cat /etc/dnsmasq.d/10-dhcp-eth1.conf
ps aux | grep dnsmasq
```

## 网络拓扑

```
外网
  │
  │ DHCP
  ▼
br-wan ━━━ eth0 (Alpine VM WAN)
              │
              │ NAT/路由/防火墙
              │
           eth1 (Alpine VM LAN: 192.168.8.1)
              │
br-lan ━━━━━━┫
  │           │
  │           └─ NixOS 宿主 (192.168.8.2)
  │
  └─ 内网设备 (192.168.8.0/24，DHCP: 100-200)
```

## 更新配置

修改本目录下的任何配置（`base/`、`lib/`、`install.sh`、`package.list` 等）后：

```bash
# 1. 重新构建 NixOS（重新打包部署 tarball）
sudo nixos-rebuild switch --flake .#default

# 2. 部署到 Alpine VM
alpine-router-deploy
```

## 故障排查

### VM 无法启动

```bash
# 查看 VM 状态
sudo virsh list --all

# 启动 VM
sudo virsh start alpine-router

# 查看控制台
sudo virsh console alpine-router
```

### 网络不通

```bash
# 检查宿主机桥接
ip link show br-wan
ip link show br-lan

# 检查 VM 网络配置
alpine-router-shell
ip addr
ping -c 3 8.8.8.8    # 测试 WAN
ping -c 3 192.168.8.2  # 测试 LAN
```

### 服务未启动

```bash
alpine-router-shell

# 检查服务状态
rc-status

# 手动启动服务
rc-service nftables start
rc-service dnsmasq start
rc-service chronyd start

# 查看日志
dmesg | tail
cat /var/log/messages
```

## 性能优化

### 减少内存占用

```bash
# 384MB 对于纯路由功能足够
sudo virsh setmem alpine-router 384M --config
```

### 启用 virtio 加速

VM 已配置使用 virtio 网络驱动，无需额外配置。

## 备份与恢复

### 备份 VM

```bash
# 导出 VM 配置
sudo virsh dumpxml alpine-router > alpine-router.xml

# 备份磁盘镜像
sudo cp /var/lib/libvirt/images/alpine-router.qcow2 \
  /srv/backup/alpine-router-$(date +%Y%m%d).qcow2
```

### 恢复 VM

```bash
# 恢复磁盘镜像
sudo cp /srv/backup/alpine-router-20260821.qcow2 \
  /var/lib/libvirt/images/alpine-router.qcow2

# 重新定义 VM
sudo virsh define alpine-router.xml

# 启动 VM
sudo virsh start alpine-router
```
