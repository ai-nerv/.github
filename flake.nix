{
  description = "nerv: magi, casper, melchior and balthasar from one flake";

  nixConfig = {
    extra-substituters = [ "https://ai-nerv.cachix.org" ];
    extra-trusted-public-keys = [
      "ai-nerv.cachix.org-1:1Wycl/383z79Nvh7ELU2jlycVzOqJyy1PGajS9caDBY="
    ];
  };

  # The four member flakes, nothing followed; `flake.lock` holds the revisions the submodules pin.
  inputs = {
    magi.url = "github:ai-nerv/magi";
    casper.url = "github:ai-nerv/casper";
    melchior.url = "github:ai-nerv/melchior";
    balthasar.url = "github:ai-nerv/balthasar";
  };

  outputs =
    { self, magi, casper, melchior, balthasar }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      members = { inherit magi casper melchior balthasar; };
      forAll = f: builtins.listToAttrs (map (system: { name = system; value = f system; }) systems);
      each = system: builtins.mapAttrs (name: flake: flake.packages.${system}.${name}) members;
      app = pkg: name: { type = "app"; program = "${pkg}/bin/${name}"; };
    in
    {
      packages = forAll (
        system:
        let
          pkgs = magi.inputs.nixpkgs.legacyPackages.${system};
          programs = each system;
        in
        programs
        // {
          default = pkgs.symlinkJoin {
            name = "nerv";
            paths = builtins.attrValues programs;
          };
        }
      );

      apps = forAll (
        system:
        let
          programs = each system;
        in
        builtins.mapAttrs (name: pkg: app pkg name) programs
        // {
          default = app programs.magi "magi";
        }
      );

      checks = forAll (system: { nerv = self.packages.${system}.default; });
    };
}
