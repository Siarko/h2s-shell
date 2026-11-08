{
  description = "h2s-shell: a desktop shell for Hyprland, built with Quickshell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # The release the shell is developed against on Arch; nixpkgs lags behind (0.3.0)
    quickshell = {
      url = "git+https://git.outfoxxed.me/quickshell/quickshell?ref=refs/tags/v0.3.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, quickshell }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forEachSystem = function: nixpkgs.lib.genAttrs systems
        (system: function nixpkgs.legacyPackages.${system} system);
      # The one place the number lives is singletons/Version.qml
      versionNumber = builtins.head (builtins.match
        ''.*readonly property string number: "([^"]+)".*''
        (builtins.readFile ./singletons/Version.qml));
    in
    {
      packages = forEachSystem (pkgs: system: rec {
        h2s-shell = pkgs.callPackage ./nix/package.nix {
          quickshell = quickshell.packages.${system}.default;
          version = versionNumber + (if self ? shortRev then "+" + self.shortRev else "");
        };
        default = h2s-shell;
      });

      nixosModules.default = import ./nix/module.nix self;
    };
}
