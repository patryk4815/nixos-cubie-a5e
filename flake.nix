{
  description = "NixOS support for Radxa Cubie A5E (Allwinner A527) - WiFi, Bluetooth, board workarounds";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs_25_11.url = "github:NixOS/nixpkgs/nixos-25.11";
    disko.url = "github:nix-community/disko";
  };

  outputs = { self, nixpkgs, nixpkgs_25_11, disko, ... }: let
    pkgs = nixpkgs.legacyPackages.aarch64-linux;
    nixpkgs-unstable = builtins.getFlake "github:NixOS/nixpkgs/104240a772428cc2e20d8fd86c9ddbb886bbaff2?narHash=sha256-D740uKsMbgsfK2oaDenJLLPIZfq7W0/g4KN/Fls8eKs%3D"; # 2026-08-03
  in {
    nixosModules = {
      aic8800 = ./modules/aic8800-sdio.nix;
      cubie-a5e = ./modules/cubie-a5e.nix;

      disko = { ... }: {
        imports = [
          disko.nixosModules.default
          ./modules/disko.nix
          ({ ... }: {
            disko = {
              imageBuilder = {
                pkgs = nixpkgs_25_11.legacyPackages.aarch64-linux;
                kernelPackages = nixpkgs_25_11.legacyPackages.aarch64-linux.linuxPackages_latest;
              };
            };
          })
        ];
      };

      default = { ... }: {
        imports = [
          self.nixosModules.aic8800
          self.nixosModules.cubie-a5e
          self.nixosModules.disko
        ];
      };
    };

    packages = let
      uboot = import ./modules/uboot.nix { inherit pkgs; };
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
    in forAllSystems (system: {
      sunxi-fel = nixpkgs-unstable.legacyPackages.${system}.sunxi-tools;
    }) // {
      aarch64-linux = {
        sunxi-fel = nixpkgs-unstable.legacyPackages.aarch64-linux.sunxi-tools;
        uboot-vendor = uboot.vendor;
        uboot-1gb = uboot.mainline-1gb;
        uboot-2gb = uboot.mainline-2gb;
        spinor-vendor = uboot.spinor-vendor;
        spinor-1gb = uboot.spinor-1gb;
        spinor-2gb = uboot.spinor-2gb;
      };
    };

    nixosConfigurations = let
      mkCubieA5E = uboot: nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          self.nixosModules.default
          ({ pkgs, ... }: {
            hardware.cubie-a5e.enable = true;
            hardware.cubie-a5e.uboot = uboot;
            boot.kernelPackages = pkgs.linuxPackages_7_0;

            users.users.root.initialPassword = "nixos";
            services.openssh = {
              enable = true;
              settings.PermitRootLogin = "yes";
            };
            services.getty.autologinUser = "root";

            environment.systemPackages = with pkgs; [ wpa_supplicant htop iproute2 nettools ];

            system.stateVersion = "26.05";
          })
        ];
      };
    in {
      cubie-a5e-sd-vendor = mkCubieA5E "vendor";
      cubie-a5e-sd-mainline-1gb = mkCubieA5E "mainline-1gb";
      cubie-a5e-sd-mainline-2gb = mkCubieA5E "mainline-2gb+";
      cubie-a5e-spi = mkCubieA5E "none";
    };
  };
}
