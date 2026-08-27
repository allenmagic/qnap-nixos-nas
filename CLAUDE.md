# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

QNAP TS-564 NAS 的 NixOS 单机配置仓库，使用 Flakes 声明式管理。注意：仓库已从 `hosts/ts564/` 多机结构**扁平化为单设备结构**（见 commit 8111ae7）——主机配置直接放在仓库根目录，flake 只输出 `nixosConfigurations.default`。完整的从零安装流程见 `INSTALL.md`。

## 常用命令

```bash
nix flake update                                  # 更新全部 flake 依赖
nix flake check                                   # 验证配置求值

sudo nixos-rebuild switch --flake .#default       # 重建系统（flake 输出名为 default，不是 .#ts564）
sudo nixos-rebuild switch --rollback              # 回滚

alpine-router-deploy                              # 在 NAS 上执行：部署配置到 Alpine 路由 VM
alpine-router-shell                                # 在 NAS 上执行：SSH 进入 Alpine 路由 VM

sops secrets/secrets.yaml                         # 编辑加密密钥（需要 age 私钥）
```

**flake.lock 已提交并锁定依赖**（nixos-26.05）。升级依赖时运行 `nix flake update` 重新生成 lock 文件。

## 架构

### 入口与模块组织

- `flake.nix`：唯一入口。imports qnap8528 和 sops-nix 的 nixosModules，然后导入 `./configuration.nix` 和 `./modules/{system,hardware,network,virtualization,services,security,users}`。通过 `specialArgs` 传入 `inputs`（所有 flake 输入，qnap8528 模块用它读 fancontrol 配置）。
- `configuration.nix`：主机级配置（hostname、stateVersion、boot loader、QNAP 硬件开关），imports `./hardware-configuration.nix` 和 `./filesystem.nix`。
- `modules/<分组>/default.nix` 是每个分组的聚合入口，只做 imports；具体配置在分组内的各个文件里。

### 网络拓扑（关键设计）

- 双网口各绑定一个桥：`eno1 → br-wan`、`eno2 → br-lan`（systemd-networkd 管理，`modules/network/bridges.nix`）。
- **宿主机在 br-wan 上不配置 IP**——WAN（DHCP/NAT/防火墙）完全由 Alpine 路由 VM 负责。宿主机只在 br-lan 上有静态 IP `192.168.8.2/24`，网关指向 VM 的 `192.168.8.1`。
- 防火墙只在 br-lan 接口开放服务端口（`modules/network/default.nix`），端口列表对应 SSH/Samba/NFS/Syncthing/Navidrome/Cockpit。

### Alpine 路由 VM

