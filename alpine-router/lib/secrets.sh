#!/bin/sh
#
# lib/secrets.sh —— 密钥注入（Tailscale / Cloudflared）
#   被 install.sh source 调用
#   定义 inject_secrets() 和 tailscale_up()
#
#   密钥来自环境变量（由 env 文件加载，见 env.example），
#   绝不写入部署包或日志。
#

inject_secrets() {
    echo "[secrets] === 密钥注入 ==="

    # Tailscale: authkey 写入 /etc/tailscale/authkey（config.json 引用）
    if [ -n "${TAILSCALE_AUTH_KEY:-}" ]; then
        mkdir -p /etc/tailscale
        printf '%s' "${TAILSCALE_AUTH_KEY}" > /etc/tailscale/authkey
        chmod 600 /etc/tailscale/authkey
        echo "  → Tailscale authkey 已注入"
    else
        echo "  → 未提供 TAILSCALE_AUTH_KEY，跳过"
    fi

    # Cloudflared: token 写入 /etc/cloudflared/config.yml
    if [ -n "${CLOUDFLARED_TOKEN:-}" ]; then
        mkdir -p /etc/cloudflared
        printf 'token: %s\n' "${CLOUDFLARED_TOKEN}" > /etc/cloudflared/config.yml
        chmod 600 /etc/cloudflared/config.yml
        echo "  → Cloudflared token 已注入"
    else
        echo "  → 未提供 CLOUDFLARED_TOKEN，跳过"
    fi
}

tailscale_up() {
    if [ -f /etc/tailscale/authkey ]; then
        echo "[secrets] Tailscale 登录（authkey）..."
        tailscale up
    else
        echo "[secrets] 未提供 authkey，跳过 Tailscale 登录（可稍后手动 tailscale up）"
    fi
}
