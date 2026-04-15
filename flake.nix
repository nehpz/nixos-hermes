{
  description = "Hermes Agent";

  inputs = {
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0";
    sops-nix.url = "https://flakehub.com/f/Mic92/sops-nix/0.1.1200";
    hermes-agent.url = "github:NousResearch/hermes-agent";
    hermes-agent.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      determinate,
      sops-nix,
      hermes-agent,
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
    in
    {
      nixosConfigurations.nixos-hermes = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          determinate.nixosModules.default
          sops-nix.nixosModules.sops
          hermes-agent.nixosModules.default
          ./hosts/hermes
        ];
      };

      devShells = forDevSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.prek
              pkgs.nixfmt-rfc-style
              pkgs.sops
            ];
            shellHook = ''
              prek install --hook-type pre-commit 2>/dev/null || true
              prek install --hook-type pre-push 2>/dev/null || true
            '';
          };
        }
      );
    };
}
