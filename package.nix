{
  lib,
  stdenv,
  src,
  version,
  dpkg,
  autoPatchelfHook,
  wrapGAppsHook3,
  makeWrapper,
  patch,
  buildFHSEnv,
  bash,
  sqlite,
  cabextract,
  coreutils,
  curl,
  gawk,
  gnugrep,
  gnused,
  gnutar,
  gzip,
  p7zip,
  perl,
  unrar-free,
  unzip,
  which,
  xdg-utils,
  xz,
  zenity,
  gamescope,
  gamemode,
  mangohud,
  gtk3,
  webkitgtk_4_1,
  libsoup_3,
  glib-networking,
  cacert,
  libayatana-appindicator,
  librsvg,
  openssl,
  glib,
  gdk-pixbuf,
  cairo,
  pango,
  dbus,
  alsa-lib,
  libpulseaudio,
  fontconfig,
  freetype,
  harfbuzz,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
  libxkbcommon,
  libdrm,
  libglvnd,
  libgbm,
  vulkan-loader,
  wayland,
  zlib,
}:

let
  winetricksRuntimeDependencies = [
    bash
    cabextract
    coreutils
    curl
    gawk
    gnugrep
    gnused
    gnutar
    gzip
    p7zip
    perl
    unrar-free
    unzip
    which
    xdg-utils
    xz
    zenity
  ];

  gamingRuntimeDependencies = [
    gamescope
    gamemode
    mangohud
  ];

  runtimePath = lib.makeBinPath (
    winetricksRuntimeDependencies ++ gamingRuntimeDependencies
  );

  unwrapped = stdenv.mkDerivation {
    pname = "twintaillauncher-unwrapped";
    inherit version src;

    strictDeps = true;
    dontUnpack = true;
    dontStrip = true;

    nativeBuildInputs = [
      dpkg
      autoPatchelfHook
      wrapGAppsHook3
      makeWrapper
      patch
    ];

    buildInputs = [
      stdenv.cc.cc.lib
      gtk3
      webkitgtk_4_1
      libsoup_3
      glib-networking
      libayatana-appindicator
      librsvg
      openssl
      glib
      gdk-pixbuf
      cairo
      pango
      dbus
      alsa-lib
      libpulseaudio
      fontconfig
      freetype
      harfbuzz
      libx11
      libxcb
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxrandr
      libxkbcommon
      libdrm
      libglvnd
      libgbm
      vulkan-loader
      wayland
      zlib
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      dpkg-deb -x "$src" "$out"

      if [ -d "$out/usr" ]; then
        cp -a "$out/usr/." "$out/"
        rm -rf "$out/usr"
      fi

      if [ ! -x "$out/bin/twintaillauncher" ]; then
        echo "The upstream package did not contain bin/twintaillauncher" >&2
        find "$out" -maxdepth 4 -type f -print >&2
        exit 1
      fi

      winetricks="$out/lib/twintaillauncher/resources/winetricks"
      if [ ! -f "$winetricks" ]; then
        echo "The upstream package did not contain its Winetricks resource" >&2
        exit 1
      fi

      # Twintail 2.4.0 embeds Winetricks 20260125-next. Wine 11 reports builtin
      # msvcp140 DLLs with a newer version than the Visual C++ 2022 redistributable,
      # so explicitly extract the required x86 and x64 DLLs.
      patch --batch --forward \
        -d "$(dirname "$winetricks")" \
        -p0 \
        < ${./patches/winetricks-vcrun2022-wine11.patch}

      # Winetricks runs inside Twintail's downloaded SteamRT. Keep an immutable
      # Nix Bash interpreter, fixed helper paths and persistent diagnostics.
      substituteInPlace "$winetricks" \
        --replace-fail '#!/bin/sh' '#!${bash}/bin/bash' \
        --replace-fail 'command -v unrar' 'command -v unrar-free' \
        --replace-fail 'w_try unrar' 'w_try unrar-free'

      {
        head -n 1 "$winetricks"
        cat <<'SCRIPT'
export PATH="${runtimePath}:''${PATH:-}:/usr/bin:/bin"
unset WINETRICKS_SUPER_QUIET
winetricks_log_dir="''${XDG_CACHE_HOME:-''${HOME}/.cache}/twintaillauncher"
mkdir -p "$winetricks_log_dir"
printf '\n===== %s Winetricks invocation =====\n' "$(date --iso-8601=seconds)" >> "$winetricks_log_dir/winetricks.log"
printf 'argv:' >> "$winetricks_log_dir/winetricks.log"
printf ' %q' "$@" >> "$winetricks_log_dir/winetricks.log"
printf '\n' >> "$winetricks_log_dir/winetricks.log"
exec >> "$winetricks_log_dir/winetricks.log" 2>&1
SCRIPT
        tail -n +2 "$winetricks"
      } > "$winetricks.tmp"
      mv "$winetricks.tmp" "$winetricks"
      chmod +x "$winetricks"

      ${bash}/bin/bash -n "$winetricks"
      grep -Fq 'msvcp140_2.dll_x86' "$winetricks"
      grep -Fq 'msvcp140_2.dll_amd64' "$winetricks"
      grep -Fq 'winetricks.log' "$winetricks"
      grep -Fq 'export PATH="/nix/store/' "$winetricks"

      # Rust's fs::copy preserves the immutable Nix-store mode of
      # hkrpg_patch.dll. Twintail 2.4.0 then unwraps an overwrite failure on the
      # next launch. Repair only registered Sparkle targets before and after the
      # native process until upstream handles permissions itself.
      entrypoint="$out/libexec/twintaillauncher-entrypoint"
      mkdir -p "$(dirname "$entrypoint")"
      cat > "$entrypoint" <<'SCRIPT'
#!@bash@
set -u

fix_sparkle_permissions() {
  local home="''${HOME:-}"
  local data_home
  local db
  local directory
  local target

  [ -n "$home" ] || return 0
  data_home="''${XDG_DATA_HOME:-$home/.local/share}"

  for db in \
    "$data_home/twintaillauncher/storage.db" \
    "$home/.local/share/twintaillauncher/storage.db"
  do
    [ -r "$db" ] || continue

    while IFS= read -r directory; do
      [ -n "$directory" ] || continue
      target="$directory/jsproxy.dll"
      if [ -e "$target" ] && [ ! -w "$target" ]; then
        @chmod@ u+w -- "$target" || true
      fi
    done < <(
      @sqlite3@ -batch -noheader "$db" \
        "SELECT directory FROM install WHERE directory IS NOT NULL AND length(directory) > 0;" \
        2>/dev/null || true
    )

    break
  done
}

fix_sparkle_permissions
status=0
"@launcher@" "$@" || status=$?
fix_sparkle_permissions
exit "$status"
SCRIPT
      substituteInPlace "$entrypoint" \
        --replace-fail '@bash@' '${bash}/bin/bash' \
        --replace-fail '@chmod@' '${coreutils}/bin/chmod' \
        --replace-fail '@sqlite3@' '${sqlite}/bin/sqlite3' \
        --replace-fail '@launcher@' "$out/bin/twintaillauncher"
      chmod +x "$entrypoint"

      ${bash}/bin/bash -n "$entrypoint"
      grep -Fq 'SELECT directory FROM install' "$entrypoint"
      grep -Fq 'jsproxy.dll' "$entrypoint"

      runHook postInstall
    '';

    preFixup = ''
      # SteamRT receives the Nix-store resources read-only. Proton-CachyOS needs
      # DLL copying enabled while Winetricks creates the prefix.
      gappsWrapperArgs+=(
        --prefix PATH : "${runtimePath}"
        --prefix XDG_DATA_DIRS : "${mangohud}/share"
        --prefix PRESSURE_VESSEL_FILESYSTEMS_RO : "/nix/store"
        --set PROTON_DLL_COPY "*"
        --set WINETRICKS_LATEST_VERSION_CHECK "disabled"
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [
          stdenv.cc.cc.lib
          libayatana-appindicator
          libglvnd
          libgbm
          vulkan-loader
          libdrm
          wayland
        ]}"
        --prefix GIO_EXTRA_MODULES : "${glib-networking}/lib/gio/modules"
        --set SSL_CERT_FILE "${cacert}/etc/ssl/certs/ca-bundle.crt"
        --set NIX_SSL_CERT_FILE "${cacert}/etc/ssl/certs/ca-bundle.crt"
      )
    '';

    meta = {
      description = "Multi-platform launcher for anime-styled games";
      homepage = "https://github.com/TwintailTeam/TwintailLauncher";
      license = lib.licenses.gpl3Only;
      mainProgram = "twintaillauncher";
      platforms = [ "x86_64-linux" ];
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    };
  };
