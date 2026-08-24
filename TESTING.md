# VirtualBox 全新安装测试指南

在 VirtualBox 中验证 INSTALL.md 的全新安装流程（不依赖 QNAP 真实硬件）。
验证目标：`nixos-install` 成功、重启进系统、RAID 组装、服务正常。

## 与真实 QNAP 的差异（测试时须知）

| 项目 | VM 里的情况 | 处理 |
|---|---|---|
| qnap8528 / fancontrol | 无 QNAP EC 硬件，开机模块加载失败、fancontrol 服务报错 | **预期现象**，不影响安装，忽略 |
| 网络接口名 | `enp0s3`/`enp0s8`，而 bridges.nix 匹配 `eno1`/`eno2` | 只测安装可不改；想装完有网需临时改（见下） |
| 磁盘 | 虚拟盘容量随意，label 必须照做 | RAID1 在 VM 里可正常测试 |

## 0. 准备

- 下载 [NixOS minimal ISO](https://nixos.org/download/)（x86_64）
- 新建 VM：Linux 64-bit、**开启 EFI**、2 CPU、4GB 内存
- 虚拟盘：`20G`（系统）+ `4G`×2（RAID1）+ `2G`（缓存）+ `2G`（备份）
- 网络：1 块 NAT 网卡（安装阶段上网）
- 挂 ISO 启动

## 1. 进入安装环境

```bash
ip a && ping -c 3 8.8.8.8   # 自动登录 nixos 用户，NAT 下自动 DHCP
sudo -i                      # 提权为 root，后续命令无需 sudo
lsblk                        # 确认磁盘名（一般 sda/sdb/sdc/sdd/sde）
```

## 2. 磁盘分区与 RAID

```bash
# 2.1 系统盘
parted /dev/sda -- mklabel gpt
parted /dev/sda -- mkpart ESP fat32 1MiB 512MiB
parted /dev/sda -- set 1 esp on
parted /dev/sda -- mkpart primary ext4 512MiB 100%
mkfs.fat -F 32 -n boot /dev/sda1
mkfs.ext4 -L nixos /dev/sda2

# 2.2 数据盘 RAID1
mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sdb /dev/sdc
mkfs.xfs -L data /dev/md0

# 2.3 缓存/备份盘
mkfs.ext4 -L cache /dev/sdd
mkfs.ext4 -L backup /dev/sde

# 2.4 记录 ARRAY 行（下一步填 disks.nix）
mdadm --detail --scan
```

## 3. 挂载 + 克隆仓库

```bash
# 3.1 挂载并生成硬件配置
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/boot /mnt/boot
nixos-generate-config --root /mnt

# 3.2 克隆仓库
# ⚠️ 必须先把 nixos-generate-config 生成的配置移出/删除，否则目录非空 git clone 失败
cd /mnt/etc/nixos
mv hardware-configuration.nix /tmp/hardware-configuration.nix
rm configuration.nix
git clone https://github.com/allenmagic/qnap-nixos-nas.git .
mv /tmp/hardware-configuration.nix .
git add -N -f hardware-configuration.nix   # flake 只能读 git 跟踪的文件

# 3.3 必改/可选改动
# a) disks.nix：填入 2.4 的 ARRAY 行（mdadmConf）
# b) modules/users/nas-user.nix：填 SSH 公钥（可选；不填只能控制台 root 登录）
# c) 想装完有网：modules/network/bridges.nix 接口名 eno1→enp0s3、eno2→enp0s8
```

## 4. 安装（TUNA 镜像）

```bash
# 安装阶段下载由 ISO 的 nix 完成，目标系统的 nix-settings.nix 镜像配置尚未生效，
# 必须显式传 --option（ISO 是 root，substituter 会被接受）
nixos-install --flake /mnt/etc/nixos#default \
  --option substituters "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://cache.nixos.org/"
# 提示设置 root 密码 → 设置并记住
reboot   # 重启前移除 ISO / 调整启动顺序
```

> 备选镜像配置（不碰 /etc）：`mkdir -p ~/.config/nix && echo 'substituters = ...' >> ~/.config/nix/nix.conf`
> （ISO 上 `/etc/nix/nix.conf` 是指向只读 store 的符号链接，echo >> 会报 Read-only file system）

## 5. 重启验证

```bash
cat /proc/mdstat                    # RAID 应已组装（填了 ARRAY 行）
lsblk                               # 挂载正常
journalctl -b | grep qnap8528       # 无硬件报错是预期
ip a                                # 改过 bridges.nix 则有网络配置
```

## 常见问题

| 现象 | 原因与处理 |
|---|---|
| `could not find a flake.nix file` | 3.2 的 clone 因目录非空失败；或用了相对路径 `.#default` 但不在仓库目录。重做 3.2，且用绝对路径 `/mnt/etc/nixos#default` |
| `echo >> /etc/nix/nix.conf` 报 Read-only file system | ISO 上该文件是指向 store 的符号链接；用 `--option` 或 `~/.config/nix/nix.conf` |
| flake 报 not tracked by Git | 未 `git add -N -f hardware-configuration.nix` |
| 重启后 RAID 未组装 | disks.nix 的 mdadmConf 缺 ARRAY 行 |
| qnap8528 模块加载失败 | VM 无 QNAP EC 硬件，预期现象 |
