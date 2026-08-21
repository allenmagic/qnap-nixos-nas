# 项目创建总结

> ⚠️ **本文档已过时**：本文记录项目初始创建时的工作。目录结构此后已扁平化（见 commit 8111ae7），`hosts/ts564/` 和 `.#ts564` 均已不存在。当前状态以 [README.md](README.md) 和 [CLAUDE.md](CLAUDE.md) 为准。

## 已完成的工作

### 1. 仓库结构

```
qnap-nixos-nas/
├── flake.nix                          # Flake 入口，集成 qnap8528、sops-nix、alpine-router-configs
├── .gitignore                         # Git 忽略规则
├── README.md                          # 完整的使用文档
├── hosts/ts564/
│   ├── default.nix                    # 主机基础配置
│   ├── disks.nix                      # RAID1 + 文件系统配置
│   └── hardware-configuration.nix.example  # 硬件配置模板
├── modules/
│   ├── system/
│   │   ├── default.nix
│   │   ├── locale.nix                 # 时区和本地化
│   │   ├── packages.nix               # 系统工具包
│   │   └── nix-settings.nix           # Nix GC 和优化
│   ├── hardware/
│   │   ├── default.nix
│   │   ├── fancontrol.nix             # 使用 qnap8528/examples/fancontrol.conf
│   │   └── sensors.nix                # SMART 监控
│   ├── network/
│   │   ├── default.nix
│   │   └── bridges.nix                # br-wan + br-lan 桥接配置
│   ├── virtualization/
│   │   ├── default.nix
│   │   ├── libvirtd.nix               # KVM/libvirt 配置
│   │   └── alpine-router.nix          # 自动生成 install.sh + 部署工具
│   ├── services/
│   │   ├── default.nix
│   │   ├── samba.nix                  # SMB 文件共享
│   │   ├── nfs.nix                    # NFS 文件共享
│   │   ├── syncthing.nix              # 文件同步
│   │   └── navidrome.nix              # 音乐流媒体
│   ├── security/
│   │   ├── default.nix
│   │   ├── ssh.nix                    # SSH 密钥认证
│   │   └── sops.nix                   # 密钥管理配置
│   └── users/
│       ├── default.nix
│       └── nas-user.nix               # nas 用户 + storage 组
├── secrets/
│   └── README.md                      # sops-nix 使用指南
└── alpine-router/
    └── README.md                      # Alpine Router 部署文档
```

### 2. 核心特性

#### 硬件支持
- ✅ 集成 `qnap8528` 内核模块（通过 flake input）
- ✅ 自动使用 TS-564 的 fancontrol 配置
- ✅ SMART 磁盘健康监控
- ✅ 温度和风扇转速监控

#### 网络架构
- ✅ 双网口桥接 (br-wan + br-lan)
- ✅ NixOS 宿主机 IP: 192.168.10.2
- ✅ Alpine Router VM: 192.168.10.1 (网关)
- ✅ 防火墙规则已配置

#### 虚拟化
- ✅ libvirtd + KVM 配置
- ✅ 自动生成 Alpine Router 部署脚本 (install.sh)
- ✅ 集成 nanopi-r3s-rootfs 配置
- ✅ 提供便捷命令：`alpine-router-deploy` 和 `alpine-router-shell`

#### 存储服务
- ✅ Samba (SMB3, 加密支持)
- ✅ NFS (NFSv4)
- ✅ Syncthing (文件同步)
- ✅ Navidrome (音乐服务器)

#### 安全
- ✅ sops-nix 密钥管理框架
- ✅ SSH 密钥认证（禁用密码登录）
- ✅ 防火墙配置

#### 存储
- ✅ mdadm RAID1 支持
- ✅ XFS (数据盘) + ext4 (缓存/备份)
- ✅ 自动 SSD Trim

### 3. 已生成的文档

1. **README.md** - 完整的安装和使用指南
2. **secrets/README.md** - sops-nix 密钥管理说明
3. **alpine-router/README.md** - Alpine Router VM 部署指南

## 下一步操作

### Git 配置和提交

