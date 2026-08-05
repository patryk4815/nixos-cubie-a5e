# NixOS support for Radxa Cubie A5E (Allwinner A527)

NixOS modules for the Radxa Cubie A5E board:

- **AIC8800 SDIO WiFi/Bluetooth** driver + firmware (out-of-tree, patched for kernel 7.0)
- **Bluetooth HCI** over UART1 with automatic `hciattach`
- **Device Tree overlay** enabling mmc1 (SDIO) for WiFi and UART1 for Bluetooth
- **Disko** SD card image with U-Boot, GPT, btrfs + LVM
- **Watchdog reboot workaround** for WIP TF-A without PSCI SYSTEM_RESET
- **Systemd hardware watchdog** configuration

## Quick start (pre-built image)

Download an SD card image from [Releases](https://github.com/patryk4815/nixos-cubie-a5e/releases):

| File | U-Boot |
|------|--------|
| `cubie-a5e-mainline-1gb.raw.zst` | Mainline, **1GB** model |
| `cubie-a5e-mainline-2gb.raw.zst` | Mainline, **2GB/4GB** models |
| `cubie-a5e-vendor.raw.zst` | Radxa vendor U-Boot |
| `cubie-a5e-spi.raw.zst` | No U-Boot on disk - for [booting from SPI NOR](#boot-from-spi-nor--nvme--usb) |

Flash to SD card:

```bash
zstdcat cubie-a5e-mainline-1gb.raw.zst | sudo dd of=/dev/sdX bs=4M status=progress
sync
```

> **Warning:** the 1GB and 2GB/4GB models use different DRAM chips with incompatible timings.
> Flashing the wrong mainline variant will not boot.

Default login: `root` / `nixos`

Connect to WiFi:

```bash
wpa_supplicant -B -i wlan0 -c <(wpa_passphrase "SSID" "password")
```

The image is only 6 GB. After first boot, resize the partition to use the full SD card:

```bash
parted /dev/mmcblk0
(parted) p
(parted) resizepart 2 100%
(parted) quit
reboot
```

After reboot, extend LVM and btrfs:

```bash
pvresize /dev/mmcblk0p2
lvextend -l +100%FREE /dev/root_vg/root
btrfs filesystem resize max /
```

## Usage

Add to your `flake.nix` inputs:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    cubie-a5e.url = "github:patryk4815/cubie-a5e";
  };

  outputs = { nixpkgs, cubie-a5e, ... }: {
    nixosConfigurations.my-cubie = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        cubie-a5e.nixosModules.default
        {
          hardware.cubie-a5e.enable = true;
          # hardware.cubie-a5e.watchdog-reboot = false;  # disable if your TF-A supports PSCI reboot
        }
      ];
    };
  };
}
```

Build SD card image (pre-configured example with root/nixos login):

```bash
# Vendor U-Boot (default)
nix build '.#nixosConfigurations.cubie-a5e-sd-vendor.config.system.build.diskoImagesScript' -L

# Mainline U-Boot - 1GB model (LPDDR4)
nix build '.#nixosConfigurations.cubie-a5e-sd-mainline-1gb.config.system.build.diskoImagesScript' -L

# Mainline U-Boot - 2GB/4GB model (LPDDR4x)
nix build '.#nixosConfigurations.cubie-a5e-sd-mainline-2gb.config.system.build.diskoImagesScript' -L
```

Then run the script and flash:

```bash
./result
sudo dd if=main.raw of=/dev/sdX bs=4M status=progress
```

### Individual modules

```nix
# WiFi/Bluetooth only (without disko or board workarounds)
cubie-a5e.nixosModules.aic8800
{
  hardware.aic8800.enable = true;
}

# Board workarounds only (watchdog reboot, systemd watchdog)
cubie-a5e.nixosModules.cubie-a5e
{
  hardware.cubie-a5e.enable = true;
}

