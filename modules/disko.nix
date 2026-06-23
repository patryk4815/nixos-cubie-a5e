{
  lib,
  config,
  pkgs,
  ...
}:
let
  uboot = import ./uboot.nix { inherit pkgs; };
in
{
  options.hardware.cubie-a5e = {
    uboot = lib.mkOption {
      type = lib.types.enum [ "vendor" "mainline-1gb" "mainline-2gb+" ];
      default = "vendor";
      description = "U-Boot variant: 'vendor' (Radxa/Allwinner), 'mainline-1gb' (1GB LPDDR4), or 'mainline-2gb+' (2GB/4GB LPDDR4x)";
    };
  };

  options.nixCommunity.disko.device = lib.mkOption {
    type = lib.types.str;
    default = "/dev/mmcblk0";
    description = "Disk device for disko partitioning";
  };

  config = {
    # Allwinner U-Boot with extlinux
    boot.loader.grub.enable = false;
    boot.loader.generic-extlinux-compatible.enable = true;
    boot.loader.generic-extlinux-compatible.configurationLimit = 4;

    # Write U-Boot to raw disk after image build
    disko.imageBuilder.extraPostVM = lib.mkMerge [
      (lib.mkIf (config.hardware.cubie-a5e.uboot == "vendor") ''
        dd if=${uboot.vendor}/boot0_sdcard.bin of="$out"/main.raw bs=512 seek=256 conv=notrunc
        dd if=${uboot.vendor}/boot_package.fex of="$out"/main.raw bs=512 seek=24576 conv=notrunc
      '')
      (lib.mkIf (config.hardware.cubie-a5e.uboot == "mainline-2gb+") ''
        dd if=${uboot.mainline-2gb}/u-boot-sunxi-with-spl.bin of="$out"/main.raw bs=1k seek=128 conv=notrunc
      '')
      (lib.mkIf (config.hardware.cubie-a5e.uboot == "mainline-1gb") ''
        dd if=${uboot.mainline-1gb}/u-boot-sunxi-with-spl.bin of="$out"/main.raw bs=1k seek=128 conv=notrunc
      '')
    ];

    disko.devices = {
      disk.main = {
        device = config.nixCommunity.disko.device;
        type = "disk";
        imageSize = "6G";
        content = {
          type = "gpt";
          partitions = {
            # First partition starts at sector 32768 (16MB) to not overlap with U-Boot
            boot = {
              size = "2G";
              type = "8300";
              start = "32768";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/boot";
              };
            };
            root = {
              name = "root";
              size = "100%";
              content = {
                type = "lvm_pv";
                vg = "root_vg";
              };
            };
          };
        };
      };
      lvm_vg = {
        root_vg = {
          type = "lvm_vg";
          lvs = {
            root = {
              size = "100%FREE";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];

                subvolumes = {
                  "/root" = {
                    mountpoint = "/";
                  };

                  "/nix" = {
                    mountOptions = [
                      "subvol=nix"
                      "noatime"
                    ];
                    mountpoint = "/nix";
                  };
                };

# files for sops-nix:
#                postMountHook = builtins.toString (
#                  pkgs.writeScript "postMountHook.sh" ''
#                    mkdir -p /mnt/etc/ssh/
#
#                    cp /tmp/ssh_host_ed25519_key /mnt/etc/ssh/ssh_host_ed25519_key
#                    cp /tmp/ssh_host_ed25519_key.pub /mnt/etc/ssh/ssh_host_ed25519_key.pub
#                    cp /tmp/ssh_host_rsa_key /mnt/etc/ssh/ssh_host_rsa_key
#                    cp /tmp/ssh_host_rsa_key.pub /mnt/etc/ssh/ssh_host_rsa_key.pub
#                  ''
#                );
              };
            };
          };
        };
      };
    };
  };
}
