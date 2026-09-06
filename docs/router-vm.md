# QNAP TS-564 AIO —— 单机 NixOS 全功能 NAS

> **AIO** 两层含义：
> - **All In One** —— 存储、服务、路由、VPN 四类职责收进**一台** QNAP TS-564；
> - **Automate Integration Once** —— 把「四类异构职责拼装成一个能工作的整体」这套
>   **集成动作**本身写成代码（Nix 配置 + CI 镜像），自动化地执行**一次**即固化。
>   此后重建 / 迁移 / 换机都是**复现**（reproduce），不再是重新做一遍**集成**
>   （integrate）。

---

## 0. 基本架构

硬件是一台 4 核 N5095、8G 内存的双网口 NAS，所有功能都收在**一个 NixOS 宿主**里：

```
                              QNAP TS-564（NixOS 宿主，192.168.10.2）
┌────────────────────────────────────────────────────────────────────────────┐
│  存储层     /srv/data  Btrfs 原生 RAID1（2×3TB，checksum + 每月 scrub）        │
│             /srv/cache SSD（性能敏感/可重建）  /srv/backup HDD（冷备）          │
│  服务层     Samba · NFS · Syncthing · Navidrome · Cockpit(9090)              │
│  虚拟化     router-vm（cloud-hypervisor，gentoo 路由）                          │
│             yunshu 容器（declarative container，透明网关 VPN）                 │
└────────────────────────────────────────────────────────────────────────────┘
        │ br-wan                                    │ br-lan
        ▼                                           ▼
   上游 ISP ── eno1 ── br-wan ── router-vm eth0 (WAN DHCP/PPPoE)
                                        │ NAT · 防火墙 · DHCP · DNS
   内网设备 ── eno2 ── br-lan ── router-vm eth1 (192.168.10.1)
                                        │
             ┌──────────────────────────┼───────────────────────────┐
             ▼                          ▼                           ▼
      宿主机 192.168.10.2          yunshu 容器 192.168.10.3      内网设备
      （网关 → .1）                （VRRP 浮动网关 .254 MASTER）   （DHCP 网关 → .254）
```

四类职责各归其位，**互相隔离、单一权威源**：

| 职责 | 载体 | 权威源 |
|---|---|---|
| 存储 | 宿主 Btrfs 卷 | `filesystem.nix`（按卷标挂载） |
| 服务 | 宿主 systemd 单元 | `modules/services/*` |
| 路由（DHCP/DNS/NAT/防火墙/Tailscale） | router-vm（gentoo，无状态） | `router-image` 仓库 `base/` + `network.env` |
| VPN 策略分流（透明网关/代理） | yunshu 容器（headless） | `yunshu-nix` 仓库 |

关键：**路由和 VPN 都跑在隔离的「盒子」里**（一个 VM、一个容器），但配置和镜像
全部声明式、可复现、可回滚——这是整套 AIO 的灵魂。

---

## 1. 为什么选这个架构

不是「想用 NixOS 秀技术」，而是几个现实约束叠出来的必然。

### 1.1 资源有限，重型虚拟化跑不动

硬件只有 **N5095（4 核 4 线程）+ 8G 内存**。Proxmox VE（PVE）这类完整虚拟化平台
自带 Web 管理、集群、存储抽象，空载就要吃掉可观的 CPU 和内存，留给实际服务的余量
所剩无几。一台以「存储 + 轻服务」为主、偶尔路由的 NAS，不值得为此背负一个虚拟化
平台的常驻开销。

### 1.2 数据安全有过前车之鉴

之前用**飞牛 NAS（fnOS）**出现过**数据丢失**。对自建 NAS 来说，数据卷的可靠性、
可校验、可迁移是底线——这要求选一个底层透明、坏了能救、换机不锁死的方案，而不是
「黑盒」的成品系统。

### 1.3 功能要求杂，尤其是路由器和 VPN 代理

