{
  description = "historical_data — Historical finance database with T pipeline";

  inputs = {
    nixpkgs.url = "github:rstats-on-nix/nixpkgs/2026-04-04";
    flake-utils.url = "github:numtide/flake-utils";
    t-lang.url = "github:b-rodrigues/tlang/v0.51.2";
  };

  nixConfig = {
    extra-substituters = [
      "https://rstats-on-nix.cachix.org"
    ];
    extra-trusted-public-keys = [
      "rstats-on-nix.cachix.org-1:vdiiVgocg6WeJrODIqdprZRUrhi1JzhBnXv7aWI6+F0="
    ];
  };

  outputs = { self, nixpkgs, flake-utils, t-lang }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # R environment
        r-env = pkgs.rWrapper.override {
          packages = with pkgs.rPackages; [
            dplyr
            arrow
            duckdb
            duckplyr
            pointblank
            targets
            crew
            httr2
            jsonlite
            knitr
            reticulate
            testthat
            cli
            rlang
          ];
        };

        # Python environment
        py-env = pkgs.python313.withPackages (ps: with ps; [
          yfinance
          pandas
          pyarrow
          pytest
        ]);

        # Additional tools
        additionalTools = with pkgs; [
          quarto
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            t-lang.packages.${system}.default
            r-env
            py-env
          ] ++ additionalTools;

          shellHook = ''
            echo "=================================================="
            echo "T Project: historical_data"
            echo "=================================================="
            echo ""
            echo "Prototype: AAPL (equity) + BTC (crypto)"
            echo ""
            echo "Commands:"
            echo "  t run src/pipeline.t   - Run the pipeline"
            echo "  t repl                 - Interactive REPL"
            echo ""

            # DuckDB sandbox fix: ensure HOME is writable
            if [ ! -w "$HOME" ]; then
              export HOME=$TMPDIR
            fi

            # Provision T Quarto extension
            mkdir -p _extensions
            expected_quarto_ext="${t-lang.packages.${system}.default}/share/tlang/quarto/tlang"
            quarto_ext_path="_extensions/tlang"
            quarto_ext_stamp="$quarto_ext_path/.tlang-store-path"
            provision_quarto_ext() {
              rm -rf "$quarto_ext_path"
              mkdir -p "$quarto_ext_path"
              cp -R "$expected_quarto_ext"/. "$quarto_ext_path"/
              printf '%s\n' "$expected_quarto_ext" > "$quarto_ext_stamp"
              echo "Provisioned T Quarto extension at _extensions/tlang"
            }
            if [ -L "$quarto_ext_path" ]; then
              provision_quarto_ext
            elif [ -d "$quarto_ext_path" ] && [ -f "$quarto_ext_stamp" ]; then
              current_quarto_ext="$(cat "$quarto_ext_stamp")"
              if [ "$current_quarto_ext" != "$expected_quarto_ext" ]; then
                provision_quarto_ext
              fi
            elif [ -e "$quarto_ext_path" ]; then
              echo "Quarto extension path _extensions/tlang already exists; leaving it unchanged."
            else
              provision_quarto_ext
            fi
          '';
        };
      }
    );
}
