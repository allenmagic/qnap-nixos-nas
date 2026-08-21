# Secrets Directory

本目录用于存储加密的敏感信息（使用 sops-nix）。

## 初始化步骤

1. **生成 age 密钥**（在目标系统上执行）：

```bash
sudo mkdir -p /var/lib/sops-nix
sudo age-keygen -o /var/lib/sops-nix/key.txt
sudo chmod 600 /var/lib/sops-nix/key.txt
```

2. **获取公钥**：

```bash
sudo cat /var/lib/sops-nix/key.txt | grep "public key:"
```

3. **创建 .sops.yaml 配置**（在仓库根目录）：

```yaml
keys:
  - &admin_ts564 age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
creation_rules:
  - path_regex: secrets/secrets.yaml$
    key_groups:
      - age:
          - *admin_ts564
```

4. **创建加密的 secrets.yaml**：

```bash
# 创建明文模板
cat > secrets/secrets.yaml <<EOF
# Samba 密码
samba-password: your-password-here

# Syncthing GUI 密码
syncthing-password: your-password-here

# Tailscale 认证密钥
tailscale-authkey: tskey-auth-xxxxx
EOF

# 使用 sops 加密
sops -e -i secrets/secrets.yaml
```

5. **验证加密**：

```bash
# 查看加密后的文件
cat secrets/secrets.yaml

# 解密查看（需要对应的私钥）
sops secrets/secrets.yaml
```

## 使用密钥

在 NixOS 配置中通过 `config.sops.secrets.<name>` 引用：

```nix
# 示例：在服务中使用密钥
systemd.services.my-service = {
  serviceConfig = {
    EnvironmentFile = config.sops.secrets.my-secret.path;
  };
};
```

## 安全注意事项

- ❌ **永远不要**提交未加密的密钥文件到 Git
- ✅ 只提交 sops 加密后的 `.yaml` 文件
- ✅ 将 age 私钥保存在安全的地方（不在 Git 中）
- ✅ 定期轮换密钥
