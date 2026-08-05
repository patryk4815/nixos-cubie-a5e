# Changelog

## v2.0.0

Adds PCIe/NVMe, SPI NOR boot, mainline U-Boot and kernel 7.1 support.

### Added

**PCIe / NVMe (M.2 slot)** - the mainline kernel has no PCIe or combo PHY support for
A523/A527. Backported from [Armbian](https://github.com/armbian/build) (Marvin Wewer):
CLK_USB3_REF clock fix, Innosilicon combo PHY driver, Allwinner sunxi PCIe RC driver and
SoC/board DT nodes. Enabled automatically with `hardware.cubie-a5e.enable = true`.

**CPU thermal sensors (THS0/THS1)** - the mainline `sun8i_thermal` driver does not support
the A523/A527 sensor hardware, so `/sys/class/thermal` reported a static temperature.
Backported from the not-yet-merged upstream series by Mikhail Kalashnikov.

**Kernel 7.1 support** - the out-of-tree AIC8800 WiFi/Bluetooth driver does not build against
7.1. Added `modules/aic8800-kernel-7.1.patch` covering the `cfg80211_ops` signature change
from `struct net_device *` to `struct wireless_dev *`, `cfg80211_new_sta`/`cfg80211_del_sta`,
the removal of `ieee80211_mgmt.u.action.u.tdls_discover_resp`, and the removal of
`linux/of_gpio.h`. Applied conditionally, so kernel 7.0 keeps working.

**Mainline U-Boot with SPI NOR and PCIe** - new `uboot-vendor`, `uboot-1gb`, `uboot-2gb`
packages and matching `spinor-*` flash images. Uses TF-A from
[jernejsk/arm-trusted-firmware](https://github.com/jernejsk/arm-trusted-firmware); the 1GB
variant carries a DRAM timing patch, since the 1GB and 2GB/4GB models use incompatible timings.

**New options**

| Option | Values | Notes |
|---|---|---|
| `hardware.cubie-a5e.uboot` | `vendor`, `mainline-1gb`, `mainline-2gb+`, `none` | `none` for U-Boot flashed to SPI NOR |
| `hardware.cubie-a5e.combophy` | `pcie` (default), `usb3` | PCIe and USB 3.0 share one PHY |
| `hardware.cubie-a5e.spi-nor` | bool (default `true`) | DT overlay enabling SPI0 |

**Reflashing SPI NOR from Linux** - `hardware.cubie-a5e.spi-nor` exposes the flash chip as
`/dev/mtd0`, so U-Boot can be rewritten with `flashcp` without entering FEL mode.

**`cubie-a5e-spi` configuration** - no U-Boot gap on disk (first partition at sector 0), for
booting from NVMe or USB with U-Boot in SPI NOR.

**`sunxi-fel` for all platforms** including Darwin, with `meta.mainProgram` set so
`nix run .#sunxi-fel` works.

**CI** - GitHub Actions builds SD card images, U-Boot binaries and SPI NOR images on `v*` tags
and uploads them to the release.

**Base image tools** - `parted`, `pciutils`, `usbutils`, `smartmontools`, `mtdutils`, `vim`.

### Fixed

**NVMe fell back to legacy INTx (MSI-X never enabled).** The Armbian sunxi PCIe driver omits
`MSI_FLAG_PCI_MSIX` from `msi_parent_ops.supported_flags`. `__pci_enable_msix_range()` checks
this before allocating anything (`drivers/pci/msi/msi.c`) and returns `-ENOTSUPP`, so an
MSI-X-only device such as an NVMe SSD ended up on a single shared INTx line. Every I/O whose
completion interrupt was missed stalled for the full `nvme_core.io_timeout` (~30 s) until the
watchdog polled it, which in turn drove btrfs read-only with `errno=-5`. The in-tree
DesignWare host driver lists this flag; sunxi does not. Bug present in upstream Armbian as of
2026-08. Confirmed fixed on hardware: 9 MSI-X vectors, no timeouts.

**`CONFIG_PCI_MSI` was not enabled** in the kernel config.

**PCIe driver did not build on kernel 7.1** - `linux/of_gpio.h` was removed upstream; replaced
with `linux/of.h` + `linux/gpio/consumer.h`, which works on both 7.0 and 7.1.

**U-Boot never tried NVMe** - sunxi's `BOOT_TARGET_DEVICES` in `include/configs/sunxi-common.h`
has no NVMe entry, so `boot_targets` came out as `fel mmc_auto usb0 pxe dhcp`. `distro_bootcmd`
already supports NVMe generically, gated on `CONFIG_NVME`.

**AIC8800 flooded dmesg** - the driver defaults to `LOGERROR|LOGINFO|LOGDEBUG|LOGTRACE|LOGFW`.
Now set to `LOGERROR` via modprobe; still tunable at runtime through
`/sys/module/aic8800_fdrv/parameters/aicwf_dbg_level`.

### Changed

- Kernel 7.1 is now the default (7.0 still supported).
- `/boot` is mounted with `sync`.

### Known limitations

- **USB 3.0 does not work.** The combo PHY can be switched with
  `hardware.cubie-a5e.combophy = "usb3"`, but there are no DWC3/xHCI device tree nodes for
  A523/A527 in mainline - not in Armbian either - so the port enumerates at USB 2.0 speed.
  PCIe and USB 3.0 are mutually exclusive regardless, as they share one PHY.
- **All NVMe interrupts land on CPU0.** `sunxi_msi_set_affinity()` in the Armbian driver is a
  stub, so there is no IRQ spreading. Throughput on Gen2 x1 is unaffected.
- HDMI, MIPI DSI/CSI, GPU and hardware video decode remain unsupported in mainline.

## v1.0.0

Initial release: AIC8800 SDIO WiFi/Bluetooth driver and firmware, Bluetooth HCI over UART1,
device tree overlay for mmc1/UART1, disko SD card image with vendor U-Boot, and the watchdog
reboot workaround for TF-A without PSCI `SYSTEM_RESET`.
