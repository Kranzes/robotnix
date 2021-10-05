# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ stdenv, lib, callPackage, fetchurl, fetchpatch, fetchFromGitHub, autoPatchelfHook, makeWrapper,
  simg2img, zip, unzip, e2fsprogs, jq, jdk, curl, utillinux, perl, python2, python3, libarchive,
  api ? 30
}:

let
  python = if api >= 30 then python3 else python2;

  dexrepair = callPackage ./dexrepair.nix {};
  apiStr = builtins.toString api;

  # TODO: Build this ourselves?
  oatdump = stdenv.mkDerivation {
    name = "oatdump-${apiStr}";

    src = fetchurl {
      url = https://onedrive.live.com/download?cid=D1FAC8CC6BE2C2B0&resid=D1FAC8CC6BE2C2B0%21574&authkey=ADSQA_DtfAmmk2c;
      name = "oatdump-${apiStr}.zip";
      sha256 = "0kiq173jqg6qzw9m5wwp0kh1d3zxxksi69xj4nwg7pp43m4lfjir";
    };

    nativeBuildInputs = [ autoPatchelfHook ];

    unpackPhase = ''
      ${unzip}/bin/unzip $src
    '';

    installPhase = ''
      mkdir -p $out
      cp -r * $out
    '';
  };

  version = if api >= 30 then "2021-09-07" else "2020-08-26";
  src = if api >= 30
    then fetchFromGitHub {
      # Android11 branch
      owner = "AOSPAlliance";
      repo = "android-prepare-vendor";
      rev = "227f5ce7cd89a3f57291fe2b84869c7a5d1e17fa";
      sha256 = "07g5dcl2x44ai5q2yfq9ybx7j7kn41s82hgpv7jff5v1vr38cia9";
    } else fetchFromGitHub {
      # Android10 branch
      owner = "AOSPAlliance";
      repo = "android-prepare-vendor";
      rev = "a9602ca6ef16ff10641d668dcb203f89f402d40d";
      sha256 = "0wldj8ykwh8r7m1ff6vbkbc73a80lmmxwfmk8nm0cnzpbfk4cq7w";
    };

in
(stdenv.mkDerivation {
  pname = "android-prepare-vendor";
  inherit src version;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [
    (python.withPackages (p: [ p.protobuf ])) # Python is used by "extract_android_ota_payload"
  ];

  patches = [
    ./0001-Disable-oatdump-update.patch
    ./0002-Just-write-proprietary-blobs.txt-to-current-dir.patch
    ./0003-Allow-for-externally-set-config-file.patch
    ./0004-Add-option-to-use-externally-provided-carrier_list.p.patch
  ];

  # TODO: No need to copy oatdump now that we're making a standalone android-prepare-vendor.
  # Just patch it out instead
  postPatch = ''
    patchShebangs ./execute-all.sh
    patchShebangs ./scripts
    # TODO: Hardcoded api version
    mkdir -p hostTools/Linux/api-${apiStr}/
    cp -r ${oatdump}/* hostTools/Linux/api-${apiStr}/

    for i in ./execute-all.sh ./scripts/download-nexus-image.sh ./scripts/extract-factory-images.sh ./scripts/generate-vendor.sh ./scripts/gen-prop-blobs-list.sh ./scripts/realpath.sh ./scripts/system-img-repair.sh ./scripts/extract-ota.sh; do
        sed -i '2 i export PATH=$PATH:${lib.makeBinPath [ zip unzip simg2img dexrepair e2fsprogs jq jdk utillinux perl curl libarchive ]}' $i
    done

    # Fix when using --input containing readonly files
    substituteInPlace ./scripts/generate-vendor.sh \
      --replace "cp -a " "cp -af "
  '';

  installPhase = ''
    mkdir -p $out
    cp -r * $out
  '';

  configurePhase = ":";

  postFixup = ''
    wrapProgram $out/scripts/extract_android_ota_payload/extract_android_ota_payload.py \
      --prefix PYTHONPATH : "$PYTHONPATH"
  '';

  # To allow eval-time fetching of config resources from this repo.
  # Hack: Only known to work with fetchFromGitHub
  passthru.evalTimeSrc = builtins.fetchTarball {
    url = lib.head src.urls;
    sha256 = src.outputHash;
  };
})
