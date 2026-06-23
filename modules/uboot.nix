{ pkgs }:
let
  armTrustedFirmwareSun55i = pkgs.buildPackages.buildArmTrustedFirmware rec {
    platform = "sun55i_a523";
    extraMeta.platforms = [ "aarch64-linux" ];
    filesToInstall = [ "build/${platform}/debug/bl31.bin" ];
    extraMakeFlags = [ "DEBUG=1" ];
    src = pkgs.fetchFromGitHub {
      owner = "jernejsk";
      repo = "arm-trusted-firmware";
      rev = "e019f64d91ff7c2dfbbfe7f76a14f240761b9edc"; # branch: a523-v4
      hash = "sha256-c42bWMYTlhNn4Byr3gaptkgatHv2DrRtXGj6GH7IbUg=";
    };
  };

  mkUboot = defconfig: extraPatches: pkgs.buildPackages.buildUBoot {
    inherit defconfig extraPatches;
    extraMeta.platforms = [ "aarch64-linux" ];
    env.BL31 = "${armTrustedFirmwareSun55i}/bl31.bin";
    filesToInstall = [ "u-boot-sunxi-with-spl.bin" ];
  };

  spiNorImageSize = 16; # MiB

  mkSpiNorImage = name: uboot: pkgs.buildPackages.runCommand "${name}-spinor.img" {} ''
    dd if=/dev/zero of=$out bs=1M count=${toString spiNorImageSize}
    dd if=${uboot}/u-boot-sunxi-with-spl.bin of=$out bs=1k conv=notrunc
  '';

  vendor = pkgs.buildPackages.stdenv.mkDerivation {
    pname = "u-boot-radxa-cubie-a5e";
    version = "2018.07-17";
    src = pkgs.fetchurl {
      url = "https://github.com/radxa-pkg/u-boot-aw2501/releases/download/2018.07-17/u-boot-aw2501_2018.07-17_all.deb";
      hash = "sha256-hM2IV20KDh8TR8v0cyUe4f1RFk5E8sOh+OV/v0pyuok=";
    };
    nativeBuildInputs = [ pkgs.buildPackages.dpkg ];
    unpackPhase = "dpkg-deb -x $src .";
    installPhase = ''
      mkdir -p $out
      cp usr/lib/u-boot/radxa-cubie-a5e/boot0_sdcard.bin $out/
      cp usr/lib/u-boot/radxa-cubie-a5e/boot_package.fex $out/
    '';
  };

  mainline-1gb = mkUboot "radxa-cubie-a5e-1gb_defconfig" [ ./radxa-cubie-a5e-1gb-defconfig.patch ];
  mainline-2gb = mkUboot "radxa-cubie-a5e_defconfig" [ ./radxa-cubie-a5e-spi-nor.patch ];
in {
  inherit vendor mainline-1gb mainline-2gb;

  spinor-1gb = mkSpiNorImage "cubie-a5e-1gb" mainline-1gb;
  spinor-2gb = mkSpiNorImage "cubie-a5e-2gb" mainline-2gb;
}
