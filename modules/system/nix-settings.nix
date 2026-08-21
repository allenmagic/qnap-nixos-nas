{ config, lib, ... }:

{
  nix = {
    # 启用 Flakes 和新命令
    settings = {
      experimental-features = [ "nix-command" "flakes" ];

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
