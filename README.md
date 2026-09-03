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
│   ├── virtualization/                # Alpine Router MicroVM（flake 模块引用）
│   ├── services/                      # Samba、NFS、Syncthing、Navidrome、Cockpit
│   ├── security/                      # SSH、sops-nix
│   └── users/                         # 用户配置
├── secrets/
│   ├── README.md                      # sops-nix 使用指南
│   └── secrets.yaml                   # 加密的密钥文件（需手动创建）

## Router VM 架构

VM 的生命周期由 [router-image](https://github.com/allenmagic/router-image)
仓库全权管理：

| 环节 | 位置 |
|---|---|
| 内核 + 镜像生产（自建内核 + rootfs + 配置烙入） | router-image CI → release asset（两件套） |
| 消费端声明（fetchurl、cloud-hypervisor systemd 单元、tap 挂桥、deploy） | `router-image` 的 `nixosModules.router`（本仓库 flake input 引用） |
| 密钥注入 | 宿主 sops-nix（secrets.yaml）→ `router-vm-deploy` 每次 VM 启动后自动注入 |

```nix
# 完整配置参考（模块已 import 并启用，见 modules/virtualization/default.nix）
services.router-vm = {
  # ── 总开关 ──
  enable = true;
  #   启用 Router VM。enable 后需重启宿主（isolcpus 内核参数生效需要）；
  #   宿主桥 br-wan/br-lan 须已由 modules/network/bridges.nix 创建。

  # ── 发行版 ──
  os = "alpine";
  #   rootfs 发行版：alpine（默认）| gentoo（均为 musl+OpenRC）。

  # ── CPU ──
  cpu = 0;
  #   隔离给 VM 独占的宿主核号：isolcpus=N + rcu_nocbs=N，宿主调度器
  #   不再使用该核；vcpu0 经 CH affinity pin 到该核。默认 0。
  #   ⚠️ 核号必须真实存在，改此参数需重启宿主。
  vcpus = 2;
  #   vCPU 总数：vcpu0 独占 `cpu` 指定的隔离核，其余 vCPU 由宿主调度器
  #   在非隔离核上动态调度。默认 2（1 独占 + 1 动态）。

  # ── 内存 ──
  mem = 512;
  #   guest 内存上限（MB）。
  initialBalloonMem = 256;
  #   初始 balloon 大小（MB，CH 要求 128M 对齐）：guest 实际可用 =
  #   mem - balloon；宿主 OOM 时自动放气归还（deflate_on_oom）。
  #   默认 512 / 256。

  # ── 网络桥（须与 modules/network/bridges.nix 一致，一般不用改） ──
  wanBridge = "br-wan";
  #   WAN 侧宿主桥：VM 的 preStart 创建 tap "router-wan"，
  #   networkd 自动将其加入此桥。
  lanBridge = "br-lan";
  #   LAN 侧宿主桥（tap "router-lan"）。
  vmIp = "192.168.10.1";
  #   VM LAN 口 IP（deploy 通道的 ssh 目标；与 bridges.nix 的网关指向一致）。
};
```

**升级镜像**：CI 出 release 自动同步 flake 模块的 tag+sha256 →
`nix flake update` → `nixos-rebuild` → VM 自动重启（rootfs 只读副本路径含
内容哈希）→ 密钥自动重新注入（guest 无状态，重启即清）。
**改密钥**：编辑 `secrets/secrets.yaml` → `nixos-rebuild` →
`systemctl restart router-vm-deploy`（或重启 VM 自动触发）。

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
ssh nas@192.168.10.2

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

### 5. 启用 Router VM

VM 全声明式（镜像与模块在 router-image 仓库），已在
`modules/virtualization/default.nix` 中启用 → `nixos-rebuild switch` →
重启宿主（isolcpus 生效）→ 配置 sops 密钥（secrets.yaml，见 INSTALL.md
第 6 步）。详细分步见 [INSTALL.md](INSTALL.md)。


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

### Router VM 配置更新

```bash
# 改配置：router-image 仓库（base/ 或 network.env）→ 触发 CI →
#         NAS 上 nix flake update + rebuild（VM 自动重启，rootfs 副本路径
#         含内容哈希；密钥由 router-vm-deploy 自动重新注入）
nix flake update
sudo nixos-rebuild switch --flake .#default

# 改密钥：编辑 secrets/secrets.yaml → rebuild 后手动补注入
sudo nixos-rebuild switch --flake .#default
sudo systemctl restart router-vm-deploy

# 或手动 SSH 进入 VM
router-vm-shell
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

浏览器访问 http://192.168.10.2:9090，用 `nas` 用户和系统密码登录，可管理虚拟机（创建/启动/停止/控制台）。

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
    Address = "192.168.10.2/24";  # 修改这里
    Gateway = "192.168.10.1";
    DNS = [ "192.168.10.1" ];
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
ping 192.168.10.1

# 进入 VM 检查
router-vm-shell
```

## 设计决策

- **Alpine VM 路由而非 NixOS 原生路由**：复用成熟的 Alpine 路由配置体系；故障隔离（路由问题不影响 NAS 存储服务）；内存占用小（512MB）；网络配置可独立备份与恢复
- **镜像烙入 + 密钥注入分离**：全部配置在 CI 构建时烙进镜像（出厂即正确），deploy 只注入密钥——配置更新走 CI 单仓库闭环，密钥更新走宿主本地秒级通道
- **模块化**：每个功能独立一个模块文件（`modules/`），VM 实现集中在 router-image 仓库

## 参考文档

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [qnap8528 模块文档](https://github.com/allenmagic/qnap8528)
- [sops-nix 使用指南](https://github.com/Mic92/sops-nix)

## License

MIT