- VM 本身**不在 NixOS 中声明**（需手动 `virt-install` 创建，见 `alpine-router/README.md`），NixOS 只负责打包和分发其配置。VM 镜像为 Alpine **3.24-stable**（virt ISO 3.24.1），virt-install 的 `--os-variant` 用 `alpinelinux3.23`（osinfo-db 尚无 3.24 条目，3.23 是最接近的）。
- 路由配置的**权威源在 alpine-router-image 仓库**（`base/` + `network.env`，CI 构建时烙进镜像，占位符由移植自 r3s 的 network.sh 按 network.env 替换）；本仓库 `alpine-router/` 目录已收缩为**纯密钥注入器**（`install.sh` + `lib/secrets.sh` + `env.example`）。`modules/virtualization/alpine-router.nix` 打包 tarball 放入 `/etc/libvirt/alpine-router-deploy.tar.gz`（无 postPatch——不再有占位符），只保留 `lanIp` 常量供 deploy 脚本 ssh。**改配置**：alpine-router-image（base/network.env）→ CI → NAS `nix flake update`（模块内 tag+sha256 与 CI 同仓库同 commit）→ rebuild → 重启 VM（disk-prep 重装状态）→ deploy 注入密钥；**改密钥**：编辑 `/etc/libvirt/alpine-router.env` → `alpine-router-deploy`。**软件包列表（package.list）只在 nanopi-r3s-rootfs 仓库维护**（alpine-router-image 是其一次性拷贝）。
- `install.sh` 在 VM 内只执行密钥注入（lib/secrets.sh）：SSH 公钥 → `/root/.ssh/authorized_keys`、Tailscale authkey、Cloudflared token；结束（含失败）即删除 env 文件。
- 密钥经 env 文件注入：NAS 上 `/etc/libvirt/alpine-router.env`（模板 `env.example`，chmod 600）由 `alpine-router-deploy` scp 到 VM，install.sh 结束（含失败）即删除；密钥不进入部署包和 nix store。
- `alpine-router-deploy` 包装脚本：ping 检查 VM 在线 → scp tarball → scp 可选 env 密钥文件 → ssh 解包执行 install.sh。VM_IP 来自模块常量。
- 更新路由配置的完整流程：修改 `alpine-router/base/` → `nixos-rebuild switch`（生成新 tarball）→ `alpine-router-deploy`。
- **MicroVM 方案**（POC，默认关闭）：消费端声明在 **alpine-router-image 仓库的 `nixosModules.router`**（本仓库通过 flake input 引用，`modules/virtualization/default.nix` imports；本地 router.nix 已删除）。模块内含镜像 fetchurl 三资产（tag+sha256 与 CI 同仓库锁定）、`alpine-router-disk` 状态盘服务（复制到 `/var/lib/alpine-router/rootfs.qcow2`，release 升级自动重装）、tap 自动挂桥 networkd、CH 声明（cpu 隔离/affinity/balloon/vsock cid 3）。启用：`microvm.router.enable = true`（参数见模块 options：cpu/mem/initialBalloonMem/wanBridge/lanBridge/三资产覆盖）。deploy 是唯一密钥注入通道。
- MicroVM 后端为 **cloud-hypervisor**（更轻量）：VM 内选项挂 `microvm.*` 下（经 `microvm.vms.<name>.config` 模块传入，**不是**直接写在 vms.<name> 下）。CPU：`cpu`（默认 0）经 isolcpus/rcu_nocbs 隔离并由 vcpu0 affinity（`affinity=[0@[N]]`，CH v53 语法）pin 独占，其余 vCPU（`vcpus` 选项，默认 2）动态调度。内存：balloon（128M 对齐粒度，初始 256M + deflateOnOOM）。网络：CH 不支持 qemu 的 bridge 接口类型，用 tap 接口 + networkd（`50-router-wan/lan`）在 tap 出现时自动挂 br-wan/br-lan。内核包装要提供 dev 输出（CH runner 取 `${kernel.dev}/vmlinux`，内容实为 bzImage 自动识别）；volumes 必须显式 `imageType = "qcow2"`（CH 默认 raw）。
- 系统 Web 管理通过 **Cockpit**（9090，`modules/services/cockpit.nix`），当前启用 `cockpit-machines` 插件（依赖 `virtualisation.libvirtd.dbus.enable`）；可按需加 podman/files/zfs 等插件。virt-manager/virt-viewer 等 GUI 工具已移除，命令行用 virsh/libguestfs。

### 硬件与密钥

- QNAP 硬件支持来自 flake input `qnap8528`；风扇配置在**求值时**直接读取外部仓库：`builtins.readFile "${inputs.qnap8528}/examples/fancontrol.conf"`（`modules/hardware/fancontrol.nix`）——修改该仓库会影响本配置。
- sops-nix：age 私钥位于 `/var/lib/sops-nix/key.txt`，`defaultSopsFile` 指向 `secrets/secrets.yaml`（见 `modules/security/sops.nix`）。
- 磁盘按 label 挂载（`filesystem.nix`）：`nixos`/`boot`（系统盘）、`/srv/data`（**Btrfs 原生 RAID1**，无 mdadm，卷标 `data`，每月自动 scrub）、`/srv/cache`、`/srv/backup`。

