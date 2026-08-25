{
  description = "QNAP TS-564 NAS NixOS configuration with Alpine Router VM";

  inputs = {
    # 使用当前稳定分支
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # QNAP ITE8528 EC kernel module
    qnap8528.url = "github:allenmagic/qnap8528";

    # Secret management
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # MicroVM（Alpine 路由 VM 的替代方案，POC，见 microvm/router.nix）
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs = { self, nixpkgs, qnap8528, sops-nix, microvm, ... }@inputs: {
    nixosConfigurations.default = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
      };
      modules = [
        # Import QNAP module
        qnap8528.nixosModules.default

        # Import sops-nix
        sops-nix.nixosModules.sops

        # Import microvm host 模块（定义 microvm.vms；客户机模块 microvm.nixosModules.microvm 用不到）
        microvm.nixosModules.host

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
