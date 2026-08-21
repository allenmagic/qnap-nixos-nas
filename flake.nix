{
  description = "QNAP TS-564 NAS NixOS configuration with Alpine Router VM";

  inputs = {
    # 使用当前稳定分支（NixOS 没有 LTS，只有 stable/unstable）
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # QNAP ITE8528 EC kernel module
    qnap8528.url = "github:allenmagic/qnap8528";

    # Secret management
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Alpine Router configuration (your nanopi-r3s-rootfs)
    alpine-router-configs = {
      url = "github:allenmagic/nanopi-r3s-rootfs";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, qnap8528, sops-nix, alpine-router-configs, ... }@inputs: {
    nixosConfigurations.default = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        alpineRouterConfigs = alpine-router-configs;
      };
      modules = [
        # Import QNAP module
        qnap8528.nixosModules.default

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