这台机器要同时干：文件共享（Samba/NFS）、同步（Syncthing）、媒体（Navidrome）、
Web 管理（Cockpit），**以及最关键的两块——路由器（DHCP/DNS/NAT/防火墙/Tailscale）
和 VPN 策略分流（透明网关/代理）**。成品 NAS 系统（群晖/威联通/fnOS）的路由和代理
能力要么阉割、要么封闭，无法满足「策略分流 + 透明网关 + 浮动网关高可用」这种自定义
网络需求。

### 1.4 为什么是 Nix：IaC，代码即基础设施

前三条（资源紧、怕丢数据、功能杂）把方向指向「裸 NixOS + 声明式 VM/容器」，但为什么
是 Nix，而不是 Ansible、Cloud-init、Docker Compose 这类更常见的自动化工具？答案在于：
**这套 AIO 的根基是 IaC（Infrastructure as Code，基础设施即代码）——代码就是基础设施，
基础设施就是代码。而 Nix 是把 IaC 做得最彻底的那一个。**

**IaC 的关键不是「用脚本自动化」，而是「用代码描述目标状态」。** 命令式工具（Ansible
playbook、shell 脚本）描述的是「怎么一步步把系统变成想要样子的**过程**」；真正的 IaC
描述的是「系统应该是什么样子的**状态**」。过程会漂移——同一套 Ansible 跑两遍，结果
可能因为执行顺序、幂等没写全、环境差异而不一致；状态则可以被校验——因为系统的最终
形态就是那份代码的求值结果，代码对，系统就对。

Nix 把「代码即基础设施」推到极致，体现在四处：

1. **纯函数式声明**：整个系统配置是一个 Nix 表达式的求值，没有副作用、没有执行顺序，
   相同输入 → 相同输出。改一个服务不会「顺带」改到别的东西。
2. **原子切换 + 可回滚**：`nixos-rebuild switch` 是原子操作，新 generation 完整生成后
   一次切过去；旧 generation 原样保留，`--rollback` 一步退回。系统更新从「赌博」变成
   「可撤销的操作」。
3. **flake.lock 锁定一切**：不仅锁系统配置本身，还锁所有依赖的精确版本——nixpkgs、
   router-image、yunshu-nix 的 commit + hash。「集成」那一刻的完整状态被固化成一组
   哈希，任何人在任何时间复现，拿到的都是同一套东西。
4. **一种语言覆盖四类职责**：存储（filesystem）、服务（systemd 单元）、路由 VM
   （cloud-hypervisor 参数）、VPN 容器（declarative container）、网络（bridge/firewall）
   ——全是 Nix 表达式，而不是「Nix + Ansible + Docker Compose + Terraform」各管一段、
   靠人脑拼起来的混合体。

对比之下：Ansible 命令式、有漂移；Docker Compose 只管容器；Terraform 管云资源。它们
各自解决一段，边界靠文档和记忆维持。Nix 从内核参数、硬件驱动，一路管到服务、VM、
容器、网络——这才是「代码即基础设施」的完整形态。

> 这也解释了为什么 "Automate Integration Once" 能够成立：**集成之所以能被「自动化
> 一次」，是因为集成的产物不是「一堆手工敲出来的命令」，而是一份描述目标状态的代码。
> 代码本身就是基础设施——改代码 = 改基础设施，跑一遍 = 复现基础设施。** 集成动作被
> 压缩进了代码，之后只剩复现。

> 一句话：**资源紧 → 不能上 PVE；怕丢数据 → 要底层透明；功能杂 → 要自己掌控路由
> 和代理；要「集成一次、处处复现」→ 必须 IaC。** 四条加起来，答案是「裸 NixOS 宿主 +
> 声明式 VM/容器」——而 Nix，正是把 IaC（代码即基础设施）做得最彻底的那个工具。

---

## 2. 架构选型思路与变化路径

整套架构不是一步到位，而是在「做减法 + 找对边界」的过程中逐步收敛的。

### 2.1 router-vm：从 microvm.nix 到自建 cloud-hypervisor + alpine/gentoo

路由 VM 经历了五个版本的演进，核心是**一层层剥掉不必要的抽象**：

