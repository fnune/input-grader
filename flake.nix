{
  description = "Input grader: frame-accurate feedback on fighting game motion inputs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sf3-decomp = {
      url = "github:gibletto/sfIII3-cps3-decomp";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, sf3-decomp }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # MAME as a pinned test bench. The host's LD_LIBRARY_PATH can leak libraries built
      # against another glibc into it, so every launcher clears it.
      mameRun = pkgs: name: script: pkgs.writeShellApplication {
        inherit name;
        runtimeInputs = [ pkgs.mame pkgs.python3 ];
        text = ''
          unset LD_LIBRARY_PATH
          set_name=''${ROMSET:-sfiii3n}
          python3 -I tools/check_roms.py roms "$set_name"
          mkdir -p build/mame
          video=(-video none)
          if [[ "''${GRADE_SNAPSHOTS:-}" == "1" ]]; then
            export SDL_VIDEODRIVER=offscreen
            mkdir -p build/snaps
            video=(-video soft -window -nomaximize -snapshot_directory build/snaps -snapname "%i" -snapsize 1152x672)
          fi
          exec mame "$set_name" -rompath roms "''${video[@]}" -sound none -nothrottle -skip_gameinfo \
            -nvram_directory build/mame/nvram -cfg_directory build/mame/cfg \
            -autoboot_script ${script}
        '';
      };
    in
    {
      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.luajit
            pkgs.lua5_4
            pkgs.lua54Packages.luacheck
            pkgs.stylua
            pkgs.python3
            pkgs.mame
            pkgs.gcc_multi
          ];
          shellHook = ''
            unset LD_LIBRARY_PATH
            export SF3_DECOMP=${sf3-decomp}
          '';
        };
      });

      apps = forAll (pkgs:
        let
          app = drv: { type = "app"; program = pkgs.lib.getExe drv; };
        in
        {
          # Unit tests on LuaJIT (the Lua 5.1 that FBNeo embeds) and on Lua 5.4.
          test = app (pkgs.writeShellApplication {
            name = "test";
            runtimeInputs = [ pkgs.luajit pkgs.lua5_4 ];
            text = ''
              luajit tests/run.lua
              ${pkgs.lua5_4}/bin/lua tests/run.lua
            '';
          });

          check = app (pkgs.writeShellApplication {
            name = "check";
            runtimeInputs = [ pkgs.luajit pkgs.lua5_4 pkgs.stylua pkgs.lua54Packages.luacheck pkgs.python3 ];
            text = ''
              stylua --check lua tests harness tools input_grader.lua
              luacheck --quiet lua tests harness input_grader.lua
              luajit tests/run.lua
              ${pkgs.lua5_4}/bin/lua tests/run.lua
            '';
          });

          check-roms = app (pkgs.writeShellApplication {
            name = "check-roms";
            runtimeInputs = [ pkgs.python3 ];
            text = ''python3 -I tools/check_roms.py roms "$@"'';
          });

          # Regenerate the command tables from the ROM, labelled and cross-checked by the decomp.
          gen = app (pkgs.writeShellApplication {
            name = "gen";
            runtimeInputs = [ pkgs.python3 pkgs.gcc ];
            text = ''
              python3 -I tools/check_roms.py roms sfiii3
              mkdir -p build
              python3 -I tools/romdump.py roms/sfiii3.zip build/prog.bin
              python3 -I tools/gen_commands.py build/prog.bin ${sf3-decomp} lua/input_grader/games/sfiii3/commands.lua
            '';
          });

          validate = app (mameRun pkgs "validate" "harness/mame/validate.lua");
          grade = app (mameRun pkgs "grade" "harness/mame/grade.lua");
        });

      formatter = forAll (pkgs: pkgs.nixpkgs-fmt);
    };
}
