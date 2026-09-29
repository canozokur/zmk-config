{
  description = "Development shell for building ZMK firmware locally";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Zephyr version ZMK main currently builds against — keep in sync with the
    # `zephyr` revision in zmkfirmware/zmk's app/west.yml (imported through
    # config/west.yml). This pins zephyr-nix's pythonEnv to the right deps.
    zephyr.url = "github:zmkfirmware/zephyr/v4.1.0+zmk-fixes";
    zephyr.flake = false;

    zephyr-nix = {
      url = "github:nix-community/zephyr-nix";
      inputs.zephyr.follows = "zephyr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, zephyr-nix, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      mkEnv =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          zephyr = zephyr-nix.packages.${system};

          # ARM toolchain only — the Piantor Pro BT's nRF52840 is a Cortex-M4F.
          # SDK 0.16.x matches what ZMK's dev container ships for Zephyr 4.1.
          zephyr-sdk = zephyr.sdk-0_16.override {
            targets = [ "arm-zephyr-eabi" ];
          };

          # Build the firmware halves, mirroring the CI matrix in build.yaml.
          # Available as `build-fw` inside the dev shell, and standalone via
          # `nix run .#build-fw` (env vars are baked in there, since the SDK's
          # setup hook only runs in interactive shells).
          build-fw = pkgs.writeShellApplication {
            name = "build-fw";
            runtimeInputs = [
              zephyr.pythonEnv # provides west
              pkgs.cmake
              pkgs.ninja
              pkgs.dtc
              pkgs.gcc
              pkgs.gperf
              pkgs.ccache
            ];
            text = ''
              export ZEPHYR_TOOLCHAIN_VARIANT="zephyr"
              export ZEPHYR_SDK_INSTALL_DIR="${zephyr-sdk}"
              export PYTHONPATH="${zephyr.pythonEnv}/${zephyr.pythonEnv.sitePackages}"

              case "''${1:-both}" in
                left) targets=(left) ;;
                right) targets=(right) ;;
                both) targets=(left right) ;;
                *)
                  echo "usage: build-fw [left|right|both]" >&2
                  exit 1
                  ;;
              esac

              if [ ! -d .west ]; then
                echo "error: no west workspace here" >&2
                exit 1
              fi

              for side in "''${targets[@]}"; do
                echo "==> Building piantor_pro_bt_''${side}"
                west build -s zmk/app -d "build/''${side}" -b "piantor_pro_bt_''${side}" -- \
                  -DSHIELD=nice_view -DZMK_CONFIG="$PWD/config"
                echo "==> Firmware: build/''${side}/zephyr/zmk.uf2"
              done
            '';
          };
        in
        {
          inherit build-fw;
          devShell = pkgs.mkShellNoCC {
            packages = [
              zephyr-sdk
              zephyr.pythonEnv # python + west + all zephyr build scripts' deps
              build-fw
              pkgs.cmake
              pkgs.ninja
              pkgs.dtc
              pkgs.gcc
              pkgs.gperf
              pkgs.ccache
            ];

            env = {
              ZEPHYR_TOOLCHAIN_VARIANT = "zephyr";
              # Let zephyr's west commands import zephyr's python modules.
              PYTHONPATH = "${zephyr.pythonEnv}/${zephyr.pythonEnv.sitePackages}";
            };

            shellHook = ''
              # Register the Zephyr CMake package so `find_package(Zephyr)` works
              # (same as the `west zephyr-export` step in ZMK's native setup docs).
              # No-op until `west init -l config` has been run once.
              if [ -d .west ]; then
                west zephyr-export >/dev/null 2>&1 || true
              fi

              echo "ZMK build environment ready."
              echo
              echo "First-time setup:"
              echo "  west init -l config && west update"
              echo
              echo "Build firmware (same args as CI):"
              echo "  build-fw [left|right|both]"
              echo
              echo "Firmware lands in build/{left,right}/zephyr/zmk.uf2"
            '';
          };
        };
    in
    {
      devShells = forAllSystems (system: {
        default = (mkEnv system).devShell;
      });

      packages = forAllSystems (system: {
        build-fw = (mkEnv system).build-fw;
      });

      apps = forAllSystems (system: {
        build-fw = {
          type = "app";
          program = "${(mkEnv system).build-fw}/bin/build-fw";
        };
      });
    };
}