| 版本 | 形态 | 淘汰原因 |
|---|---|---|
| 一版 | libvirt / `virt-install` 手动装 Alpine | 不可重现、配置漂移、QEMU 全套模拟太重 |
| 二版 | microvm.nix + Alpine 官方 virt 三件套 | 声明式了，但 microvm.nix 面向 NixOS-guest，与「预构建镜像」重叠极小 |
| 三版 | 镜像生产独立成 `router-image` 仓库，CI 出单文件 | 解决了「镜像怎么来」，但消费端仍绑 microvm |
| 四版 | 消费端模块化 + 后端换 Cloud Hypervisor | CH 更轻，但 microvm.nix 的空占位（空 initramfs、内核双输出、flake 双输入）越来越扎眼 |
| 五版（现状） | **剥离 microvm.nix，systemd 直管 CH + guest 完全无状态** | 删掉抽象层后复杂度不升反降 |

第五版的最终形态，几个关键决策：

- **后端选 Cloud Hypervisor（CH）而非 QEMU**：Rust 写的专用 microvm VMM，无设备
  模拟层，空闲 CPU/内存占用显著低于 QEMU；支持 `isolcpus` 独占核 + vCPU affinity
  硬 pin（路由独占一核）；virtio-balloon 动态内存。
- **内核自建、无 initramfs**：引导链全 builtin（virtio/8250 串口/网卡内建），省掉
  initramfs 和 modloop 的复杂度，CVE 响应就是 LTS bump + CI 重编。
- **guest 完全无状态**：rootfs 只读挂载（`--disk readonly=on` + `ro`），所有可写路径
  在构建期烙成指向 `/run`（tmpfs）的符号链接；重启即清空，密钥由宿主 sops-nix 解密
  后 `router-vm-deploy` 每次启动自动注入。**镜像升级不再丢状态——因为状态根本不在
  镜像里。**
- **双发行版链 alpine/gentoo**：共用 `base/` 配置体系（OpenRC + 同一套 nftables/
  dnsmasq/sysctl），消费端 `os` 选项一键切换，按需选 musl 生态的两种底子。

> 为什么绕了 microvm.nix 这一圈？因为「借一个 host 模块」比「自己写 systemd 单元」
> 看起来快，但最后发现借来的抽象里 90% 用不上。**当抽象层的重叠小于它的开销时，
> 拆掉它才是对的。** 这也是整个项目一贯的取舍哲学。

### 2.2 yunshu：抛弃 GUI，headless 化

YunShu 是亿格云的零信任/SASE 客户端，官方交付形态是带 GUI 的桌面应用（`.deb` 包）。
但在 NAS 这个无头环境里：

- **GUI 是纯负担**：X11/Wayland、依赖树、图形登录流程，全是无头机器用不到的东西；
- **真正有用的是运行时二进制**：`yunshu-daemon`（隧道 + TUN 分流）、`yunshu-updater`、
  `libtunnel.so`（隧道核心库）、`yunshu` CLI（登录/连接控制）。

于是把 `.deb` 解包、剥离 GUI，只保留运行时 payload（`dist/yunshu-headless/`），用
systemd 服务 + 一个飞书 SSO 登录状态页（darkhttpd 8080）替代图形登录流程。登录 token
持久化在容器 `/var/lib/yunshu`，重启不丢。

**代价**：headless 版缺两个桌面版会自动做的事，需要在 NixOS 侧补齐（这是本次项目踩
出来的关键）：

1. **`yunshu -s all`（连接 pa/ga）≠ 登录**——登录态持久，但 pa/ga 连接在容器重启后
   会断，需 `yunshu-connect` 服务循环检测并自动重连；
2. **fake-IP 路由**——被墙域名由 YunShu DNS 解析成 `198.18.0.0/15` 网段的 fake-IP，
   必须把该网段路由到 `tun0`，否则分流不生效。

### 2.3 yunshu 的两种接入形式：gateway vs 3proxy

同一个 headless payload，`yunshu.container.mode` 提供两种「把流量送进 YunShu 隧道」
的形式，对应两种使用场景：

