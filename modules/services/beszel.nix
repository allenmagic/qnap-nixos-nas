{ config, lib, ... }:

# ============================================================
# Beszel 服务器监控（hub + agent，仅监控本机）
#
# 架构：hub（Web 面板，PocketBase 底座）跑在 qnap；agent 采集本机
# 指标（CPU/内存/磁盘/温度 + systemd 服务状态）并经回环供 hub 拉取。
# 数据落 /var/lib/beszel-hub（sqlite 历史，systemd 自动管理属主），
# 镜像升级不影响。
#
# ── 当前状态：方案 A 第 1 步 —— 只启用 hub，agent 暂关 ──────────
#
# 为什么分两步：agent 的 KEY 是 **hub 生成的 SSH 公钥**，必须先有 hub
# 才能拿到，无法预先写入 sops。
#
# 后续步骤（拿到公钥后）：
#   1. 浏览器打开 http://192.168.10.2:8090 → 建管理员账号
#      → Add System → 复制它显示的 SSH 公钥
#   2. 写入 sops（EnvironmentFile 格式，一行）：
#        sops -k /var/lib/sops-nix/key.txt set secrets/secrets.yaml \
#          beszel-agent-key 'KEY=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI...'
#   3. 在 modules/security/sops.nix 里定义同名 secret（owner=root, mode=0400）
#   4. 把下面的 agentEnable 改成 true → 重新 rebuild
#
# ⚠️ KEY 不是随机串，是 SSH 公钥（"Public SSH key(s) to use for
#    authentication. Provided in hub."）——见
#    https://www.beszel.dev/guide/environment-variables
#    敏感的是 WebSocket 模式的 TOKEN（hub /settings/tokens），两者别混淆。
# ============================================================
let
  # 方案 A 第 1 步：先只跑 hub；拿到公钥并写入 sops 后改为 true
  agentEnable = false;
in
{
  services.beszel = {
    # ---- hub：Web 面板（8090，br-lan 放行见 network/default.nix） ----
    hub = {
      enable = true;
      host = "0.0.0.0";    # 默认 127.0.0.1；对外访问需全接口
      port = 8090;         # 未与现有服务冲突（见 network/default.nix 端口清单）
      # dataDir 默认 /var/lib/beszel-hub，模块自动 StateDirectory 创建
    };

    # ---- agent：本机采集（KEY 由 hub UI 生成后经 sops 注入） ----
    agent = {
      enable = agentEnable;
      # 密钥不进 nix store（agent.environment 会明文落 store），故用
      # environmentFile 走 /run/secrets；默认端口 45876 仅回环访问，
      # 无需 openFirewall。
      # mkIf 保证 agent 关闭时不去引用尚未定义的 sops secret，
      # 否则求值会报 attribute 'beszel-agent-key' missing。
      environmentFile = lib.mkIf agentEnable config.sops.secrets.beszel-agent-key.path;
    };
  };
}
