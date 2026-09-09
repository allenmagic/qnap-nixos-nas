{ config, lib, ... }:

{
  nix = {
    # 启用 Flakes 和新命令
    settings = {
      experimental-features = [ "nix-command" "flakes" ];

      # 国内镜像优先（清华 TUNA binary cache），官方源兜底
      # qnap-kernel：定制内核由 qnap-kernel 仓库的 CI 构建并推送到该 Cachix 缓存，
      # 本机直接拉取，无需本地编译内核
      substituters = [
        "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
        "https://cache.nixos.org"
        "https://qnap-kernel.cachix.org"
      ];

      # 公钥必须显式信任，否则从缓存拉取时报 "lacks a signature by a trusted key"
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "qnap-kernel.cachix.org-1:HwBIYv2RlW2ZHEeuDP+0HRRKABTcjmd8DMAK9vdopL4="
      ];

      # 自动优化存储
      auto-optimise-store = true;

      # 构建配置
      max-jobs = "auto";
      cores = 0;  # 使用所有可用核心

      # 信任用户
      trusted-users = [ "root" "@wheel" ];
    };

    # 自动垃圾回收
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    # 优化设置
    optimise = {
      automatic = true;
      dates = [ "weekly" ];
    };
  };

  # 允许非自由软件（如果需要）
  nixpkgs.config.allowUnfree = true;
}