| | `gateway`（透明网关，默认） | `private_proxy`（3proxy 代理） |
|---|---|---|
| 客户端 | **零配置**：默认网关/DNS 指向浮动 IP `.254` | 每台设备显式设 `192.168.10.3:7890` |
| 分流机制 | 三层转发 + fake-IP 路由（被墙域名走 tun0） | 应用层代理，3proxy 出站走隧道 |
| 高可用 | keepalived VRRP MASTER（.254 浮动） | 无浮动网关 |
| 适用 | 全家设备透明上网 | 少数设备按需翻墙 |

`gateway` 模式下，容器还承担**浮动网关**职责：内网设备 DHCP 下发的网关是
`192.168.10.254`，正常由 yunshu 容器持有（VRRP MASTER，策略分流），容器不可用时由
router-vm 的 keepalived（BACKUP）接管，降级为纯直连 NAT 保连通。这套 VRRP 参数
（vrid/auth_pass/floatIp）横跨三个仓库同步。

> 简单说：**要「全家无感」就 gateway，要「按需可控」就 3proxy**。两者共用同一套
> headless 运行时，切换只改一个 `mode` 字段。

---

## 3. 整体方案

### 3.1 存储构建

数据盘与系统盘彻底分离，**数据卷按卷标挂载、不依赖 UUID**：

| 卷 | 设备 | 文件系统 | 用途 | 可靠性 |
|---|---|---|---|---|
| `nixos` | 256G SSD | ext4 | 系统 + 配置（可重建） | 单盘，随时可重装 |
| `boot` | 256G SSD | FAT32 ESP | systemd-boot | 同上 |
| `data` | 2×3T HDD | **Btrfs 原生 RAID1** | 不可再生数据 | checksum + 每月自动 scrub |
| `cache` | 1T SSD | ext4 | 性能敏感/可重建 | 可重建 |
| `backup` | 2T HDD | ext4 | 冷备 | 单盘 |

要点：

- **Btrfs 原生 RAID1（`-m raid1 -d raid1`）不用 mdadm**：多设备成员由内核自动组装，
  数据带 checksum，配合 `services.btrfs.autoScrub` 每月检测并修复静默损坏。
- **挂载靠卷标**：`mkfs.btrfs -L data` 之后无需记录任何 UUID，`filesystem.nix` 里
  `device = "/dev/disk/by-label/data"`，换盘/换机只需重做卷标即可挂上。

### 3.2 服务构建

服务层全是标准 NixOS 模块，集中在 `modules/services/`，每个功能一个文件：

- **Samba / NFS**：文件共享，绑定 `192.168.10.0/24` 内网；
- **Syncthing**：跨设备同步（GUI 绑定内网地址）；
- **Navidrome / Feishin**：音乐流媒体；
- **Cockpit**（9090）：Web 管理入口，`nas` 用户 + 系统密码登录。

所有服务共用 `nas` 用户、跑在 `/srv/*` 路径上，tmpfiles 规则负责建目录。改服务 =
改一个模块文件 + rebuild，不动其它任何东西。

### 3.3 router-vm 构建

路由 VM 的全部实现都在 **router-image** 仓库，NAS 侧**零 VM 实现代码**，只有一行
flake input + 一个 `services.router-vm` 块：

```nix
services.router-vm = {
  enable = true;
  os = "gentoo";            # alpine | gentoo（musl + OpenRC 双链）
  cpu = 0;                  # isolcpus 独占核
  vcpus = 2;                # 1 独占 + 1 动态
  mem = 256;
  wanBridge = "br-wan";
  lanBridge = "br-lan";
  vmIp = "192.168.10.1";
};
```

**构建链**：`router-image` CI（一次点击）→ 自建内核（全 builtin，无 initramfs）→
rootfs chroot 装包 + `base/` 配置烙入（`network.env` 占位符替换）→ ext4 → qcow2 →
release 上传 + 自动同步模块内 tag+sha256。**升级只需 NAS 上 `nix flake update` +
rebuild**，VM 因 rootfs 副本路径含内容哈希而自动重启。

**密钥走另一条通道**：路由 VM 的 SSH/Tailscale/Cloudflared 密钥由宿主 sops-nix 解密，
`router-vm-deploy` 每次 VM 启动后注入 guest 的 `/run`，用完即删——**密钥永不进镜像、
不进 store、不进 git**。

### 3.4 yunshu container 构建