# Disko only (disk layout + U-Boot)
cubie-a5e.nixosModules.disko
```

## Disk layout

Booting from **SD card** (`/dev/mmcblk0`), **USB** or **NVMe** is supported. The image uses
GPT partitioning.

When U-Boot lives on the disk itself (`hardware.cubie-a5e.uboot` other than `"none"`), the
first 16 MB are reserved for it:

| Offset | Content |
|--------|---------|
| 128 KB (sector 256) | U-Boot boot0 (SPL) |
| 12 MB (sector 24576) | U-Boot boot_package (U-Boot + ATF) |
| 16 MB (sector 32768) | First GPT partition |

With `uboot = "none"` (the `cubie-a5e-spi` image, U-Boot in SPI NOR) no gap is reserved and
partitioning starts at the front of the disk.

Partitions:

- `/boot` - 2 GB ext4 (extlinux boot)
- `root` - remaining space, LVM physical volume

LVM volume group `root_vg` with single logical volume `root` formatted as **btrfs** with subvolumes:

- `/root` -> mounted at `/`
- `/nix` -> mounted at `/nix` (noatime)

## U-Boot

Four variants available via `hardware.cubie-a5e.uboot`:

| Variant | Description |
|---------|-------------|
| `"vendor"` (default) | Radxa vendor U-Boot (`u-boot-aw2501` package) |
| `"mainline-1gb"` | Mainline U-Boot for **1GB** model (LPDDR4, 1.1V VDDQ) + SPI NOR + PCIe/NVMe |
| `"mainline-2gb+"` | Mainline U-Boot for **2GB/4GB** models (LPDDR4x, 0.6V VDDQ) + SPI NOR + PCIe/NVMe |
| `"none"` | No U-Boot on disk — use when U-Boot is flashed to SPI NOR |

Mainline U-Boot uses TF-A from [jernejsk/arm-trusted-firmware](https://github.com/jernejsk/arm-trusted-firmware) (branch `a523-v4`).
The 1GB variant applies [DRAM timing patch](https://gist.github.com/apritzel/01b5afcae189cf3c34c4256dafa3f60d) from Andre Przywara (not yet upstream).
PCIe/NVMe support uses patches from [Armbian](https://github.com/armbian/build) (DesignWare PCIe controller + Innosilicon combo PHY).

> **Warning:** 1GB and 2GB/4GB models use different DRAM chips with incompatible timings. Using the wrong variant will fail to boot.

## SPI NOR flashing

U-Boot can be flashed to SPI NOR via USB FEL mode. This flake provides `sunxi-fel` for all platforms (Linux, macOS):

```bash
nix run .#sunxi-fel -- ver
# or install into profile:
nix profile install .#sunxi-fel
```

Download the SPI NOR and U-Boot images from [Releases](https://github.com/patryk4815/nixos-cubie-a5e/releases):

```bash
# 1GB model
wget https://github.com/patryk4815/nixos-cubie-a5e/releases/latest/download/spinor-1gb.img.zst
wget https://github.com/patryk4815/nixos-cubie-a5e/releases/latest/download/uboot-1gb.bin.zst
zstd -d spinor-1gb.img.zst && zstd -d uboot-1gb.bin.zst

# 2GB/4GB model: use spinor-2gb.img.zst + uboot-2gb.bin.zst
```

Or build from source:

```bash
nix build .#spinor-1gb   # or .#spinor-2gb, .#spinor-vendor
nix build .#uboot-1gb    # just the U-Boot binary
```

Enter FEL mode by powering the board via USB-C without an SD card. Verify with:

```bash
nix run .#sunxi-fel -- ver
# AWUSBFEX soc=00001890(A523) ...
```

Load U-Boot into RAM, write the SPI image to DRAM, and start U-Boot:

```bash
nix run .#sunxi-fel -- spl uboot-1gb.bin \
  write 0x50000000 spinor-1gb.img \
  exe 0x4a000000
```

Then on UART (115200 baud), flash SPI NOR:

```
sf probe
sf update 0x50000000 0 0x1000000
reset
```

After reset the board boots from SPI NOR (`Trying to boot from sunxi SPI`).

> **Note:** `sunxi-fel spiflash-write` is not yet supported for A523. The workaround above loads U-Boot via FEL into RAM and uses U-Boot's `sf` commands to flash.

### Reflashing SPI NOR from a running system

`hardware.cubie-a5e.spi-nor` (enabled by default) adds a DT overlay that enables SPI0 and
exposes the flash chip as `/dev/mtd0`, so it can be rewritten without FEL mode:

```bash
cat /proc/mtd   # should list mtd0, 16 MiB

wget https://github.com/patryk4815/nixos-cubie-a5e/releases/latest/download/spinor-1gb.img.zst
zstd -d spinor-1gb.img.zst

