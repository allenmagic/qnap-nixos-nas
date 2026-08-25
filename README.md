# QNAP TS-564 NixOS NAS Configuration

基于 NixOS 的 QNAP TS-564 NAS 系统配置，使用 Flakes 进行声明式管理。

## 特性

- **声明式配置**: 所有配置通过 Nix 管理，可重现、可回滚
- **QNAP 硬件支持**: 集成 qnap8528 内核模块，支持风扇控制、LED、温度传感器
- **Alpine Router VM**: 使用独立 VM 处理网络路由、NAT、DHCP、DNS
- **Web 管理**: Cockpit Web 界面管理虚拟机与系统（插件可扩展）
- **存储服务**: Samba、NFS、Syncthing、Navidrome
- **安全管理**: sops-nix 加密密钥管理、SSH 密钥认证
- **自动化维护**: 定期垃圾回收、SMART 监控、SSD Trim

## 硬件配置

- **型号**: QNAP TS-564
- **CPU**: Intel N5095 (4核)
- **内存**: 8GB
- **网络**: 2×2.5G 网口 (eno1/eno2)
- **存储**:
  - 1×256GB SSD (系统盘)
  - 1×1TB SSD (缓存盘)
  - 2×3TB HDD (RAID1 数据盘)
  - 1×2TB HDD (备份盘)

## 目录结构

```
.
├── flake.nix                          # Flake 入口文件
├── flake.lock                         # 依赖锁定（必须提交）
├── CLAUDE.md                          # Claude Code 开发指引
├── configuration.nix                  # 主机配置
├── filesystem.nix                     # 文件系统挂载与维护配置
├── hardware-configuration.nix.example # 硬件配置模板
├── hardware-configuration.nix         # 硬件配置（安装时生成，不入库）
├── README.md                          # 本文档
├── INSTALL.md                         # 从零安装完整指南
├── modules/
│   ├── system/                        # 基础系统配置（语言、软件包、Nix 设置）
│   ├── hardware/                      # 硬件相关（风扇、传感器）
│   ├── network/                       # 网络配置（桥接、防火墙）
│   ├── virtualization/                # libvirtd 和 Alpine Router
│   ├── services/                      # Samba、NFS、Syncthing、Navidrome、Cockpit
│   ├── security/                      # SSH、sops-nix
│   └── users/                         # 用户配置
├── secrets/
│   ├── README.md                      # sops-nix 使用指南
│   └── secrets.yaml                   # 加密的密钥文件（需手动创建）
└── alpine-router/
    ├── base/                          # Alpine 路由 VM 配置源（占位符构建时替换）
    ├── lib/                           # install.sh 功能组件（装包/网络/服务/密钥/检查）
    ├── scripts/network-watchdog.sh    # 网络看门狗运行时脚本
    ├── install.sh                     # VM 内主安装脚本
    ├── package.list                   # 声明式软件包列表
    ├── env.example                    # 部署密钥模板（Tailscale/Cloudflared）
    └── README.md                      # Alpine Router VM 部署指南
```

## 快速开始

> 📖 完整的分步安装指南（含磁盘分区、RAID、Alpine VM 创建、验收清单）见 **[INSTALL.md](INSTALL.md)**。以下为精简流程。

### 1. 准备工作

1. 下载 NixOS minimal ISO
2. 制作启动 U 盘
3. 仅插入 256GB SSD，从 U 盘启动

### 2. 磁盘分区和文件系统创建

```bash
# 数据盘：Btrfs 原生 RAID1（两块 3TB HDD，内建 checksum + 每月自动 scrub）
mkfs.btrfs -m raid1 -d raid1 -L data \
  /dev/disk/by-id/ata-WDC_WD30EFRX-xxx \
  /dev/disk/by-id/ata-WDC_WD30EFRX-yyy

# 缓存/备份盘
mkfs.ext4 -L cache /dev/disk/by-id/ata-KINGSTON_SA400S37480G-xxx
mkfs.ext4 -L backup /dev/disk/by-id/ata-ST2000LM007-xxx
```

### 3. 安装 NixOS

```bash
# 挂载文件系统
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/boot /mnt/boot

# 生成硬件配置
nixos-generate-config --root /mnt

# 克隆本配置仓库
cd /mnt/etc/nixos
git clone https://github.com/allenmagic/qnap-nixos-nas.git .

# 将生成的 hardware-configuration.nix 移动到仓库根目录
mv hardware-configuration.nix .

# 重要：flake 只能读取 git 跟踪的文件，用 intent-to-add 让其可见（文件本身不会被提交）
git add -N -f hardware-configuration.nix

# 编辑 modules/users/nas-user.nix，添加你的 SSH 公钥

# 安装系统
nixos-install --flake .#default

# 重启
reboot
```

### 4. 首次启动配置

