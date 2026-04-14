{
  description = "Hermes Agent";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    sops-nix.url = "https://flakehub.com/f/Mic92/sops-nix/0.1.1200";
    hermes-agent.url = "github:NousResearch/hermes-agent";
    hermes-agent.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, determinate, sops-nix, hermes-agent, ... }@inputs: {
    nixosConfigurations.nixos-hermes = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        sops-nix.nixosModules.sops
        hermes-agent.nixosModules.default
        ./hosts/hermes
      ];
    };
  };
}