flashcp -v spinor-1gb.img /dev/mtd0   # erases, writes and verifies
reboot
```

> **Warning:** if the board currently boots from SPI NOR, an interrupted write leaves it
> unbootable - recovery then requires FEL mode. Booting from SD/NVMe while reflashing is safer.

## Hardware support status

| Feature | Status | Notes |
|---------|--------|-------|
| WiFi 6 (AIC8800D80 SDIO) | ✅ Working | 2.4 GHz only, out-of-tree driver |
| Bluetooth 5.4 (AIC8800D80 UART) | ✅ Working | HCI over UART1, out-of-tree driver, hciattach service |
| Ethernet (RJ45 x2) | ✅ Working | Both GbE ports |
| SD card | ✅ Working | Boot + rootfs |
| CPU thermal sensor (THS0/THS1) | ✅ Working | Requires backported patches (see below), not yet in mainline |
| USB 2.0 | ✅ Working | |
| USB 3.0 | ❌ Not working | Missing DWC3 (xHCI) DT nodes in mainline, combo PHY shared with PCIe |
| M.2 slot (PCIe) | ✅ Working | PCIe Gen2 x1 via combo PHY (default), requires kernel patches (see below) |
| HDMI | ❌ Not working | Requires display engine drivers not yet in mainline |
| MIPI DSI | ❌ Not working | Missing mainline support/drivers |
| MIPI CSI | ❌ Not working | Missing mainline support/drivers |
| GPU (Mali G57 MC1) | ❌ Not working | Panfrost support WIP, no display output in mainline yet |
| Video HW decode/encode | ❌ Not working | Cedrus driver does not support sun55i/A527 yet |
| NPU | ➖ N/A | Only available on T527 (industrial variant), A527 does not have NPU |
| GPIO | 🔘 Not tested | Likely works |
| eMMC | 🔘 Not tested | Likely works |


## Boot from SPI NOR + NVMe / USB

Flash U-Boot to SPI NOR first (see [SPI NOR flashing](#spi-nor-flashing)), then write the `cubie-a5e-spi` image to the target drive:

```bash
# NVMe
zstdcat cubie-a5e-spi.raw.zst | sudo dd of=/dev/nvme0n1 bs=4M status=progress

# USB drive
zstdcat cubie-a5e-spi.raw.zst | sudo dd of=/dev/sdX bs=4M status=progress
```

The `cubie-a5e-spi` configuration has no U-Boot gap on disk (partition starts at sector 0).

Default boot order: NVMe → USB → SD card (`mmc0`).

## Backported patches

- **CPU thermal sensor (A523 THS0/THS1)** - the mainline `sun8i_thermal` driver does not yet
  support the A523/A527's actual THS0/THS1 sensor hardware, so `/sys/class/thermal` reports a
  static, non-updating temperature. This is fixed by backporting the not-yet-merged upstream
  series ["\[PATCH v5 0/5\] Allwinner: A523: add support for A523 THS0/1 controllers"](https://patchew.org/linux/20260704171411.1413349-1-iuncuim@gmail.com/)
  by Mikhail Kalashnikov, applied via `boot.kernelPatches` in `modules/cubie-a5e.nix`
  (patch files in `modules/patches/kernel/`). This is automatically enabled whenever
  `hardware.cubie-a5e.enable = true` and can be dropped once nixpkgs' kernel includes the
  upstream merge.

- **PCIe + combo PHY (NVMe/M.2)** - the mainline kernel does not yet include PCIe or combo PHY
  support for A523/A527. This is fixed by applying patches from
  [Armbian](https://github.com/armbian/build) (by Marvin Wewer): CLK_USB3_REF clock fix,
  Innosilicon combo PHY driver, Allwinner sunxi PCIe RC driver, and SoC/board DT nodes.
  Applied via `boot.kernelPatches` in `modules/cubie-a5e.nix` (patch files in
  `modules/patches/kernel/`). Automatically enabled with `hardware.cubie-a5e.enable = true`.
  Includes a fix for MSI-X support: the Armbian 7.0 driver omits `MSI_FLAG_PCI_MSIX` from its
  `msi_parent_ops.supported_flags`, so no MSI-X device domain can be created and MSI-X capable
  devices such as NVMe fall back to legacy INTx - a single shared queue with frequent
  `I/O tag ... timeout, completion polled` stalls (~30 s each, the `nvme_core.io_timeout`
  default), which in turn drives btrfs read-only with `errno=-5`. The in-tree DesignWare host
  (`pcie-designware-host.c`) lists this flag; sunxi does not. This bug is present in upstream
  Armbian as of 2026-08.

## Known issues

- **PSCI SYSTEM_RESET not implemented** in vendor TF-A - `watchdog-reboot-helper` service crashes kernel on shutdown so hardware watchdog triggers reboot
- **eMMC boot not tested**

## Tested on

- NixOS 26.05 + kernel 7.1 (also works with 7.0)
- Radxa Cubie A5E with AIC8800D80 WiFi/BT chip
