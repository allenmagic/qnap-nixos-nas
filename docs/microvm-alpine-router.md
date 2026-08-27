# NixOS × Cloud Hypervisor：把路由器装进一个 512MB 的 MicroVM

> 从「手动 virt-install 装 Alpine」到「一行 enable 声明式拉起路由器」，记录一次 NAS 虚拟化架构的完整演进。

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

接下来把「镜像装配」从 NAS 的 Nix 构建中剥离，独立成 [alpine-router-image](https://github.com/allenmagic/alpine-router-image) 仓库：

```
GitHub Actions（一次点击）
  ├─ rootfs 构建（chroot 装包 + 配置烙入）
  ├─ 三件套下载（固定 3.24.1 + sha256 校验）
  ├─ 装配：initrd 注入 → rootfs 注入模块 → 8G ext4 → qcow2 compact
  ├─ release 上传（qcow2 253MB + vmlinuz + initrd + SHA256SUMS）
  └─ 自动同步 flake 模块的 tag+sha256 并提交推送
```

**配置全部烙进镜像**——nftables 规则、dnsmasq、sysctl、服务脚本、网络参数，出厂即正确。网络参数用占位符机制：`base/` 里的 `__LAN_IP__` 之类在构建时按 `network.env` 替换，改网段只动这一个文件。

同时 NAS 侧的 deploy 收缩为**纯密钥注入器**：SSH 公钥（deploy 通道与日常登录）、Tailscale authkey、Cloudflared token 经 600 权限的 env 文件注入，密钥永不进 git、不进镜像、不进 release。

## 第四版：消费端模块化 + Cloud Hypervisor

最后一步收敛：microvm 声明（镜像 fetchurl、CH 参数、状态盘、tap 挂桥）也迁入 alpine-router-image，以 **flake 模块**形式发布。NAS 侧启用整个路由器只剩：

```nix
imports = [ inputs.alpine-router-image.nixosModules.router ];
microvm.router = {
  enable = true;

  cpu = 3;                 # isolcpus 独占核：vcpu0 pin 到此核，宿主不用
  vcpus = 2;               # 1 独占 + 1 动态调度
  mem = 512;               # guest 内存上限 MB
  initialBalloonMem = 256; # virtio-balloon，128M 对齐；宿主 OOM 自动放气

  wanBridge = "br-wan";    # tap 自动挂入的宿主桥
  lanBridge = "br-lan";
};
```

后端从 QEMU 换成 **Cloud Hypervisor**——Rust 写的专用 microvm VMM：

- **更轻**：无设备模拟层，空闲内存/CPU 占用显著低于 QEMU
- **CPU 隔离**：`isolcpus` 把核 3 从宿主调度器剥离 + vCPU0 affinity 硬 pin——路由器独占一核，其余 vCPU 动态调度且不会抢占隔离核
- **动态内存**：virtio-balloon（128M 粒度），初始 balloon 256M 意味着 guest 只实际占用 256M，宿主内存紧张时自动放气归还
- **网络**：CH 没有 QEMU 的 bridge 便捷类型，用 tap + systemd-networkd——tap 出现时 networkd 自动挂桥，零手工步骤

网络数据面两者等价：都是 virtio-net + vhost-net 内核加速，包不过 VMM 用户态，2.5G 网口轻松跑满线速。

## 更新与回滚：自愈链

```
改配置 → CI 出 release（自动同步 sha256）
       → NAS: nix flake update → rebuild
       → VM 自动重启（状态盘路径含镜像内容哈希，镜像变 = 必然重启）
```

三个保护层次：

1. **无关 rebuild 零断网**：restartIfChanged 机制保证只有 VM 相关配置变化才重启它
2. **失败自愈**：镜像 sha256 在构建期校验（坏镜像进不了 store）；回滚是纯本地操作，旧 generation 指向旧镜像文件（保留不删），`nixos-rebuild switch --rollback` 一步恢复网络
3. **物理兜底**：HDMI 控制台（kmscon + 中文字体）在完全断网时本地登录修复

## 实测与验证

WSL2（KVM 嵌套虚拟化）上完成全链路实测：

- CH + bzImage 自动识别引导 ✅（affinity 语法踩坑：v53 用 `[0@[3]]` 而非 JSON 形式）
- 出厂镜像 debugfs 审计：占位符零残留、WG 规则零残留、服务脚本路径正确
- deploy 全链路：串口登录 → install.sh 执行 → 密钥注入 → tailscale 登录 / cloudflared 重启生效

## 最终架构一览

| 环节 | 位置 |
|---|---|
| rootfs 构建 + 配置烙入 + 镜像装配 | alpine-router-image CI → release |
| microvm 消费端声明（fetchurl/CH/状态盘/挂桥） | alpine-router-image 的 nixosModules.router |
| 密钥注入 | 宿主 env 文件 → alpine-router-deploy |
| NAS 侧 VM 代码量 | **零**（一个 flake input + 一个 enable） |

## 写在最后

这次演进的最大收获不是某个技术点，而是**收敛的节奏**：从「手动 VM + 覆盖式部署」到「镜像自包含 + 单一覆盖通道」，再到「单仓库闭环 + 消费端模块化」——每一步都让系统更声明式、更可重现、更少手工干预。

如果你的 NAS 也想跑一个路由器 VM，这套方案（microvm.nix + Cloud Hypervisor + Alpine virt 三件套）是资源占用和运维成本的平衡点：512MB 内存、一个独占核、一次 CI 点击完成更新，剩下的交给声明式配置。

---

**相关仓库**：[qnap-nixos-nas](https://github.com/allenmagic/qnap-nixos-nas) · [alpine-router-image](https://github.com/allenmagic/alpine-router-image) · [nanopi-r3s-rootfs](https://github.com/allenmagic/nanopi-r3s-rootfs)
