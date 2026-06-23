{
  description = "NixOS support for Radxa Cubie A5E (Allwinner A527) - WiFi, Bluetooth, board workarounds";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs_25_11.url = "github:NixOS/nixpkgs/nixos-25.11";
    disko.url = "github:nix-community/disko";
  };

  outputs = { self, nixpkgs, nixpkgs_25_11, disko, ... }: let
    pkgs = nixpkgs.legacyPackages.aarch64-linux;
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

    packages.aarch64-linux = let
      uboot = import ./modules/uboot.nix { inherit pkgs; };
    in {
      uboot-1gb = uboot.mainline-1gb;
      uboot-2gb = uboot.mainline-2gb;
      spinor-1gb = uboot.spinor-1gb;
      spinor-2gb = uboot.spinor-2gb;
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
      cubie-a5e = mkCubieA5E "vendor";
      cubie-a5e-mainline-1gb = mkCubieA5E "mainline-1gb";
      cubie-a5e-mainline-2gb = mkCubieA5E "mainline-2gb+";
    };
  };
}
