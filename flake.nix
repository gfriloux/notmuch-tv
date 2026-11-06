{
  description = "Television cable channels for notmuch";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
  }: let
    systems = ["x86_64-linux" "aarch64-linux"];
    mkCables = import ./nix/cables.nix;
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
  in {
    formatter = forAllSystems (_: pkgs: pkgs.alejandra);

    lib.mkCables = mkCables;

    homeManagerModules.default = import ./modules/home-manager.nix self;
    # Same module under the name newer flakes use.
    homeModules.default = self.homeManagerModules.default;

    packages = forAllSystems (system: pkgs: let
      notmuch-tv = self.packages.${system}.notmuch-tv;
    in {
      notmuch-tv = import ./nix/notmuch-tv.nix {inherit pkgs;};
      default = import ./nix/package.nix {inherit pkgs notmuch-tv;};
      demo = import ./nix/demo.nix {
        inherit pkgs;
        package = self.packages.${system}.default;
        fixture = (import ./tests/fixture.nix {inherit pkgs;}).fixture;
      };
    });

    apps = forAllSystems (system: _: {
      default = {
        type = "app";
        program = "${self.packages.${system}.default}/bin/notmuch-television";
      };
      demo = {
        type = "app";
        program = "${self.packages.${system}.demo}/bin/notmuch-tv-demo";
      };
    });

    checks = forAllSystems (system: pkgs: let
      fx = import ./tests/fixture.nix {inherit pkgs;};
      tv = self.packages.${system}.notmuch-tv;
    in {
      menu = import ./tests/menu.nix {inherit pkgs fx tv;};
      mails = import ./tests/mails.nix {inherit pkgs fx tv;};
      cache = import ./tests/cache.nix {inherit pkgs fx tv;};
      cables = import ./tests/cables.nix {inherit pkgs fx tv mkCables;};
      module = import ./tests/module.nix {
        inherit pkgs home-manager;
        module = self.homeManagerModules.default;
      };
      package = import ./tests/package.nix {
        inherit pkgs fx tv;
        mkPackage = import ./nix/package.nix;
        mkDemo = import ./nix/demo.nix;
      };
      fixture = pkgs.runCommand "check-fixture" {nativeBuildInputs = [pkgs.notmuch pkgs.jq];} ''
        source ${./tests/lib.sh}
        export HOME=$TMPDIR

        use_fixture ${fx.fixture}

        expect() { [ "$1" = "$2" ] || { echo "expected $2, got $1: $3" >&2; exit 1; }; }
        expect "$(notmuch count --exclude=false '*')" 14 "all messages"
        expect "$(notmuch count tag:unread)" 2 "unread"
        expect "$(notmuch count --output=files id:m01@fixture.example.com)" 2 "m01 files"
        expect "$(notmuch count --exclude=false tag:spam)" 1 "spam"

        expect "$(notmuch search --format=json id:m15@fixture.example.com | jq -r '.[0].subject')" 'Price: "50$" $HOME' "m15 subject verbatim"

        use_fixture ${fx.fixtureEmpty}
        expect "$(notmuch count '*')" 0 "empty db"

        touch $out
      '';
    });
  };
}
