# Alpine Router 部署目录

本目录用于管理 Alpine Linux 路由器 VM 的配置和部署。

## 配置来源

路由器配置来自 [nanopi-r3s-rootfs](https://github.com/allenmagic/nanopi-r3s-rootfs) 仓库的 `base/` 目录。

## 部署流程

### 1. 创建 Alpine VM

```bash
# 下载 Alpine virt ISO
wget https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86_64/alpine-virt-3.20.3-x86_64.iso

# 创建虚拟磁盘
sudo qemu-img create -f qcow2 /var/lib/libvirt/images/alpine-router.qcow2 8G

# 安装 VM
sudo virt-install \
  --name alpine-router \
  --memory 512 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/alpine-router.qcow2,format=qcow2 \
  --cdrom alpine-virt-3.20.3-x86_64.iso \
  --network bridge=br-wan,model=virtio \
  --network bridge=br-lan,model=virtio \
  --graphics none \
  --console pty,target_type=serial \
  --os-variant alpinelinux3.17 \
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
#   - eth1: 192.168.10.1/24 (LAN)
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
# 使用提供的便捷命令
alpine-router-deploy

# 或手动执行
scp /etc/libvirt/alpine-router-deploy.tar.gz root@192.168.10.1:/root/
ssh root@192.168.10.1 'cd /root && tar xzf alpine-router-deploy.tar.gz && sh install.sh'
```

### 4. 验证配置

```bash
# SSH 进入 VM
alpine-router-shell

# 或
ssh root@192.168.10.1

# 检查服务状态
rc-status

# 检查网络
ip addr
ip route

# 检查防火墙规则
nft list ruleset

# 检查 DNS/DHCP
cat /etc/dnsmasq.conf
ps aux | grep dnsmasq
```

## 配置文件说明

从 nanopi-r3s-rootfs 同步的配置：

- `base/nftables.nft` - 防火墙主配置
- `base/nftables.d/` - 防火墙规则模块
- `base/dnsmasq.conf` - DNS/DHCP 主配置
- `base/dnsmasq.d/` - DNS/DHCP 配置模块
- `base/chrony.conf` - NTP 时间同步
- `base/sysctl.d/` - 内核参数调优
- `base/modules-load.d/` - 内核模块自动加载
- `base/init/` - 初始化脚本
- `base/local.d/` - 本地启动脚本
- `base/tailscale/` - Tailscale VPN 配置

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
           eth1 (Alpine VM LAN: 192.168.10.1)
              │
br-lan ━━━━━━┫
  │           │
  │           └─ NixOS 宿主 (192.168.10.2)
  │
  └─ 内网设备 (192.168.10.0/24)
```

## 更新配置

当 nanopi-r3s-rootfs 配置更新后：

```bash
# 1. 在本仓库更新 flake inputs
nix flake lock --update-input alpine-router-configs

# 2. 重新构建 NixOS（生成新的部署包）
sudo nixos-rebuild switch --flake .#ts564

# 3. 部署到 Alpine VM
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
ping -c 3 8.8.8.8  # 测试 WAN
ping -c 3 192.168.10.2  # 测试 LAN
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

编辑 `modules/virtualization/libvirtd.nix`，调整 VM 内存：

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