in
buildFHSEnv {
  pname = "twintaillauncher";
  inherit version;

  # Match nixpkgs' Steam runtime environment: it deliberately creates a valid
  # 32-/64-bit ld.so.cache at the paths used by Nix glibc before starting any
  # dynamic process. This is required by nested pressure-vessel/libcapsule.
  multiArch = true;
  includeClosures = true;
  privateTmp = false;

  targetPkgs =
    pkgs:
    with pkgs;
    [
      bash
      coreutils
      file
      lsb-release
      pciutils
      glibc_multi.bin
      usbutils
      xdg-utils
      xz
      zenity
    ];

  multiPkgs =
    pkgs:
    with pkgs;
    [
      glibc
      libxcrypt
      libGL
      libdrm
      libgbm
      udev
      libudev0-shim
      libva
      vulkan-loader
      networkmanager
      libcap
    ];

  profile = ''
    export SDL_JOYSTICK_DISABLE_UDEV=1
    export LIBGL_DRIVERS_PATH=/run/opengl-driver/lib/dri:/run/opengl-driver-32/lib/dri
    export __EGL_VENDOR_LIBRARY_DIRS=/run/opengl-driver/share/glvnd/egl_vendor.d:/run/opengl-driver-32/share/glvnd/egl_vendor.d
    export LIBVA_DRIVERS_PATH=/run/opengl-driver/lib/dri:/run/opengl-driver-32/lib/dri
    export VDPAU_DRIVER_PATH=/run/opengl-driver/lib/vdpau:/run/opengl-driver-32/lib/vdpau
  '';

  # SteamRT3+ expects a real /sbin/ldconfig inside nested containers.
  extraBuildCommands = ''
    cp -f $out/usr/{bin,sbin}/ldconfig
  '';

  runScript = "${unwrapped}/libexec/twintaillauncher-entrypoint";

  extraInstallCommands = ''
    ln -s ${unwrapped}/lib $out/lib
    ln -s ${unwrapped}/share $out/share
  '';

  passthru = {
    inherit unwrapped;
  };

  meta = unwrapped.meta;
}
