{ config, lib, ... }:

# ============================================================
# ⚠️ 待命状态（未启用）：本文件未在任何地方 import。启用时需一并：
#   1. services/default.nix 加 `./beszel.nix`
#   2. network/default.nix 放行 8090（br-lan + tailscale0 + ts0）
#   3. sops.nix 定义 beszel-agent-key secret（KEY=<随机串>，EnvironmentFile 格式）
#   4. secrets.yaml 加密该 entry 后 nixos-rebuild switch
#
# Beszel 服务器监控（hub + agent，仅监控本机）
#
# 架构：hub（Web 面板，PocketBase 底座）跑在 qnap；agent 采集本机
# 指标（CPU/内存/磁盘/温度 + systemd 服务状态）并经回环供 hub 拉取。
# 数据落 /var/lib/beszel-hub（sqlite 历史，systemd DynamicUser 自动
# 管理属主），镜像升级不影响。
#
# key 认证：agent 的 KEY 两端一致即可——部署前先自生成强随机串
# （openssl rand -hex 24）写入 sops（见 modules/security/sops.nix 的
# beszel-agent-key，内容为 EnvironmentFile 格式 `KEY=<随机串>`），
# rebuild 后再在 hub UI「添加系统」填 http://127.0.0.1:45876 与同一
# KEY 完成配对。
# ============================================================
{
  services.beszel = {
    # ---- hub：Web 面板（8090，LAN/Tailscale 放行见 network/default.nix） ----
    hub = {
      enable = true;
      host = "0.0.0.0";    # 默认 127.0.0.1；对外访问需全接口
      port = 8090;         # 未与现有服务冲突（见 network/default.nix 端口清单）
      # dataDir 默认 /var/lib/beszel-hub，模块自动 StateDirectory 创建
    };

    # ---- agent：本机采集（KEY 由 hub 侧生成，经 sops 环境文件注入） ----
    agent = {
      enable = true;
      # 密钥不进 nix store（agent.environment 会明文落 store，故用
      # environmentFile 走 /run/secrets）；默认端口 45876 仅回环访问，
      # 无需 openFirewall
      environmentFile = config.sops.secrets.beszel-agent-key.path;
    };
  };
}
