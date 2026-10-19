{
  description = "NixOS 26.11-unstable for the HTC Nexus 9 (flounder, NVIDIA Tegra132)";

  inputs = {
    # Local checkout of nixpkgs 26.11-unstable (master).
    # (github.com is unreachable in this environment; the local tree
    # is at 26.11-unstable and used directly.)
    nixpkgs.url = "path:/home/lumiere/workspace/nixpkgs";
  };

  outputs =
    { self, nixpkgs }:
    let
      buildSystem = "x86_64-linux";
    in
    {
      nixosConfigurations.flounder = nixpkgs.lib.nixosSystem {
        system = null; # set modularly via nixpkgs.hostPlatform
        specialArgs = {
          inherit nixpkgs;
        };
        modules = [
          ./configuration/configuration.nix
        ];
      };

      packages.${buildSystem} =
        let
          cfg = self.nixosConfigurations.flounder.config;
        in
        {
          bootimg = cfg.system.build.bootimg;
          bootimg-rescue = cfg.system.build.bootimg-rescue;
          bootimg-highmem = cfg.system.build.bootimg-highmem;
          bootimg-minimal = cfg.system.build.bootimg-minimal;
          rootfs-image = cfg.system.build.rootfs-image;
          kernel = cfg.boot.kernelPackages.kernel;
          kernel-config = cfg.boot.kernelPackages.kernel.configfile;
          toplevel = cfg.system.build.toplevel;
          default = self.packages.${buildSystem}.bootimg;
        };

      # Iterate quickly on the kernel without evaluating all of NixOS.
      devShells.${buildSystem}.default =
        let
          pkgs = import nixpkgs { system = buildSystem; };
        in
        pkgs.mkShell {
          packages = with pkgs; [
            dtc
            mkbootimg-osm0sis
          ];
        };
    };
}
