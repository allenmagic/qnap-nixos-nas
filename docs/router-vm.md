# NixOS × Cloud Hypervisor：把路由器装进一个 512MB 的无状态 VM

> 从「手动 virt-install 装 Alpine」到「一行 enable 声明式拉起路由器」，再到「剥离 microvm.nix、guest 完全无状态」，记录一次 NAS 虚拟化架构的完整演进。

## 缘起：NAS 为什么需要一个路由器 VM

我的 QNAP TS-564（N5095 四核，8G 内存）跑着 NixOS，负责存储（Btrfs RAID1 + Samba + NFS）、媒体（Navidrome）、同步（Syncthing）等一堆服务。而路由功能——DHCP、DNS、NAT、防火墙、Tailscale——我选择放在一个独立的 Alpine Linux VM 里，理由是：

- **故障隔离**：路由挂了不影响存储服务，反过来也是
- **网络职责单一**：VM 的防火墙规则可以激进配置，不用顾忌宿主服务
- **独立重启**：折腾网络时不用重启整个 NAS

拓扑是经典的「路由器在中间」：

```
上游 ── eno1 ── br-wan ── VM eth0 (DHCP)
                            │ NAT/防火墙
内网设备 ── eno2 ── br-lan ── VM eth1 (192.168.10.1，DHCP/DNS)
                            │
                   NAS 宿主 192.168.10.2（网关指向 VM）
```

**关键约束**：宿主的网关就是 VM 自己。这意味着 VM 的网络方案必须支持「宿主 ↔ guest 二层互通」——这个约束在后面会淘汰掉一整类方案。

## 第一版：libvirt 手动方案

最初用 `virt-install` 手动创建 VM、进控制台跑 `setup-alpine`、再 scp 配置脚本部署。很快暴露出问题：

1. **不可重现**：VM 是手搓的，换机器要重来一遍
2. **配置漂移**：配置脚本和 rootfs 里烙的默认配置互相覆盖，谁是对的说不清
3. **资源浪费**：QEMU 全套设备模拟对一台常驻路由器来说太重

## 第二版：microvm.nix + Alpine 官方 virt 三件套

