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
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          zephyr = zephyr-nix.packages.${system};

          # ARM toolchain only — the Piantor Pro BT's nRF52840 is a Cortex-M4F.
          # SDK 0.16.x matches what ZMK's dev container ships for Zephyr 4.1.
          zephyr-sdk = zephyr.sdk-0_16.override {
            targets = [ "arm-zephyr-eabi" ];
          };
        in
        {
          default = pkgs.mkShellNoCC {
            packages = [
              zephyr-sdk
              zephyr.pythonEnv # python + west + all zephyr build scripts' deps
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
              echo "  west build -s zmk/app -d build/left -b piantor_pro_bt_left -- -DSHIELD=nice_view -DZMK_CONFIG=\"$PWD/config\""
              echo "  west build -s zmk/app -d build/right -b piantor_pro_bt_right -- -DSHIELD=nice_view -DZMK_CONFIG=\"$PWD/config\""
              echo
              echo "Firmware lands in build/{left,right}/zephyr/zmk.uf2"
            '';
          };
        }
      );
    };
}