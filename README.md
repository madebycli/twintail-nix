# twintail-nix

Native Nix/NixOS packaging for [TwintailLauncher](https://github.com/TwintailTeam/TwintailLauncher). The package uses the official Linux DEB release and supports **x86_64-linux only**. Proton, Wine and Steam Runtime remain managed by TwintailLauncher.

## Restored NixOS runtime fixes

The recovered package preserves the required multi-architecture `buildFHSEnv`, writable shared temporary space, closure inclusion and NixOS graphics paths. It provides a real `ldconfig` inside the FHS environment, exposes `/nix/store` read-only to Pressure Vessel and sets `PROTON_DLL_COPY="*"`.

The packaged Winetricks copy keeps the Wine 11 `vcrun2022` extraction fix for `msvcp140.dll` and `msvcp140_2.dll` on x86 and x64, an immutable Bash shebang, an absolute runtime `PATH`, and persistent diagnostics under the user's cache directory.

Before and after the native launcher runs, the wrapper reads only registered install directories from Twintail's SQLite database and makes an existing non-writable `jsproxy.dll` user-writable. It does not recursively scan the home directory.

## Install

```bash
nix profile add github:madebycli/twintail-nix#twintaillauncher
twintaillauncher
```

Run without installing:

```bash
nix run github:madebycli/twintail-nix#twintaillauncher
```

Upgrade and remove:

```bash
nix profile upgrade --all --refresh
nix profile remove twintail-nix
```

Use `nix profile list` to confirm the exact profile entry name before removal.

## NixOS module

```nix
{
  inputs.twintail-nix.url = "github:madebycli/twintail-nix";

  outputs = { nixpkgs, twintail-nix, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        twintail-nix.nixosModules.default
        { programs.twintaillauncher.enable = true; }
      ];
    };
  };
}
```

The module enables GameMode and Gamescope by default. They can still be overridden in the system configuration.

## Validate a checkout

```bash
nix flake show
nix flake check --print-build-logs
nix build .#twintaillauncher --print-build-logs
```

The CI additionally checks the FHS environment, Winetricks patch markers and targeted `jsproxy.dll` repair wrapper.

## Updating the upstream release

`scripts/update.py` discovers the latest official x86_64 DEB and updates `flake.nix`. It intentionally does not commit or push. Run it manually, regenerate `flake.lock`, review the diff and execute the full checks before publishing an update.

## Data and limitations

Twintail user data, downloaded games, runners and Steam Runtime files are not part of the Nix package. A real graphical NixOS session is still required to validate tray integration, downloads, Proton launches, Gamescope and MangoHud end to end. Other Linux distributions should use legitimate upstream installation methods; this repository provides Nix/NixOS integration only.

See [NOTICE.md](NOTICE.md) for third-party licensing notes.