```bash
# SSH 登录
ssh nas@192.168.8.2

# 生成 sops age 密钥
sudo mkdir -p /var/lib/sops-nix
sudo age-keygen -o /var/lib/sops-nix/key.txt
sudo chmod 600 /var/lib/sops-nix/key.txt

# 显示公钥（用于加密 secrets.yaml）
sudo cat /var/lib/sops-nix/key.txt | grep "public key:"

# 设置 Samba 密码
sudo smbpasswd -a nas

# 设置 nas 系统密码（Cockpit Web 登录需要；SSH 仍只用密钥）
mkpasswd -m sha-512
# 将输出哈希填入 modules/users/nas-user.nix 的 hashedPassword，然后重建系统
sudo nixos-rebuild switch --flake .#default
```

### 5. 部署 Alpine Router VM

#### 手动方式

```bash
# 下载 Alpine ISO（3.24-stable 分支）
wget https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/x86_64/alpine-virt-3.24.1-x86_64.iso

# 创建虚拟磁盘
sudo qemu-img create -f qcow2 /var/lib/libvirt/images/alpine-router.qcow2 8G

# 创建 VM
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

# 在 Alpine 控制台完成基础安装
# - setup-alpine
# - 配置 eth0 为 DHCP (WAN)
# - 配置 eth1 为 192.168.8.1/24 (LAN)
# - 安装到磁盘 (sys 模式)

# VM 重启后，部署配置
alpine-router-deploy
```

## 日常使用

### 系统更新

```bash
# 更新 flake 依赖
nix flake update

# 重建系统
sudo nixos-rebuild switch --flake .#default

# 如果有问题，回滚
sudo nixos-rebuild switch --rollback
```

### Alpine Router 配置更新

```bash
# 在修改 alpine-router/ 下配置后（base/、lib/、install.sh、package.list 等）
sudo nixos-rebuild switch --flake .#default
alpine-router-deploy

# 或手动 SSH 进入 VM
alpine-router-shell
```

### 服务管理

```bash
# 查看服务状态
systemctl status samba
systemctl status nfs-server
systemctl status syncthing
systemctl status navidrome
systemctl status cockpit

# 重启服务
sudo systemctl restart samba
```

### Cockpit Web 管理

浏览器访问 http://192.168.8.2:9090，用 `nas` 用户和系统密码登录，可管理虚拟机（创建/启动/停止/控制台）。

> 注意：Cockpit 登录使用 PAM 密码认证，需要在 `modules/users/nas-user.nix` 中为 nas 用户设置系统密码（`mkpasswd -m sha-512` 生成哈希填入 `hashedPassword`）。

### 监控

```bash
# 查看风扇转速和温度
sensors

# 查看磁盘 SMART 状态
sudo smartctl -a /dev/sda

# 查看 Btrfs RAID 状态
btrfs filesystem show
btrfs device stats /srv/data
```

## 自定义配置

### 修改网络 IP

编辑 `modules/network/bridges.nix`:

```nix
"30-br-lan" = {
  matchConfig.Name = "br-lan";
  networkConfig = {
    Address = "192.168.8.2/24";  # 修改这里
    Gateway = "192.168.8.1";
    DNS = [ "192.168.8.1" ];
  };
};
```

### 添加 Samba 共享

编辑 `modules/services/samba.nix`，在 `settings` 中添加新的共享段（每个共享名对应一个 smb.conf 段）：

```nix
settings.newshare = {
  "path" = "/srv/data/newshare";
  "read only" = "no";
  "valid users" = "nas";
  "force user" = "nas";
  "force group" = "nas";
};
```

### 添加 SSH 公钥

编辑 `modules/users/nas-user.nix`:

```nix
openssh.authorizedKeys.keys = [
  "ssh-ed25519 AAAAC3... your-key-here"
];
```

## 故障排查

### QNAP 模块未加载

```bash
# 检查模块是否已加载
lsmod | grep qnap8528

# 查看 dmesg 日志
dmesg | grep qnap8528

# 手动加载
sudo modprobe qnap8528
```

### 数据卷未自动挂载

```bash
# 重新扫描并挂载
sudo btrfs device scan
sudo mount /srv/data

# 确认卷标与 filesystem.nix 一致
btrfs filesystem show
```

### Alpine VM 网络问题

```bash
# 检查桥接状态
ip link show br-wan
ip link show br-lan

# 测试连通性
ping 192.168.8.1

# 进入 VM 检查
alpine-router-shell
```

## 设计决策

- **Alpine VM 路由而非 NixOS 原生路由**：复用成熟的 Alpine 路由配置体系；故障隔离（路由问题不影响 NAS 存储服务）；内存占用小（512MB）；网络配置可独立备份与恢复
- **install.sh 而非 cloud-init**：配置更新只需重新运行脚本；可逐步调试；直接复用 base/ 文件结构；可添加任意自定义逻辑
- **模块化**：每个功能独立一个模块文件（`modules/` 与 `alpine-router/lib/`），便于启用/禁用与维护

## 参考文档

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [qnap8528 模块文档](https://github.com/allenmagic/qnap8528)
- [sops-nix 使用指南](https://github.com/Mic92/sops-nix)

## License

MIT
