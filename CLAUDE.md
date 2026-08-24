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
- `configuration.nix`：主机级配置（hostname、stateVersion、boot loader、QNAP 硬件开关），imports `./hardware-configuration.nix` 和 `./disks.nix`。
- `modules/<分组>/default.nix` 是每个分组的聚合入口，只做 imports；具体配置在分组内的各个文件里。

### 网络拓扑（关键设计）

- 双网口各绑定一个桥：`eno1 → br-wan`、`eno2 → br-lan`（systemd-networkd 管理，`modules/network/bridges.nix`）。
- **宿主机在 br-wan 上不配置 IP**——WAN（DHCP/NAT/防火墙）完全由 Alpine 路由 VM 负责。宿主机只在 br-lan 上有静态 IP `192.168.8.2/24`，网关指向 VM 的 `192.168.8.1`。
- 防火墙只在 br-lan 接口开放服务端口（`modules/network/default.nix`），端口列表对应 SSH/Samba/NFS/Syncthing/Navidrome/Cockpit。

### Alpine 路由 VM

- VM 本身**不在 NixOS 中声明**（需手动 `virt-install` 创建，见 `alpine-router/README.md`），NixOS 只负责打包和分发其配置。VM 镜像为 Alpine **3.24-stable**（virt ISO 3.24.1），virt-install 的 `--os-variant` 用 `alpinelinux3.23`（osinfo-db 尚无 3.24 条目，3.23 是最接近的）。
- 路由配置在本仓库 `alpine-router/` 目录维护（最初从 nanopi-r3s-rootfs 导入，现已解耦），结构：`base/`（配置源）+ `install.sh`（主安装脚本）+ `lib/`（packages/network/service/secrets/check 组件）+ `scripts/network-watchdog.sh` + `package.list`（声明式包列表）+ `env.example`。构建时（`modules/virtualization/alpine-router.nix`）把这些文件打成 tarball 放入 `/etc/libvirt/alpine-router-deploy.tar.gz`，并用 postPatch 替换 `__XXX__` 占位符（base/ 配置、install.sh 网络默认值、tailscale config.json）。
- `install.sh` 在 VM 内执行：装包（package.list）→ rsync 配置到 /etc → 网络配置（lib/network.sh）→ 服务注册与启动（lib/service.sh）→ 密钥注入（lib/secrets.sh）→ 完整性检查（lib/check.sh，失败会中止）。网络接口配置不立即生效（`RESTART_NETWORK=yes` 才重启网络，或重启 VM）。
- 密钥经 env 文件注入：NAS 上 `/etc/libvirt/alpine-router.env`（模板 `env.example`，chmod 600）由 `alpine-router-deploy` scp 到 VM，install.sh 结束（含失败）即删除；密钥不进入部署包和 nix store。
- `alpine-router-deploy` 包装脚本：ping 检查 VM 在线 → scp tarball → scp 可选 env 密钥文件 → ssh 解包执行 install.sh。VM_IP 来自模块常量。
- 更新路由配置的完整流程：修改 `alpine-router/base/` → `nixos-rebuild switch`（生成新 tarball）→ `alpine-router-deploy`。
- 系统 Web 管理通过 **Cockpit**（9090，`modules/services/cockpit.nix`），当前启用 `cockpit-machines` 插件（依赖 `virtualisation.libvirtd.dbus.enable`）；可按需加 podman/files/zfs 等插件。virt-manager/virt-viewer 等 GUI 工具已移除，命令行用 virsh/libguestfs。

### 硬件与密钥

