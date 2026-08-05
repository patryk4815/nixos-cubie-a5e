{ pkgs, lib, config, ... }:
let
  cfg = config.hardware.cubie-a5e;
in
{
  options.hardware.cubie-a5e = {
    enable = lib.mkEnableOption "Radxa Cubie A5E board support";

    watchdog-reboot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable watchdog-based reboot workaround for WIP TF-A (no PSCI SYSTEM_RESET)";
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.aic8800.enable = true;

    boot.kernelPatches = [
      # Thermal sensor support (THS0/THS1) - backported from upstream
      # https://patchew.org/linux/20260704171411.1413349-1-iuncuim@gmail.com/
      { name = "sun55i-a523-thermal-1-dt-bindings"; patch = ./patches/kernel/0001-dt-bindings-thermal-sun8i-add-a523-ths.patch; }
      { name = "sun55i-a523-thermal-2-reset-control-shared"; patch = ./patches/kernel/0002-thermal-sun8i-reset-control-shared-deasserted.patch; }
      { name = "sun55i-a523-thermal-3-two-nvmem-cells"; patch = ./patches/kernel/0003-thermal-sun8i-calibration-two-nvmem-cells.patch; }
      { name = "sun55i-a523-thermal-4-ths0-ths1-driver"; patch = ./patches/kernel/0004-thermal-sun8i-add-a523-ths0-ths1-support.patch; }
      { name = "sun55i-a523-thermal-5-dts-sensors-zones"; patch = ./patches/kernel/0005-arm64-dts-allwinner-sun55i-add-thermal-sensors.patch; }
      # PCIe + combo PHY support - from Armbian (Marvin Wewer)
      { name = "a523-clk-usb3-ref"; patch = ./patches/kernel/drv-clk-sunxi-ng-fix-clock-handling-for-ccu-sun55i-a523.patch; }
      { name = "a523-combophy"; patch = ./patches/kernel/drv-phy-allwinner-add-pcie-usb3-driver.patch; }
      { name = "a523-pcie-rc"; patch = ./patches/kernel/drv-pci-sunxi-enable-pcie-support.patch; }
      { name = "a523-pcie-dts"; patch = ./patches/kernel/arm64-dts-sun55i-dtsi-add-iommu-usbc-pcie-combophy-nodes.patch; }
      { name = "a523-cubie-pcie-dts"; patch = ./patches/kernel/arm64-dts-sun55i-a527-cubie-a5e-enable-usbc-pcie-combophy.patch; }
      {
        name = "a523-pcie-config";
        patch = null;
        structuredExtraConfig = {
          PCIE_SUN55I_RC = lib.kernel.yes;
          AW_INNO_COMBOPHY = lib.kernel.yes;
        };
      }
    ];

    # Hardware watchdog for reliable reboot/shutdown detection
    systemd.settings.Manager = {
      RuntimeWatchdogSec = "15s";
      RebootWatchdogSec = "15s";
    };

    # Workaround: WIP TF-A doesn't support PSCI SYSTEM_RESET
    # Crash kernel on shutdown so hardware watchdog triggers reboot
    systemd.services.watchdog-reboot-helper = lib.mkIf cfg.watchdog-reboot {
      description = "Crash kernel for reboot";
      wantedBy = [ "multi-user.target" ];
      before = [ "shutdown.target" ];
      conflicts = [ "shutdown.target" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
        ExecStop = "${pkgs.bash}/bin/bash -c 'echo c > /proc/sysrq-trigger'";
      };
    };
  };
}
