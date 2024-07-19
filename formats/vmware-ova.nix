{
  modulesPath,
  specialArgs,
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption;

  diskSize = specialArgs.diskSize or "auto";
  formatAttr = "vmwareOVA";
  cfg = config.vmware-ova;

  argsFormat.type =
    with lib.types;
    attrsOf (
      nullOr (oneOf [
        int
        bool
        str
        (listOf (oneOf [
          int
          bool
          str
        ]))
      ])
    );
  argsFormat.generate =
    let
      # Taken from lib/cli.nix
      mkOptionName = k: if builtins.stringLength k == 1 then "-${k}" else "--${k}";
    in
    lib.cli.toGNUCommandLineShell {
      mkList =
        k: vs:
        lib.optionals (vs != [ ]) [ (mkOptionName k) ]
        ++ builtins.map (lib.generators.mkValueStringDefault { }) vs;
    };
in
{
  imports = [ "${toString modulesPath}/virtualisation/virtualbox-image.nix" ];
  options = {
    vmware-ova = {
      baseImageSize = mkOption {
        type = with lib.types; either (enum [ "auto" ]) int;
        default = "auto";
        example = 2048;
        description = ''
          The size of the VMWare base image in MiB.
        '';
      };
      vmDerivationName = mkOption {
        type = lib.types.str;
        default = "nixos-vmware-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}";
        description = ''
          The name of the derivation for the VMWare appliance.
        '';
      };
      vmFileName = mkOption {
        type = lib.types.str;
        default = "nixos-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}.ova";
        description = ''
          The file name of the VMWare appliance.
        '';
      };
      product = mkOption {
        default = { };
        description = "Arguments passed to `cot edit-product`";
        # NOTE: examples taken from
        # https://github.com/glennmatthews/cot/tree/master/docs licensed under MIT
        type = lib.types.submodule (
          { config, ... }:
          {
            freeformType = argsFormat.type;
            options = {
              product = mkOption {
                type = lib.types.str;
                default = "Unnamed product";
                example = "Cisco IOS-XE";
              };
              vendor = mkOption {
                type = lib.types.str;
                default = "Unknown vendor";
                example = "Cisco Systems, Inc.";
              };
              version = mkOption {
                type = lib.types.str;
                default = "0.0.0";
                description = "Software short version string";
                example = "15.3(4)S";
              };
              full-version = mkOption {
                type = lib.types.str;
                default = "${config.product} Software, Version ${config.version}";
                description = "Software long version string";
              };
              product-url = mkOption {
                type = with lib.types; nullOr str;
                default = null;
                description = "Product URL";
                example = "http://www.cisco.com/go/iosxrv";
              };
              vendor-url = mkOption {
                type = with lib.types; nullOr str;
                default = null;
                description = "Vendor URL";
                example = "http://www.cisco.com";
              };
              application-url = mkOption {
                type = with lib.types; nullOr str;
                default = null;
                description = "Application URL";
                example = "https://router1:530/";
              };
            };
          }
        );
      };
      hardware = mkOption {
        default = { };
        description = "Arguments passed to `cot edit-hardware`";
        type = lib.types.submodule (
          { config, ... }:
          {
            freeformType = argsFormat.type;
            options = {
              profiles = mkOption {
                type = with lib.types; listOf str;
                default = [ ];
                defaultText = lib.literalMD "All profiles";
                description = "Profile(s) to change";
              };
              virtual-system-type = mkOption {
                type = with lib.types; listOf str;
                default = [ "vmx-20" ];
              };
              delete-all-other-profiles = lib.mkEnableOption "Delete all configuration profiles other than those specified with the --profiles option";
              cpus = mkOption {
                type = with lib.types; nullOr int;
                default = null;
                example = 1;
              };
              memory = mkOption {
                type = with lib.types; nullOr str;
                default = null;
                example = "4 GiB";
              };
              nics = mkOption {
                type = with lib.types; nullOr int;
                default = null;
                example = 1;
                description = "Number of NICs";
              };
              nic-types = mkOption {
                type = with lib.types; listOf str;
                default = [ ];
              };
              nic-names = mkOption {
                type = with lib.types; listOf str;
                default = [ ];
              };
              nic-networks = mkOption {
                type = with lib.types; listOf str;
                default = [ ];
              };
              network-descriptions = mkOption {
                type = with lib.types; listOf str;
                default = [ ];
              };
              mac-addresses-list = mkOption {
                type = with lib.types; listOf str;
                default = [ ];
              };
              serial-ports = mkOption {
                type = with lib.types; nullOr int;
                default = null;
                description = "Number of serial ports";
              };
              serial-connectivity = mkOption {
                type = with lib.types; listOf str;
                default = [ ];
                example = [ "telnet://localhost:9101" ];
                description = "Connectivity strings. If fewer URIs than serial ports are specified, the remaining ports will be unmapped";
              };
              scsi-subtypes = mkOption {
                type = with lib.types; listOf str;
                default = [ ];
                example = [
                  "lsilogic"
                  "virtio"
                ];
                description = ''Resource subtype(s) for all SCSI controllers. If an empty string is provided, any existing subtype will be removed'';
              };
              ide-subtypes = mkOption {
                type = with lib.types; listOf str;
                default = [ ];
                example = [ "virtio" ];
                description = "Resource subtype(s) for all IDE controllers. If an empty string is provided, any existing subtype will be removed";
              };
            };
          }
        );
      };
    };
  };
  config = {
    inherit formatAttr;
    fileExtension = ".ova";

    boot.loader.grub.device = lib.mkForce "/dev/sda"; # Resolve conflict between virtualbox-image.nix and vmware-image.nix
    vmware-ova.baseImageSize = if diskSize == "auto" then "auto" else lib.strings.toIntBase10 diskSize;

    # NOTE: This is a naive implementation operating on multiple copies of the image.
    # One could probably reuse the logic in virtualbox-image.nix to create a
    # single fused derivation working on a single image copy.
    system.build.${formatAttr} =
      pkgs.runCommand cfg.vmDerivationName
        {
          nativeBuildInputs = [ pkgs.cot ];
          VBOX_OVA = "${config.system.build.virtualBoxOVA}";
          cotFlags = [
            "--force"
            "--verbose"
          ];
        }
        (
          ''
            ova=$VBOX_OVA/*.ova

            cot $cotFlags edit-product $ova ${argsFormat.generate cfg.product} --output nixos.ova
          ''
          + lib.optionalString (argsFormat.generate cfg.hardware != "") ''
            cot $cotFlags edit-hardware nixos.ova ${argsFormat.generate cfg.hardware}
          ''
          + ''
            mkdir "$out"
            mv nixos.ova "$out"/${cfg.vmFileName}
          ''
        );
  };
}
