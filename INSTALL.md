# 从零安装指南

从一台全新的 QNAP TS-564 裸机开始，到运行着完整 NAS 服务 + Alpine 路由 VM 的 NixOS 系统。

## 0. 准备清单

**硬件**

- QNAP TS-564（含全部 5 块硬盘）
- U 盘（≥ 4GB，制作启动盘）
- 笔记本一台（后续通过 SSH 操作）
- 网线 2 根
- 显示器 + USB 键盘（可选，备用控制台）

**软件（提前下载）**

- [NixOS minimal ISO](https://nixos.org/download/)（x86_64）
- [Alpine virt ISO 3.24.1](https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/x86_64/alpine-virt-3.24.1-x86_64.iso)（拷到 NAS 的 `/srv/data` 或临时目录备用）

**信息准备**

- 你的 SSH 公钥（写入 `modules/users/nas-user.nix`）
- 规划好的密码：root 密码（仅控制台）、nas 系统密码（Cockpit 用）、Samba 密码

**网络规划**

```
上行（现有路由器 LAN 口）
  │
  │ eno1（QNAP 网口1，无宿主机 IP）
  ▼
br-wan ── Alpine VM eth0 (DHCP)
              │ NAT/防火墙
           Alpine VM eth1: 192.168.8.1
  │
br-lan（eno2，QNAP 网口2）
  ├── NAS 宿主机 192.168.8.2
  └── 内网设备 192.168.8.100-200（VM 提供 DHCP）
```

## 1. 制作启动盘并进入安装环境

```bash
# 在笔记本上制作启动盘（假设 U 盘为 /dev/sdb，请确认设备名！）
sudo dd if=nixos-minimal-xxx-x86_64.iso of=/dev/sdb bs=4M status=progress && sync
```

1. 插入**全部 5 块硬盘**和 U 盘，QNAP 开机进 BIOS/引导菜单，从 U 盘启动
2. **网线：eno1 接到现有路由器 LAN 口**（安装阶段需要 DHCP 上网下载包）
3. 进入 ISO 后确认网络：

```bash
ip a          # 确认有接口拿到了 DHCP 地址
ping -c 3 8.8.8.8
```

> 备注：ISO 环境下网口都是自动 DHCP 的，装完系统后才会按配置变成 br-wan/br-lan。

## 2. 磁盘分区与 RAID 创建

先用 `lsblk` 确认磁盘名（本文假设：`/dev/sda`=256GB 系统盘、`/dev/sdb` `/dev/sdc`=3TB×2、`/dev/sdd`=1TB 缓存、`/dev/sde`=2TB 备份）。

### 2.1 系统盘分区（GPT + EFI + root）

```bash
parted /dev/sda -- mklabel gpt
parted /dev/sda -- mkpart ESP fat32 1MiB 512MiB
parted /dev/sda -- set 1 esp on
parted /dev/sda -- mkpart primary ext4 512MiB 100%

mkfs.fat -F 32 -n boot /dev/sda1
mkfs.ext4 -L nixos /dev/sda2
```

### 2.2 数据盘 RAID1

```bash
# 用 by-id 更稳妥（ls /dev/disk/by-id/ 确认）
mdadm --create /dev/md0 --level=1 --raid-devices=2 \
  /dev/disk/by-id/ata-WDC_WD30EFRX-xxx \
  /dev/disk/by-id/ata-WDC_WD30EFRX-yyy

mkfs.xfs -L data /dev/md0
```

### 2.3 缓存盘与备份盘

```bash
mkfs.ext4 -L cache /dev/sdd
mkfs.ext4 -L backup /dev/sde
```

### 2.4 记录 RAID 配置（关键！）

```bash
mdadm --detail --scan
# 输出形如：
# ARRAY /dev/md0 level=raid1 num-devices=2 metadata=1.2 UUID=xxxxxxxx:xxxxxxxx:...
```

把 `ARRAY` 这一行记下来，第 3 步要填入 `disks.nix`，否则重启后 RAID 不会自动组装。

## 3. 安装 NixOS

### 3.1 挂载并生成硬件配置

```bash
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/boot /mnt/boot

nixos-generate-config --root /mnt
```

### 3.2 克隆本仓库并放置硬件配置

```bash
cd /mnt/etc/nixos
git clone https://github.com/allenmagic/qnap-nixos-nas.git .
mv hardware-configuration.nix .

# 关键：flake 只能读取 git 跟踪的文件
git add -N -f hardware-configuration.nix
```

### 3.3 必改的两处配置

**`disks.nix`**：填入第 2.4 步记录的 ARRAY 行：

```nix
mdadmConf = ''
  ARRAY /dev/md0 level=raid1 num-devices=2 metadata=1.2 UUID=xxxxxxxx:xxxxxxxx:...
  MAILADDR root
'';
```

**`modules/users/nas-user.nix`**：填入你的 SSH 公钥：

```nix
openssh.authorizedKeys.keys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... you@laptop"
];
```

### 3.4 安装

```bash
nixos-install --flake .#default
# 安装器会提示设置 root 密码 —— 设置并记住（仅控制台登录用，SSH 已禁 root 密码登录）

reboot
# 拔掉 U 盘
```

## 4. 首次启动与基础配置

> ⚠️ **此时 br-lan 上没有 DHCP 和网关**（Alpine 路由 VM 还没创建）。NAS 自身也没有外网（网关指向还不存在的 192.168.8.1）。

**登录方式（二选一）**：

- **方案 A（推荐）**：笔记本网线接 **eno2**，手动设置静态 IP `192.168.8.100/24`，然后：

  ```bash
  ssh nas@192.168.8.2    # 用第 3.3 步配置的密钥
  ```

- **方案 B**：HDMI 接显示器 + USB 键盘，控制台用 root 登录（第 3.4 步设的密码）

**登录后依次执行**：

```bash
# 1. 生成 sops age 密钥（记录输出的 public key，将来加密 secrets.yaml 用）
sudo mkdir -p /var/lib/sops-nix
sudo age-keygen -o /var/lib/sops-nix/key.txt
sudo chmod 600 /var/lib/sops-nix/key.txt
sudo cat /var/lib/sops-nix/key.txt | grep "public key:"

# 2. 设置 Samba 密码（与系统密码相互独立）
sudo smbpasswd -a nas

# 3. 设置 nas 系统密码（Cockpit Web 登录需要；SSH 仍只用密钥）
#    无外网时在笔记本上生成哈希：openssl passwd -6
#    把输出的 $6$... 填入 modules/users/nas-user.nix 的 hashedPassword，然后：
sudo nixos-rebuild switch --flake .#default

# 4. 硬件检查
lsmod | grep qnap8528
sensors
cat /proc/mdstat            # RAID 应已自动组装
```

## 5. 创建 Alpine 路由 VM

### 5.1 创建虚拟磁盘和 VM

```bash
# 下载 Alpine virt ISO（若还没拷到 NAS）
wget https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/x86_64/alpine-virt-3.24.1-x86_64.iso

sudo qemu-img create -f qcow2 /var/lib/libvirt/images/alpine-router.qcow2 8G

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

### 5.2 在 VM 内完成 Alpine 基础安装

```bash
sudo virsh console alpine-router   # 进入串口控制台（退出：Ctrl+]）
# 登录 root（初始无密码），执行：
setup-alpine
```

`setup-alpine` 交互选项：

| 项目 | 选择 |
|---|---|
| Keyboard layout | `us` `us` |
| Hostname | `alpine-router` |
| 网口 eth0（WAN） | `dhcp` |
| 网口 eth1（LAN） | `static` → 地址 `192.168.8.1/24` |
| Root password | **设置密码**（部署脚本 SSH 用） |
| Timezone | `Asia/Shanghai` |
| Proxy | 留空 |
| NTP | `chrony` |
| APK mirror | 任选（建议国内镜像） |
| SSH | `openssh` |
| Disk | `sda`，模式 `sys`（安装到磁盘） |

安装完成后 `reboot`，VM 重启后验证：

```bash
# 从宿主机
ping -c 3 192.168.8.1
ssh root@192.168.8.1    # 用 setup-alpine 设的密码
```

## 6. 部署路由配置

```bash
# （可选）配置部署密钥：Tailscale / Cloudflared
sudo cp /etc/nixos/alpine-router/env.example /etc/libvirt/alpine-router.env
sudo chmod 600 /etc/libvirt/alpine-router.env
# 编辑填入 TAILSCALE_AUTH_KEY / CLOUDFLARED_TOKEN（不需要则跳过此步）

# 在宿主机上执行（会提示输入 VM 的 root 密码）
alpine-router-deploy

# ⚠️ 首次部署后重启 VM，使网络接口配置完全生效
sudo virsh reboot alpine-router
# 或 alpine-router-shell 'reboot'
```

### 验证

**VM 内部**（`alpine-router-shell` 或 `virsh console`）：

```bash
rc-status                  # dnsmasq/chronyd/sshd/nftables 应已启动
ip -brief addr             # eth0=DHCP(WAN)、eth1=192.168.8.1
nft list ruleset | head    # 规则应包含 eth0/eth1 和 192.168.8.0/24
```

**客户端验证**（笔记本从静态 IP 改回 DHCP，仍接 eno2）：

```bash
ip a                       # 应拿到 192.168.8.100-200 的地址，网关 192.168.8.1，DNS 192.168.8.1
ping -c 3 8.8.8.8          # 外网连通（经 VM NAT）
nslookup baidu.com 192.168.8.1   # DNS 解析正常
ping -c 3 192.168.8.2      # 内网到 NAS 连通
```

> 此时 NAS 宿主机也通过 VM 网关获得了外网访问。

## 7. Cockpit 与收尾

1. 浏览器访问 **http://192.168.8.2:9090**，用 `nas` + 第 4 步设置的系统密码登录
2. 在 Cockpit「虚拟机」中确认 alpine-router 存在且运行
3. 备份 VM 定义（建议）：

```bash
sudo virsh dumpxml alpine-router > /srv/data/alpine-router.xml
```

4. （可选）Tailscale：在 VM 上执行 `tailscale up` 或部署时传 `TAILSCALE_AUTHKEY`

## 8. 验收清单

- [ ] 重启 NAS 后 RAID1（`/dev/md0`）自动组装
- [ ] br-lan 客户端自动获取 DHCP 地址，外网与 DNS 正常
- [ ] Samba 共享可挂载（`\\192.168.8.2\data`，用户名 nas）
- [ ] NFS、Syncthing(8384)、Navidrome(4533) 端口可达
- [ ] Cockpit 登录正常，虚拟机管理可用
- [ ] 宿主 `sensors` 有风扇/温度读数，qnap8528 模块已加载

## 附录 A：默认地址与端口

| 项目 | 值 |
|---|---|
| NAS 宿主机 | 192.168.8.2（br-lan） |
| Alpine VM LAN | 192.168.8.1（网关/DNS） |
| DHCP 池 | 192.168.8.100 - 192.168.8.200 |
| SSH | 22（仅密钥登录） |
| Cockpit | 9090（br-lan） |
| Samba | 139/445 |
| NFS | 2049 |
| Syncthing | 8384（UI）/ 22000（同步） |
| Navidrome | 4533 |

## 附录 B：故障排查

| 现象 | 处理 |
|---|---|
| 重启后 RAID 未组装 | `sudo mdadm --assemble --scan`，确认 disks.nix 的 mdadmConf ARRAY 行 |
| flake 报 not tracked by Git | `git add -N -f hardware-configuration.nix` |
| VM 无法启动 | `sudo virsh list --all`、`sudo virsh console alpine-router` |
| DHCP 客户端拿不到地址 | VM 内检查 `rc-service dnsmasq status`、`cat /etc/dnsmasq.d/10-dhcp-eth1.conf` |
| 外网不通但 VM 正常 | VM 内 `nft list ruleset` 检查 NAT 规则、`ip route` 检查默认路由 |
| Cockpit 登录失败 | 确认 nas 系统密码已设置并 `nixos-rebuild switch` 过 |
| qnap8528 未加载 | `sudo modprobe qnap8528`，`dmesg \| grep qnap8528` |