YunShu 跑在 **NixOS declarative container**（systemd-nspawn）里，veth 挂 `br-lan`、
静态 `192.168.10.3`。容器内 guestModule 复用 headless + dns 模块：

- `enableTun = true` + `CAP_NET_ADMIN`：提供 `/dev/net/tun` 给 YunShu 建隧道；
- **gateway 模式**：开 `ip_forward`、关 `rp_filter`/ICMP redirect、nftables 放行
  `eth0 ↔ tun0` 转发 + 直连 SNAT、keepalived VRRP MASTER 持 `.254`；
- **补 headless 缺口**：`yunshu-connect`（登录后自动 `-s all` 连 pa/ga）+ 
  `yunshu-routes`（fake-IP `198.18.0.0/15` → tun0，`ip` 用绝对路径绕 systemd PATH）；
- **DNS**：`gateway` 默认透明接管 53 端口（DNAT 到隧道 DNS `10.251.1.1`），域名级
  分流和隧道一致。

---

## 4. 这个 AIO 的好处，以及与其它 AIO 方案对比

### 4.1 好处

- **一机多职、资源克制**：4 核 8G 同时跑存储 + 服务 + 路由 VM + VPN 容器，路由独占
  一核，其余动态调度，没有虚拟化平台的常驻开销。
- **可复现、可回滚**：所有配置进 git、依赖锁 flake.lock、镜像由 CI 产出；系统更新是
  纯本地操作，`switch --rollback` 一步回滚（旧 generation/旧镜像副本都保留）。
- **故障隔离、职责单一**：路由和 VPN 都关在隔离的盒子里，折腾网络不会波及存储服务；
  路由挂了还能走 router-vm 的 keepalived BACKUP 兜底。
- **数据底线透明**：Btrfs 原生 RAID1 + 卷标挂载，数据不锁死在任何黑盒系统里，坏了能
  校验、换机能迁移。
- **密钥分层**：路由 VM 密钥走 sops-nix → deploy 注入，永不进镜像/store/git；yunshu
  登录态持久化在容器内。

### 4.2 与其它 AIO/自建方案对比

| 方案 | IaC 程度 | 优势 | 劣势 | 适合 |
|---|---|---|---|---|
| **本方案（裸 NixOS + 声明式）** | **完整**：单语言覆盖硬件→容器 | 可复现、可回滚、资源克制、底层透明 | 学习曲线陡（Nix/CH/容器都要懂） | 想完全掌控、能折腾的进阶用户 |
| Proxmox VE（PVE） | 部分：VM/LXC 可 IaC，宿主系统靠脚本 | 成熟的 VM/LXC 管理、集群、备份 | **重**：空载开销大，N5095/8G 吃紧 | 多机、要跑完整 VM 群 |
| 群晖/威联通原厂 | 弱：GUI 点点点，配置难代码化 | 开箱即用、生态全 | 路由/代理能力阉割封闭、换机锁死 | 只想要成品、不折腾 |
| fnOS（飞牛 NAS） | 弱：GUI + 少量脚本 | 国产、上手快 | 数据安全有过丢失前科、可定制性差 | 轻量尝鲜（数据要另备） |
| 裸 Docker/OMV 全家桶 | 部分：Compose 管容器，系统/路由仍手工 | 服务编排灵活 | 路由/VM 弱，配置散落、难整体复现 | 只跑容器服务 |

**一句话总结这套 AIO 的定位**：在「成品 NAS 太封闭、PVE 太重」之间，用 **Nix 这套 IaC
（代码即基础设施）作为骨架**，把「一个无状态路由 VM + 一个透明网关容器 + 一组标准服务
+ 一块校验过的 Btrfs 数据卷」串成一个**集成一次、可复现可回滚、资源克制**的单机全功能
NAS。

---

**相关仓库**：[qnap-nixos-nas](https://github.com/allenmagic/qnap-nixos-nas) ·
[router-image](https://github.com/allenmagic/router-image) ·
[yunshu-nix](https://github.com/allenmagic/yunshu-nix) ·
[nanopi-r3s-rootfs](https://github.com/allenmagic/nanopi-r3s-rootfs)
