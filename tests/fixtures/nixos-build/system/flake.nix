# A flake configuration for tests/system/nixos/build.sh (@REPO@: the checkout, put in by it)
{
  inputs.h2s-shell.url = "path:@REPO@";
  inputs.nixpkgs.follows = "h2s-shell/nixpkgs";
  outputs = { nixpkgs, h2s-shell, ... }: {
    nixosConfigurations.fixture = nixpkgs.lib.nixosSystem {
      modules = [ h2s-shell.nixosModules.default ./build.nix ];
    };
  };
}
