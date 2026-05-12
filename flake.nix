{
  description = "Hermes Agent";

  inputs = {
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0";
    # nixpkgs-llama tracks a nixpkgs commit that ships llama-cpp >= b8637, which is
    # required for Gemma 4 (gemma4 arch) support.  Used only for the llama-cpp overlay
    # in modules/packages.nix.  Remove once FlakeHub's NixOS/nixpkgs/0 advances past
    # nixpkgs commit a4bf06618f0b5ee50f14ed8f0da77d34ecc19160 (currently at b6981).
    nixpkgs-llama.url = "github:NixOS/nixpkgs/0726a0ecb6d4e08f6adced58726b95db924cef57";
    sops-nix.url = "https://flakehub.com/f/Mic92/sops-nix/0.1.1200";
    disko.url = "https://flakehub.com/f/nix-community/disko/*";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    nixos-anywhere.url = "github:nix-community/nixos-anywhere";
    nixos-anywhere.inputs.nixpkgs.follows = "nixpkgs";
    nixos-anywhere.inputs.disko.follows = "disko";
    hermes-agent.url = "github:NousResearch/hermes-agent";
    hermes-agent.inputs.nixpkgs.follows = "nixpkgs";
    llm-agents.url = "github:numtide/llm-agents.nix";
    llm-agents.inputs.nixpkgs.follows = "nixpkgs";
    git-hooks.url = "https://flakehub.com/f/cachix/git-hooks.nix/*";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-llama,
      determinate,
      sops-nix,
      disko,
      nixos-anywhere,
      hermes-agent,
      llm-agents,
      git-hooks,
      ...
    }@inputs:
    let
      # Dev tools run on the contributor's machine, not the NixOS host.
      # Support both Apple Silicon and x86_64 Linux development environments.
      devSystems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];
      forDevSystems = nixpkgs.lib.genAttrs devSystems;
      # treefmt-nix from llm-agents powers `nix fmt`.
      treefmt-nix = llm-agents.inputs.treefmt-nix;
    in
    {
      nixosConfigurations.nixos-hermes = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs nixpkgs-llama llm-agents; };
        modules = [
          determinate.nixosModules.default
          sops-nix.nixosModules.sops
          disko.nixosModules.default
          hermes-agent.nixosModules.default
          ./hosts/hermes
        ];
      };

      # Expose `nix fmt` for all dev systems.
      # Formats Nix files with nixfmt-rfc-style + deadnix (from ./treefmt.nix).
      formatter = forDevSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
        in
        treefmtEval.config.build.wrapper
      );

      devShells = forDevSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          hooks = self.checks.${system}.pre-commit-check;
        in
        {
          default = pkgs.mkShell {
            packages = hooks.enabledPackages ++ [
              pkgs.sops
              pkgs.prek
            ];
            shellHook = hooks.shellHook;
          };
        }
      );

      checks = forDevSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          vmTests = pkgs.callPackage ./tests {
            inherit sops-nix hermes-agent;
          };
        in
        {
          pre-commit-check = git-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              # Nix formatting
              nixfmt-rfc-style.enable = true;

              # Secret scanning — knows 150+ patterns
              gitleaks = {
                enable = true;
                name = "gitleaks";
                entry = "${pkgs.gitleaks}/bin/gitleaks protect --staged --no-banner --config .gitleaks.toml";
                language = "system";
                pass_filenames = false;
                stages = [ "pre-commit" ];
              };

              # Catches bash pitfalls (set -u, unquoted globs, etc.) if shell scripts are added
              shellcheck.enable = true;

              # YAML validation — inline config to handle dotfile exclusion in nix sandbox
              yamllint = {
                enable = true;
                settings.configuration = ''
                  extends: default
                  rules:
                    document-start: disable
                    truthy: disable
                    line-length:
                      max: 120
                      allow-non-breakable-words: true
                      level: warning
                  ignore: |
                    hosts/hermes/secrets/
                    tests/assets/
                '';
              };

              # GitHub Actions linting
              actionlint.enable = true;

              # Typo detection across all text files
              typos.enable = true;

              # General hygiene
              end-of-file-fixer.enable = true;
              trim-trailing-whitespace.enable = true;
              check-yaml.enable = true;
              check-added-large-files.enable = true;
            };
          };
        }
        // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
          # VM tests — QEMU only available on Linux.
          # Run with: nix build .#checks.x86_64-linux.<name>
          # See AGENTS.md for the testing ladder — use VM tests only for
          # activation script changes.
          inherit (vmTests) activation-github-auth;

          hindsight-service-config =
            let
              hostConfig = self.nixosConfigurations.nixos-hermes.config;
              hindsightUnit = hostConfig.systemd.services.hindsight-embed;
              hindsightInitUnit = hostConfig.systemd.services.hindsight-postgres-init;
              llamaUnit = hostConfig.systemd.services.llama-server;
              envFile = builtins.head (pkgs.lib.toList hindsightUnit.serviceConfig.EnvironmentFile);
              llamaExec = llamaUnit.serviceConfig.ExecStart;
              pgInitExec = hindsightInitUnit.serviceConfig.ExecStart;
              hermesMemory = hostConfig.services.hermes-agent.settings.memory;
              hermesEnv = hostConfig.services.hermes-agent.environment;
              hermesAfter = hostConfig.systemd.services.hermes-agent.after;
              hermesWants = hostConfig.systemd.services.hermes-agent.wants;
              hindsightActivation = hostConfig.system.activationScripts.hermes-hindsight-config.text;
            in
            pkgs.runCommand "hindsight-service-config" { } ''
              set -eu

              grep -qx 'LD_LIBRARY_PATH=.*gcc.*-lib/lib' ${envFile}
              grep -qx 'HINDSIGHT_API_LLM_PROVIDER=openai' ${envFile}
              grep -qx 'HINDSIGHT_API_LLM_BASE_URL=http://10.0.0.102:8317/v1' ${envFile}
              grep -qx 'HINDSIGHT_API_LLM_MODEL=gpt-5.4-mini' ${envFile}
              grep -qx 'HINDSIGHT_API_LLM_TIMEOUT=120' ${envFile}
              ! grep -q '^HINDSIGHT_API_LLM_API_KEY=' ${envFile}
              test '${toString (builtins.elem "cliproxyapi-key:${hostConfig.sops.secrets."cliproxyapi-key".path}" hindsightUnit.serviceConfig.LoadCredential)}' = '1'
              grep -qx 'HINDSIGHT_API_RETAIN_MAX_COMPLETION_TOKENS=4096' ${envFile}
              grep -qx 'HINDSIGHT_API_RETAIN_EXTRACTION_MODE=custom' ${envFile}
              grep -q 'top-level "facts" array' ${envFile}
              grep -q 'extract only the durable lesson' ${envFile}
              grep -qx 'HINDSIGHT_API_EMBEDDINGS_PROVIDER=openai' ${envFile}
              grep -qx 'HINDSIGHT_API_EMBEDDINGS_OPENAI_MODEL=google_gemma-4-E2B-it-Q6_K_L.gguf' ${envFile}
              grep -qx 'HINDSIGHT_API_RERANKER_PROVIDER=rrf' ${envFile}
              grep -qx 'HINDSIGHT_API_DATABASE_URL=postgresql:///hermes?host=/run/postgresql' ${envFile}
              test '${hermesMemory.provider}' = 'hindsight'
              test '${hermesEnv.HINDSIGHT_MODE}' = 'local_external'
              test '${hermesEnv.HINDSIGHT_API_URL}' = 'http://127.0.0.1:8888'
              test '${hermesEnv.HINDSIGHT_BANK_ID}' = 'hermes'
              test '${hermesEnv.HINDSIGHT_BUDGET}' = 'mid'
              test '${toString (builtins.elem "hindsight-embed.service" hermesAfter)}' = '1'
              test '${toString (builtins.elem "hindsight-embed.service" hermesWants)}' = '1'
              grep -q -- 'hermes-hindsight-config.json' <<'EOF'
              ${hindsightActivation}
              EOF
              grep -q -- 'hindsight/config.json' <<'EOF'
              ${hindsightActivation}
              EOF
              grep -q -- 'CREATE EXTENSION IF NOT EXISTS vector' <<'EOF'
              ${pgInitExec}
              EOF
              grep -q -- '--embeddings' <<'EOF'
              ${llamaExec}
              EOF
              grep -q -- '--pooling' <<'EOF'
              ${llamaExec}
              EOF
              grep -q -- 'mean' <<'EOF'
              ${llamaExec}
              EOF
              ! grep -q -- '--chat-template' <<'EOF'
              ${llamaExec}
              EOF

              touch $out
            '';
        }
      );

      # Install-time CLIs exposed as flake apps so they use the same lockfile
      # pin as the NixOS modules. Invoke with:
      #   nix run .#nixos-anywhere -- --flake .#nixos-hermes ...
      #   nix run .#disko -- --mode disko hosts/hermes/disk-config.nix
      apps = forDevSystems (system: {
        nixos-anywhere = {
          type = "app";
          program = "${nixos-anywhere.packages.${system}.nixos-anywhere}/bin/nixos-anywhere";
        };
        disko = {
          type = "app";
          program = "${disko.packages.${system}.disko}/bin/disko";
        };
      });
    };
}