改用 [microvm.nix](https://github.com/astro/microvm.nix) 做声明式 VM 管理，引导链换成了 Alpine 官方为虚拟机场景裁剪的 **netboot 三件套**（固定版本 + sha256 锁定）：

| 组件 | 来源 | 作用 |
|---|---|---|
| `vmlinuz-virt` | Alpine netboot | 精简内核：virtio 内建、8250 串口内建 |
| `initramfs-virt` | Alpine netboot | 官方 initramfs（需注入 ext4 模块，后述） |
| `modloop-virt` | Alpine netboot | 与内核精确配套的模块集 |

rootfs 则是从我的 [nanopi-r3s-rootfs](https://github.com/allenmagic/nanopi-r3s-rootfs) 多发行版构建框架中提取的 Alpine 构建链：chroot 装包、烙入配置、打包 tarball。

### 两个值得记录的坑

**initrd 注入 ext4**：netboot 版 initramfs 不含 ext4 模块（它的设计是 `root=` 模式不挂 modloop）。启动时根分区挂载失败——需要在 initramfs 里注入 ext4 依赖链（crc16/mbcache/jbd2/ext4）并 `depmod` 重建模块索引。注意 `modprobe` 读的是 `modules.dep.bin` 二进制索引，手写文本 `modules.dep` 无效。

**uid 0 属主**：镜像装配时如果用普通用户解包 rootfs，tar 里的 root 属主记录会降级为当前用户 uid。后果是镜像里 `/var/empty` 属主错误，sshd 的 chroot 目录校验失败拒绝启动。解法是 fakeroot 包裹装配阶段（CI runner 是 root 则无此问题）。

## 第三版：镜像生产独立成仓库，CI 出单文件

接下来把「镜像装配」从 NAS 的 Nix 构建中剥离，独立成 [router-image](https://github.com/allenmagic/router-image) 仓库：

```
GitHub Actions（一次点击）
  ├─ 内核构建（自建，引导链全 builtin）
  ├─ rootfs 构建（chroot 装包 + 配置烙入，alpine/gentoo 双链）
  ├─ 装配：模块元数据注入 → ext4 → qcow2 compact
  ├─ release 上传（vmlinuz-router + <distro>-rootfs.qcow2 + SHA256SUMS）
  └─ 自动同步 flake 模块的 tag+sha256 并提交推送
```

**配置全部烙进镜像**——nftables 规则、dnsmasq、sysctl、服务脚本、网络参数，出厂即正确。网络参数用占位符机制：`base/` 里的 `__LAN_IP__` 之类在构建时按 `network.env` 替换，改网段只动这一个文件。

同时 NAS 侧的 deploy 收缩为**纯密钥注入器**：SSH 公钥（deploy 通道与日常登录）、Tailscale authkey、Cloudflared token 注入，密钥永不进 git、不进镜像、不进 release。

## 第四版：消费端模块化 + Cloud Hypervisor（microvm.nix 时代）

镜像声明（fetchurl、CH 参数、状态盘、tap 挂桥）迁入镜像仓库，以 **flake 模块**形式发布。NAS 侧启用整个路由器只剩：

```nix
imports = [ inputs.router-image.nixosModules.router ];
microvm.router = {
  enable = true;

  cpu = 0;                 # isolcpus 独占核：vcpu0 pin 到此核，宿主不用
  vcpus = 2;               # 1 独占 + 1 动态调度
  mem = 512;               # guest 内存上限 MB
  initialBalloonMem = 256; # virtio-balloon，128M 对齐；宿主 OOM 自动放气

  wanBridge = "br-wan";    # tap 自动挂入的宿主桥
  lanBridge = "br-lan";
};
```

后端从 QEMU 换成 **Cloud Hypervisor**——Rust 写的专用 microvm VMM：

- **更轻**：无设备模拟层，空闲内存/CPU 占用显著低于 QEMU
- **CPU 隔离**：`isolcpus` 把核 0 从宿主调度器剥离 + vCPU0 affinity 硬 pin——路由器独占一核，其余 vCPU 动态调度且不会抢占隔离核
- **动态内存**：virtio-balloon（128M 粒度），初始 balloon 256M 意味着 guest 只实际占用 256M，宿主内存紧张时自动放气归还
- **网络**：CH 没有 QEMU 的 bridge 便捷类型，用 tap + systemd-networkd——tap 出现时 networkd 自动挂桥，零手工步骤

### 为 microvm.nix 妥协的复杂度

这套方案跑通后，几个妥协点越来越扎眼：microvm.nix 面向 NixOS-guest 场景，而本仓库 guest 是预构建镜像，重叠很小——`initramfs-empty.cpio` 空占位（五个 runner 无条件传 `--initramfs`）、`guestKernel` 双输出包装、完整的 NixOS 模块求值、flake 双输入。它们全部只是为了「借」microvm 的 host 模块。

## 第五版：剥离 microvm.nix，guest 完全无状态（现状）

2026-09 重构：**不再依赖 microvm.nix**，systemd 单元直接管理 cloud-hypervisor；同时把持久化从「可写 rootfs 副本」改为「guest 完全无状态 + 宿主 sops-nix」。

```nix
imports = [ inputs.router-image.nixosModules.router ];
services.router-vm = {
  enable = true;
  os = "alpine";

  cpu = 0;                 # isolcpus 独占核：vcpu0 pin 到此核，宿主不用
  vcpus = 2;               # 1 独占 + 1 动态调度
  mem = 512;               # guest 内存上限 MB
  initialBalloonMem = 256; # virtio-balloon，128M 对齐；宿主 OOM 自动放气

  wanBridge = "br-wan";    # tap 自动挂入的宿主桥
  lanBridge = "br-lan";
  vmIp = "192.168.10.1";   # deploy 通道的 ssh 目标
};
```

### 变化一览

| 维度 | 第四版 | 第五版 |
|---|---|---|
| VM 管理 | microvm.nix host 模块 | `router-vm.service` 直接 ExecStart cloud-hypervisor（tap 创建/挂桥/balloon/优雅关机自管） |
| 内核 | Alpine virt 三件套 + 自建双变体 | 唯一自建内核（跟最新 LTS，引导链全 builtin，**无 initramfs**） |
| rootfs | 可写副本（镜像升级 = 状态清零） | **只读挂载**（`--disk readonly=on` + `ro` cmdline） |
| 状态 | 状态盘/可写 rootfs | **完全无状态**：可写路径构建期烙成符号链接 → `/run`（tmpfs），重启即清 |
| 密钥 | 手工 `alpine-router-deploy`（env 文件） | sops-nix 加密进 git，`router-vm-deploy.service` **每次 VM 启动后自动注入** |
| 优雅关机 | microvm 管 | `ExecStop = ch-remote shutdown-vmm`（api-socket，实测秒级退出） |

### 为什么可以无状态

路由器的持久化数据其实只有「密钥与登录凭据」一类纯文本：SSH 公钥、Tailscale authkey、Cloudflared token。它们由宿主 sops-nix 加密进 git、解密到 `/run/secrets`，deploy 服务在 VM 每次启动后 scp 注入 guest 的 `/run`。重启后密钥消失 → 宿主自动重新注入（PartOf 依赖，操作者无感知）。

**镜像升级不再丢状态**——因为状态根本不在镜像里。代价是 tailscale 节点身份每次重启 churn（hostname 固定，管理台可辨）——deploy 注入后自动后台 `tailscale up` 登录（authkey 经 config.json 的 `file:` 机制被读取；key 须 reusable、建议 Ephemeral 避免僵尸节点），审批在 Tailscale admin 侧处理。

### ro rootfs 的写点处理

运行期无法在 ro 根上创建符号链接，全部可写路径在**构建期烙入**：

- `/var/lib/tailscale`、`/etc/cloudflared`、`/var/log`、`/root/.ssh` … → `/run/...`
- `/etc/mtab` → `/proc/mounts`；`/etc/resolv.conf` → `/run/resolv.conf`（udhcpc 直写）
- sshd host key 由 `sshd-keys` 服务生成在 `/run/ssh/`（每次启动更换，deploy 通道用 root/root 密码 + StrictHostKeyChecking=no）

### 串口与排障

`--serial file=/run/router-vm/console.log`——网络故障时宿主侧 `router-vm-console` 查看，getty 仍在 guest 的 ttyS0 上。

## 更新与回滚：自愈链

```
改配置 → CI 出 release（自动同步 sha256）
       → NAS: nix flake update → rebuild
       → VM 自动重启（rootfs 只读副本路径含内容哈希，镜像变 = ExecStart 变 = 必然重启）
       → router-vm-deploy 自动重新注入密钥
```

三个保护层次：

1. **无关 rebuild 零断网**：systemd 只重启定义变化的单元，NAS 其它服务不受影响
2. **失败自愈**：镜像 sha256 在构建期校验（坏镜像进不了 store）；回滚是纯本地操作，旧 generation 指向旧镜像副本（保留不删），`nixos-rebuild switch --rollback` 一步恢复网络
3. **物理兜底**：HDMI 控制台（kmscon + 中文字体）在完全断网时本地登录修复

## 实测与验证

Arch 上完成全链路实测：

- CH + bzImage 自动识别引导 ✅（affinity 语法踩坑：v53 用 `[0@[3]]` 而非 JSON 形式）
- deploy 全链路：串口登录 → install.sh 执行 → 密钥注入 → cloudflared 重启生效
- 出厂镜像 debugfs 审计：占位符零残留、WG 规则零残留、服务脚本路径正确

2026-09 重构后的验证（router-image 仓库 CI + smoke-test）：

- CH 断言（与生产同参数：readonly=on + ro cmdline）对 alpine/gentoo 双发行版全绿，含「无 Read-only file system 报错」断言
- deploy 端到端：root/root 密码通道 → 注入 → **重启清空 → 自动重新注入** ✅
- `ch-remote shutdown-vmm` 实测秒级退出 ✅
- guest 内核版本串：`6.18.48-dange-router-vm`（CONFIG_LOCALVERSION 命名）

## 最终架构一览

| 环节 | 位置 |
|---|---|
| 内核 + rootfs 构建 + 装配 | router-image CI → release（两件套资产） |
| 消费端声明（fetchurl/systemd 单元/tap 挂桥/deploy） | router-image 的 `nixosModules.router` |
| 密钥管理 | 宿主 sops-nix（secrets.yaml 加密进 git）→ router-vm-deploy 自动注入 |
| NAS 侧 VM 代码量 | 一个 flake input + 一个 `services.router-vm` 块 + 三个 sops 密钥声明 |

## 写在最后

这次演进的最大收获不是某个技术点，而是**收敛的节奏**：从「手动 VM + 覆盖式部署」到「镜像自包含 + 单一覆盖通道」，再到「单仓库闭环 + 消费端模块化」，最后到「剥离抽象层 + 无状态化」——每一步都让系统更声明式、更可重现、更少手工干预。第五版的特别之处在于：删掉 microvm.nix 之后，复杂度不升反降——systemd 单元就是全部编排，没有中间抽象层可猜。

如果你的 NAS 也想跑一个路由器 VM，这套方案（cloud-hypervisor 直管 + 自建内核 + 无状态 guest）是资源占用和运维成本的平衡点：512MB 内存、一个独占核、一次 CI 点击完成更新，密钥由 sops-nix 管、重启自动恢复，剩下的交给声明式配置。

---

**相关仓库**：[qnap-nixos-nas](https://github.com/allenmagic/qnap-nixos-nas) · [router-image](https://github.com/allenmagic/router-image) · [nanopi-r3s-rootfs](https://github.com/allenmagic/nanopi-r3s-rootfs)
