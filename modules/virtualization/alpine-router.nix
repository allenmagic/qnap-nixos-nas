{ config, pkgs, lib, ... }:

let
  # VM LAN 口 IP（NAS 的网关）。网络参数权威源在
  # alpine-router-image 仓库的 network.env（CI 烙进镜像），
  # 此处仅 deploy 脚本的 ssh 目标需要；网段修改时两边同步。
  # 与 modules/network/bridges.nix 的 br-lan 配置保持一致！
  lanIp = "192.168.8.1";

  # 打包部署文件（install.sh + lib/——纯密钥注入器；
  # 配置已由 alpine-router-image CI 烙进镜像，无占位符无需 postPatch）
  alpineRouterDeployPkg = pkgs.stdenv.mkDerivation {
    name = "alpine-router-deploy";
    src = ../../alpine-router;

    installPhase = ''
      mkdir -p $out
      cp -r lib $out/
      cp install.sh $out/install.sh
      chmod +x $out/install.sh
    '';
  };

  # 打包为 tarball
  alpineRouterTarball = pkgs.runCommand "alpine-router-deploy.tar.gz" {} ''
    tar czf $out -C ${alpineRouterDeployPkg} .
  '';

in
{
  # 将部署包放到已知路径
  environment.etc."libvirt/alpine-router-deploy.tar.gz".source = alpineRouterTarball;

  # 提供便捷部署命令
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "alpine-router-deploy" ''
      #!/bin/sh
      set -e

      VM_IP="${lanIp}"
      DEPLOY_PKG="/etc/libvirt/alpine-router-deploy.tar.gz"
      ENV_FILE="/etc/libvirt/alpine-router.env"

      echo "Deploying Alpine Router secrets..."

      # 检查 VM 是否在线
      if ! ping -c 1 -W 2 "$VM_IP" >/dev/null 2>&1; then
        echo "Error: VM is offline or not reachable at $VM_IP"
        exit 1
      fi

      # 传输部署包
      echo "Uploading deployment package..."
      scp "$DEPLOY_PKG" "root@$VM_IP:/tmp/alpine-router-deploy.tar.gz"

      # 可选：传输密钥 env 文件（不存在则无密钥部署）
      if [ -f "$ENV_FILE" ]; then
        echo "Uploading env file (secrets)..."
        scp "$ENV_FILE" "root@$VM_IP:/tmp/alpine-router.env"
      else
        echo "Note: $ENV_FILE not found, deploying without secrets"
      fi

      # 执行注入脚本（结束后清理 /tmp 中的 tarball 和明文密钥 env 文件，保留退出码）
      echo "Running install.sh on VM..."
      ssh "root@$VM_IP" 'rm -rf /tmp/alpine-router-deploy && mkdir -p /tmp/alpine-router-deploy && cd /tmp/alpine-router-deploy && tar xzf /tmp/alpine-router-deploy.tar.gz && if [ -f /tmp/alpine-router.env ]; then mv /tmp/alpine-router.env ./env; fi; sh install.sh; _rc=$?; rm -f /tmp/alpine-router-deploy.tar.gz /tmp/alpine-router.env; exit $_rc'

      echo "Deployment complete!"
    '')

    (pkgs.writeShellScriptBin "alpine-router-shell" ''
      #!/bin/sh
      # 快速连接到 Alpine Router VM
      ssh root@${lanIp} "$@"
    '')
  ];
}
