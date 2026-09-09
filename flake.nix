{
  description = "QNAP TS-564 NAS NixOS configuration with Router VM";

  inputs = {
    # 使用当前稳定分支
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # QNAP ITE8528 EC kernel module
    qnap8528.url = "github:allenmagic/qnap8528";

    # 定制内核（由 qnap-kernel 的 CI 构建并推到 Cachix qnap-kernel 缓存）
    # ⚠️ 不要 follows nixpkgs：缓存命中要求本地求值出的 derivation 与 CI 完全一致，
    # 跟随本仓库的 nixpkgs 会导致内核用另一套 nixpkgs 构建、store 路径不同、拉不到缓存。
    qnap-kernel.url = "github:allenmagic/qnap-kernel";

    # Secret management
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # 路由 VM router-image
    router-image = {
      url = "github:allenmagic/router-image";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # YunShu 透明网关容器
    yunshu-router = {
      url = "github:allenmagic/yunshu-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs = { self, nixpkgs, qnap8528, sops-nix, router-image, qnap-kernel, ... }@inputs: {
    nixosConfigurations.default = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
      };
      modules = [
        # Import QNAP module
        qnap8528.nixosModules.default

        # 定制内核：只替换 boot.kernelPackages。qnap8528 由上面那个模块自带的
        # overlay 挂到新内核上，所以这里用 nixosModules.kernel 而不是 .default
        # （后者会再挂一次 qnap8528，重复）。
        qnap-kernel.nixosModules.kernel

        # Import sops-nix
        sops-nix.nixosModules.sops

        # Import main configuration
        ./configuration.nix

        # Import all module groups
        ./modules/system
        ./modules/hardware
        ./modules/network
        ./modules/virtualization
        ./modules/services
        ./modules/security
        ./modules/users
      ];
    };
  };
}
