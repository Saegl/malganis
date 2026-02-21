{
  description = "Malganis VPS NixOS config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = {nixpkgs, ...}: {
    nixosConfigurations."malganis" = nixpkgs.lib.nixosSystem {
      modules = [./configuration.nix];
    };
  };
}
