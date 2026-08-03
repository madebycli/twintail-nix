{
  description = "Native Nix package for TwintailLauncher (no Flatpak)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    twintail_x86_64 = {
      url = "file+https://github.com/TwintailTeam/TwintailLauncher/releases/download/ttl-v2.4.0/twintaillauncher_2.4.0_amd64.deb";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      twintail_x86_64,
      ...
    }:
    let
      version = "2.4.0";
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      package = pkgs.callPackage ./package.nix {
        src = twintail_x86_64;
        inherit version;
      };
    in
    {
      packages.${system} = {
        twintaillauncher = package;
        default = package;
      };

      apps.${system} = {
        twintaillauncher = {
          type = "app";
          program = "${package}/bin/twintaillauncher";
        };
        default = self.apps.${system}.twintaillauncher;
      };

      checks.${system} = {
        inherit package;
        wrapper-runtime = pkgs.runCommand "twintaillauncher-wrapper-runtime" { } ''
          set -euxo pipefail

          launcher=${package}/bin/twintaillauncher
          native_launcher=${package.unwrapped}/bin/twintaillauncher
          winetricks=${package.unwrapped}/lib/twintaillauncher/resources/winetricks
          fhs_root=${package.fhsenv}

          test -x "$launcher"
          test -x "$native_launcher"
          test -x "$winetricks"
          test -x "$fhs_root/usr/bin/true"
          test -x "$fhs_root/usr/bin/ldconfig"
          test -x "$fhs_root/usr/sbin/ldconfig"

          # buildFHSEnv's static init generates the cache before the first
          # dynamically linked process, specifically supporting nested SteamRT.
          grep -a -q 'container-init' "$launcher"
          grep -a -q 'ld.so.cache' "$launcher"
          grep -a -q 'ld.so.conf' "$launcher"

          grep -a -q 'libayatana-appindicator' "$native_launcher"
          grep -a -q 'glib-networking' "$native_launcher"
          grep -a -q 'ca-bundle.crt' "$native_launcher"
          grep -a -q 'gamescope' "$native_launcher"
          grep -a -q 'gamemode' "$native_launcher"
          grep -a -q 'mangohud' "$native_launcher"
          grep -a -q 'cabextract' "$native_launcher"
          grep -a -q 'p7zip' "$native_launcher"
          grep -a -q 'WINETRICKS_LATEST_VERSION_CHECK' "$native_launcher"
          grep -a -q 'PRESSURE_VESSEL_FILESYSTEMS_RO' "$native_launcher"
          grep -a -q '/nix/store' "$native_launcher"
          grep -a -q 'PROTON_DLL_COPY' "$native_launcher"
          ! grep -a -q 'PRESSURE_VESSEL_BWRAP' "$native_launcher"

          head -n 1 "$winetricks" | grep -E '^#!/nix/store/.+/bin/bash$'
          ! head -n 1 "$winetricks" | grep -q '^#!/bin/sh$'
          grep -q 'command -v unrar-free' "$winetricks"
          grep -Fq 'msvcp140.dll_x86' "$winetricks"
          grep -Fq 'msvcp140_2.dll_x86' "$winetricks"
          grep -Fq 'msvcp140.dll_amd64' "$winetricks"
          grep -Fq 'msvcp140_2.dll_amd64' "$winetricks"
          grep -Fq 'export PATH="/nix/store/' "$winetricks"
          grep -Fq 'winetricks.log' "$winetricks"
          ${pkgs.bash}/bin/bash -n "$winetricks"

          for candidate in "$launcher" "$native_launcher"; do
            if grep -a -E -q '/nix/store/[^/]+-mesa-[0-9]' "$candidate"; then
              echo "TwintailLauncher directly references the complete Mesa output" >&2
              exit 1
            fi

            if grep -a -E -q '/nix/store/[^/]+-(wine|proton)-[0-9]' "$candidate"; then
              echo "Proton and Wine must remain launcher-managed rather than package-managed" >&2
              exit 1
            fi
          done

          touch "$out"
        '';
      };

      overlays.default = final: _prev:
        nixpkgs.lib.optionalAttrs (final.stdenv.hostPlatform.system == system) {
          twintaillauncher = final.callPackage ./package.nix {
            src = twintail_x86_64;
            inherit version;
          };
        };

      nixosModules.default =
        { config, lib, pkgs, ... }:
        let
          cfg = config.programs.twintaillauncher;
          hostSystem = pkgs.stdenv.hostPlatform.system;
        in
        {
          options.programs.twintaillauncher.enable =
            lib.mkEnableOption "the native TwintailLauncher package";

          config = lib.mkIf cfg.enable {
            assertions = [
              {
                assertion = hostSystem == system;
                message = "TwintailLauncher is packaged only for x86_64-linux.";
              }
            ];

            environment.systemPackages =
              lib.optionals (hostSystem == system) [ self.packages.${system}.twintaillauncher ];

            programs.gamemode.enable = lib.mkDefault true;
            programs.gamescope.enable = lib.mkDefault true;
          };
        };
    };
}