- QNAP 硬件支持来自 flake input `qnap8528`；风扇配置在**求值时**直接读取外部仓库：`builtins.readFile "${inputs.qnap8528}/examples/fancontrol.conf"`（`modules/hardware/fancontrol.nix`）——修改该仓库会影响本配置。
- sops-nix：age 私钥位于 `/var/lib/sops-nix/key.txt`，`defaultSopsFile` 指向 `secrets/secrets.yaml`（见 `modules/security/sops.nix`）。
- 磁盘按 label 挂载（`disks.nix`）：`nixos`/`boot`（系统盘）、`/srv/data`（**Btrfs 原生 RAID1**，无 mdadm，卷标 `data`，每月自动 scrub）、`/srv/cache`、`/srv/backup`。

## ⚠️ 当前状态与坑

1. **内网网段为 `192.168.8.0/24`，且在多个文件硬编码**：`bridges.nix`（宿主机 IP/网关）、`samba.nix`（hosts allow）、`nfs.nix`（exports）、`syncthing.nix`（guiAddress）、`music.nix`（Navidrome/Feishin 绑定地址）、`alpine-router.nix` 常量（install.sh 默认值、Tailscale advertise-routes）。修改网段时必须全局同步这些位置，否则服务绑定错 IP 或防火墙/共享拒绝访问。
2. `hardware-configuration.nix` 被 `.gitignore` 忽略（规则 `/hardware-configuration.nix`），但当前已通过 `git add -N -f` 以 intent-to-add 状态暂存——**内容仍是占位模板**（空 kernelModules），不能用于真实安装。安装时用 `nixos-generate-config --root /mnt` 生成真实配置**覆盖**它并保持 intent-to-add 状态；`hardware-configuration.nix.example` 是占位模板。**flake 求值只能看到 git 跟踪的文件**——未暂存时 `nixos-rebuild --flake` 报 "not tracked by Git"。
3. `secrets/secrets.yaml` 尚不存在。sops 模块引用了它但 `secrets` 集合为空；在 `modules/security/sops.nix` 中取消注释 secret 定义前，须先按 `secrets/README.md` 生成 age 密钥并创建加密文件。
4. `modules/users/nas-user.nix` 的 SSH 公钥是占位注释——无任何密钥则无法 SSH 登录（密码登录已禁用）。`wheelNeedsPassword = true`。
5. 数据盘为 Btrfs 原生 RAID1（无 mdadm）：`mkfs.btrfs -m raid1 -d raid1 -L data` 创建，挂载靠卷标，多设备由内核自动组装；`services.btrfs.autoScrub` 每月自动校验修复。
6. `modules/security/sops.nix` 中 `defaultSopsFile = ../../secrets/secrets.yaml` 是相对路径——移动该文件时必须同步改路径。
7. **Cockpit 登录需要系统密码**：cockpit 本地登录走 PAM 密码认证，而 `nas` 用户 `hashedPassword = "!"`（`modules/users/nas-user.nix`）。要用 Cockpit 必须先给 nas（或专用用户）设系统密码：`mkpasswd -m sha-512` 生成哈希后填入。SSH 仍只允许密钥登录，不受影响。
8. `alpine-router/` 中的 `__XXX__` 占位符（base/ 配置、install.sh 网络默认值、tailscale config.json）在 **Nix 构建时替换**（`modules/virtualization/alpine-router.nix` 的 postPatch），网络参数常量在同文件 `let` 块中，**修改网段时必须与 `bridges.nix` 同步**。R3S 遗留：`PROXY_SERVER_IP`（nftables vars 中被防火墙规则引用）、`local.d/99-hw-tweak.start`（R3S 网卡调优，VM 中无实际效果）。

## 代码风格

- 模块文件是 NixOS module（`{ config, pkgs, lib, ... }: { ... }`），不是纯函数式 Nix 表达式。
- 注释使用中文；配置内嵌 shell 脚本（install.sh、部署脚本）通过 `pkgs.writeShellScript` / `writeShellScriptBin` 生成。
- 磁盘和服务路径约定：数据 `/srv/data`、缓存 `/srv/cache`、备份 `/srv/backup`、应用 `/srv/app`；服务运行用户为 `nas`（在 `users/` 模块中定义），tmpfiles 规则负责建目录。
