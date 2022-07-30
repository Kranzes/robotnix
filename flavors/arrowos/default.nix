# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
let
  inherit (lib)
    optional optionals optionalString optionalAttrs
    elem mapAttrs mapAttrs' nameValuePair filterAttrs
    attrNames getAttrs flatten remove
    mkIf mkMerge mkDefault mkForce
    importJSON toLower hasPrefix removePrefix;

  androidVersionToArrowBranch = {
    "11" = "arrow-11.0";
    "12" = "arrow-12.1";
  };
  arrowBranchToAndroidVersion = mapAttrs' (name: value: nameValuePair value name) androidVersionToArrowBranch;

  deviceMetadata = lib.importJSON ./device-metadata.json;
  ArrowOSRelease = androidVersionToArrowBranch.${builtins.toString config.androidVersion};
  repoDirs = lib.importJSON (./. + "/${ArrowOSRelease}/repo.json");
  _deviceDirs = importJSON (./. + "/${ArrowOSRelease}/device-dirs.json");

  # TODO: Condition on soc name?
  dtbReproducibilityFix = ''
    sed -i \
      's/^DTB_OBJS := $(shell find \(.*\))$/DTB_OBJS := $(sort $(shell find \1))/' \
      arch/arm64/boot/Makefile
  '';
  kernelsNeedFix = [
    # Only verified marlin reproducibility is fixed by this, however these other repos have the same issue
    "kernel/asus/sm8150"
    "kernel/bq/msm8953"
    "kernel/essential/msm8998"
    "kernel/google/marlin"
    "kernel/leeco/msm8996"
    "kernel/lge/msm8996"
    "kernel/motorola/msm8996"
    "kernel/motorola/msm8998"
    "kernel/motorola/sdm632"
    "kernel/nubia/msm8998"
    "kernel/oneplus/msm8996"
    "kernel/oneplus/sdm845"
    "kernel/oneplus/sm8150"
    "kernel/razer/msm8998"
    "kernel/samsung/sdm670"
    "kernel/sony/sdm660"
    "kernel/xiaomi/jason"
    "kernel/xiaomi/msm8998"
    "kernel/xiaomi/sdm660"
    "kernel/xiaomi/sdm845"
    "kernel/yandex/sdm660"
    "kernel/zuk/msm8996"
  ];
  # Patch kernels
  patchKernelDir = n: v: v // (optionalAttrs (hasPrefix "kernel/" n) {
    patches = config.kernel.patches;
    postPatch = config.kernel.postPatch
      + optionalString (config.useReproducibilityFixes && (elem n kernelsNeedFix)) ("\n" + dtbReproducibilityFix);
  });
  deviceDirs = mapAttrs patchKernelDir _deviceDirs;

  supportedDevices = attrNames deviceMetadata;

  # TODO: Move this filtering into vanilla/graphene
  filterDirAttrs = dir: filterAttrs (n: v: elem n [ "rev" "sha256" "url" "patches" "postPatch" ]) dir;
  filterDirsAttrs = dirs: mapAttrs (n: v: filterDirAttrs v) dirs;
in
mkIf (config.flavor == "arrowos")
{
  androidVersion =
    let
      defaultBranch = deviceMetadata.${config.device}.branch;
    in
    mkIf (deviceMetadata ? ${config.device}) (mkDefault (lib.toInt arrowBranchToAndroidVersion.${defaultBranch}));
  flavorVersion = removePrefix "arrow-" androidVersionToArrowBranch.${toString config.androidVersion};

  productNamePrefix = "arrow_"; # product names start with "arrow_"

  buildDateTime = mkDefault 1659127974;

  # ArrowOS uses this by default. If your device supports it, I recommend using variant = "user"
  variant = mkDefault "userdebug";

  warnings = optional
    (
      (config.device != null) &&
      !(elem config.device supportedDevices) &&
      (config.deviceFamily != "generic")
    )
    "${config.device} is not an officially-supported device for ArrowOS";

  source.dirs = mkMerge ([
    repoDirs

    {
      "vendor/arrow".patches = [ ./0001-kernel-Set-constant-kernel-timestamp.patch ];
      "system/extras".patches = [
        # pkgutil.get_data() not working, probably because we don't use their compiled python
        (pkgs.fetchpatch {
          url = "https://github.com/ArrowOS/android_system_extras/commit/62556d41c784ae86e5ef415f4b9760ab97d90097.patch";
          sha256 = "sha256-hl+oUgENXPzzbEX0dc/7GwgTsX57nKFVoTLV58viLks=";
          revert = true;
        })
      ];

      # ArrowOS will sometimes force-push to this repo, and the older revisions are garbage collected.
      # So we'll just build chromium webview ourselves.
      "external/chromium-webview".enable = false;
    }
  ] ++ optionals (deviceMetadata ? "${config.device}") [
    # Device-specific source dirs
    (
      let
        vendor = toLower deviceMetadata.${config.device}.vendor;
        relpathWithDependencies = relpath: [ relpath ] ++ (flatten (map (p: relpathWithDependencies p) deviceDirs.${relpath}.deps));
        relpaths = relpathWithDependencies "device/${vendor}/${config.device}";
        filteredRelpaths = remove (attrNames repoDirs) relpaths; # Remove any repos that we're already including from repo json
      in
      filterDirsAttrs (getAttrs filteredRelpaths deviceDirs)
    )

    # Vendor-specific source dirs
    (
      let
        _vendor = toLower deviceMetadata.${config.device}.vendor;
      in
      filterDirsAttrs (getAttrs [ "vendor/${_vendor}" ] _deviceDirs)
    )
  ]
  );

  source.manifest.url = mkDefault "https://github.com/ArrowOS/android_manifest";
  source.manifest.rev = mkDefault "refs/heads/${ArrowOSRelease}";

  # Enable robotnix-built chromium / webview
  apps.chromium.enable = mkDefault true;
  webview.chromium.availableByDefault = mkDefault true;
  webview.chromium.enable = mkDefault true;

  # This is the prebuilt webview apk from ArrowOS. Adding this here is only
  # for convenience if the end-user wants to set `webview.prebuilt.enable = true;`.
  webview.prebuilt.apk = config.source.dirs."external/chromium-webview".src + "/prebuilt/${config.arch}/webview.apk";
  webview.prebuilt.availableByDefault = mkDefault true;
  removedProductPackages = [ "webview" ];

  apps.updater.flavor = mkDefault "arrowos";
  apps.updater.includedInFlavor = mkDefault true;
  apps.seedvault.includedInFlavor = mkDefault false;
  pixel.activeEdge.includedInFlavor = mkDefault true;

  # Needed by included kernel build for some devices
  envPackages = [ pkgs.openssl.dev ] ++ optionals (config.androidVersion >= 11) [ pkgs.gcc.cc pkgs.glibc.dev ];

  envVars.RELEASE_TYPE = mkDefault "EXPERIMENTAL"; # Other options are RELEASE NIGHTLY SNAPSHOT EXPERIMENTAL

  # ArrowOS flattens all APEX packages
  signing.apex.enable = false;
  envVars.OVERRIDE_TARGET_FLATTEN_APEX = "true";

  # ArrowOS needs this additional command line argument to enable
  # backuptool.sh, which runs scripts under /system/addons.d
  otaArgs = [ "--backup=true" ];
}
