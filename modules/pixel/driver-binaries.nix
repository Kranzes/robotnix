{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkIf mkOption mkMerge types;

  driversList = lib.importJSON ./pixel-drivers.json;
  fetchItem = type: device: buildID: let
    matchingItem = lib.findSingle
      (v: lib.hasInfix "/${type}-${device}-${lib.toLower buildID}" v.url)
      (throw "no items found for ${type} ${device} drivers")
      (throw "multiple items found for ${type} ${device} drivers")
      driversList;
  in
    pkgs.fetchurl matchingItem;

  unpackDrivers = tarball: pkgs.runCommand "unpacked-${lib.strings.sanitizeDerivationName tarball.name}" {} ''
    tar xvf ${tarball}

    mkdir -p $out
    tail -n +315 ./extract-*.sh | tar zxv -C $out
  '';
in
{
  options = {
    pixel.useUpstreamDriverBinaries = mkOption {
      default = false;
      type = types.bool;
      description = "Use device vendor binaries from https://developers.google.com/android/drivers";
    };
  };

  config = mkMerge [
    (mkIf config.pixel.useUpstreamDriverBinaries {
      assertions = [
        { assertion = !config.apv.enable;
          message = "pixel.useUpstreamDriverBinaries and apv.enable must not both be set to true";
        }
      ];

      # Merge qcom and google drivers
      source.dirs."vendor/google_devices/${config.device}".src = pkgs.runCommand "${config.device}-vendor" {} ''
        mkdir extracted

        cp -r ${config.build.driversGoogle}/vendor/google_devices/${config.device}/. extracted
        chmod +w -R extracted
        cp -r ${config.build.driversQcom}/vendor/google_devices/${config.device}/. extracted

        mv extracted $out
      '';

      source.dirs."vendor/qcom/${config.device}".src = "${config.build.driversQcom}/vendor/qcom/${config.device}";
    })

    ({
      build = {
        driversGoogle = unpackDrivers (fetchItem "google_devices" config.device config.apv.buildID);
        driversQcom = unpackDrivers (fetchItem "qcom" config.device config.apv.buildID);
      };
    })
  ];
}