```bash
cd ~/Projects/qnap-nixos-nas

# 配置 Git 用户信息（如果还没配置）
git config user.name "Your Name"
git config user.email "your.email@example.com"

# 提交
git commit -m "Initial commit: QNAP TS-564 NixOS NAS configuration"

# 创建 GitHub 仓库后
git remote add origin https://github.com/allenmagic/qnap-nixos-nas.git
git push -u origin main
```

### 部署前的准备工作

1. **替换占位符**：
   - `modules/users/nas-user.nix` - 添加你的 SSH 公钥
   - `hosts/ts564/disks.nix` - 安装时填入实际的 RAID UUID

2. **创建 GitHub 仓库**：
   ```bash
   gh repo create qnap-nixos-nas --public --source=. --remote=origin
   git push -u origin main
   ```

3. **准备 Alpine Router 配置**：
   - 确保 `nanopi-r3s-rootfs` 仓库已公开
   - 或将其添加为 git submodule（如果是私有仓库）

### 实际部署流程

1. **准备硬件**：
   - 仅插入 256GB SSD
   - 准备 NixOS minimal ISO U 盘

2. **创建 RAID 和文件系统**：
   ```bash
   mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sdX /dev/sdY
   mkfs.xfs -L data /dev/md0
   mkfs.ext4 -L cache /dev/sdZ
   mkfs.ext4 -L backup /dev/sdW
   ```

3. **安装 NixOS**：
   ```bash
   # 挂载文件系统
   mount /dev/disk/by-label/nixos /mnt
   mount /dev/disk/by-label/boot /mnt/boot
   
   # 生成硬件配置
   nixos-generate-config --root /mnt
   
   # 克隆配置
   cd /mnt/etc/nixos
   git clone https://github.com/allenmagic/qnap-nixos-nas.git .
   
   # 移动生成的硬件配置
   mv hardware-configuration.nix hosts/ts564/
   
   # 编辑 disks.nix 填入 RAID UUID
   # 编辑 nas-user.nix 添加 SSH 公钥
   
   # 安装
   nixos-install --flake .#ts564
   ```

4. **首次启动**：
   ```bash
   # 生成 sops age 密钥
   sudo mkdir -p /var/lib/sops-nix
   sudo age-keygen -o /var/lib/sops-nix/key.txt
   
   # 设置 Samba 密码
   sudo smbpasswd -a nas
   ```

5. **部署 Alpine Router**：
   ```bash
   # 创建 VM（见 alpine-router/README.md）
   # 然后运行
   alpine-router-deploy
   ```

## 关键设计决策

### 为什么选择 Alpine VM 而不是 NixOS 原生路由？

1. **配置灵活性** - 可以直接使用现有的 nanopi-r3s-rootfs 配置
2. **故障隔离** - 路由故障不影响 NAS 存储服务
3. **轻量级** - Alpine 只需 384-512MB 内存
4. **迁移性** - 网络配置可以独立备份和恢复

### 为什么使用 install.sh 而不是 cloud-init？

1. **更新友好** - 配置变更后可以快速重新运行脚本
2. **调试简单** - 可以逐行执行和测试
3. **配置复用** - 直接使用 nanopi-r3s-rootfs 的文件结构
4. **灵活性** - 可以添加任意自定义逻辑

### 模块化设计

每个功能独立为一个模块，便于：
- 启用/禁用特定功能
- 理解配置结构
- 后续维护和扩展

## 可选的后续改进

1. **添加更多服务**：
   - WebDAV
   - 百度网盘同步
   - Transmission/qBittorrent
   - Jellyfin/Plex

2. **监控和告警**：
   - Prometheus + Grafana
   - 邮件/短信告警

3. **自动化备份**：
   - Restic/Borg 定期备份
   - 远程备份到云存储

4. **CI/CD**：
   - GitHub Actions 自动检查 Nix 配置
   - 自动部署到测试环境

## 资源

- [qnap8528 模块](https://github.com/allenmagic/qnap8528)
- [nanopi-r3s-rootfs](https://github.com/allenmagic/nanopi-r3s-rootfs)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [sops-nix](https://github.com/Mic92/sops-nix)