## ⚠️ 当前状态与坑

1. **内网网段为 `192.168.8.0/24`，且在多个文件硬编码**：`bridges.nix`（宿主机 IP/网关）、`samba.nix`（hosts allow）、`nfs.nix`（exports）、`syncthing.nix`（guiAddress）、`music.nix`（Navidrome/Feishin 绑定地址）、`alpine-router.nix` 常量（deploy 脚本 ssh 目标）、**alpine-router-image 仓库的 `network.env`**（VM 网络参数权威源，含 TS_ADVERTISE_ROUTES）。修改网段时必须全局同步这些位置，否则服务绑定错 IP 或防火墙/共享拒绝访问。
2. `hardware-configuration.nix` 被 `.gitignore` 忽略（规则 `/hardware-configuration.nix`），但当前已通过 `git add -N -f` 以 intent-to-add 状态暂存——**内容仍是占位模板**（空 kernelModules），不能用于真实安装。安装时用 `nixos-generate-config --root /mnt` 生成真实配置**覆盖**它并保持 intent-to-add 状态；`hardware-configuration.nix.example` 是占位模板。**flake 求值只能看到 git 跟踪的文件**——未暂存时 `nixos-rebuild --flake` 报 "not tracked by Git"。
3. `secrets/secrets.yaml` 尚不存在。sops 模块引用了它但 `secrets` 集合为空；在 `modules/security/sops.nix` 中取消注释 secret 定义前，须先按 `secrets/README.md` 生成 age 密钥并创建加密文件。
4. `modules/users/nas-user.nix` 的 SSH 公钥是占位注释——无任何密钥则无法 SSH 登录（密码登录已禁用）。`wheelNeedsPassword = true`。
5. 数据盘为 Btrfs 原生 RAID1（无 mdadm）：`mkfs.btrfs -m raid1 -d raid1 -L data` 创建，挂载靠卷标，多设备由内核自动组装；`services.btrfs.autoScrub` 每月自动校验修复。
6. `modules/security/sops.nix` 中 `defaultSopsFile = ../../secrets/secrets.yaml` 是相对路径——移动该文件时必须同步改路径。
7. **Cockpit/nas 密码已配置**：`nas` 用户的 hash 已填在 `modules/users/nas-user.nix` 的 `hashedPassword`（安装即用，Cockpit/sudo/SSH 密码登录共用）。**⚠️ 仓库是公开的，hash 可被离线爆破——密码必须足够强且不复用；旧 hash 会永久留在 git 历史里**。改密码：`mkpasswd -m sha-512` 重新生成替换；需要加密管理时可用 sops-nix（`secrets/README.md`）。SSH 密码登录仅对内网与 Tailscale 网段放行（`ssh.nix` 的 Match Address 192.168.8.0/24,100.64.0.0/10），其他来源仅允许密钥。
8. 配置权威源已移至 **alpine-router-image 仓库**：`base/` 的 `__XXX__` 占位符由该仓库构建时（network.sh 按 network.env）替换；本仓库已无 postPatch。R3S 遗留：`PROXY_SERVER_IP`（nftables vars 中被防火墙规则引用）、`local.d/99-hw-tweak.start`（R3S 网卡调优，VM 中无实际效果）。

## 代码风格

- 模块文件是 NixOS module（`{ config, pkgs, lib, ... }: { ... }`），不是纯函数式 Nix 表达式。
- 注释使用中文；配置内嵌 shell 脚本（install.sh、部署脚本）通过 `pkgs.writeShellScript` / `writeShellScriptBin` 生成。
- 磁盘和服务路径约定：数据 `/srv/data`（Btrfs RAID1，不可再生数据）、缓存 `/srv/cache`（SSD，性能敏感/可重建状态）、备份 `/srv/backup`；服务运行用户为 `nas`（在 `users/` 模块中定义），tmpfiles 规则负责建目录。
