# The Home Manager module builds the right cables for each mail client setup.
{
  pkgs,
  home-manager,
  module,
}: let
  inherit (pkgs) lib;

  mk = extra:
    home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        module
        {
          home.username = "test";
          home.homeDirectory = "/home/test";
          home.stateVersion = "25.11";
          programs.television.enable = true;
          programs.notmuch.enable = true;
          programs.notmuch-tv.enable = true;
          accounts.email.accounts.test = {
            primary = true;
            address = "test@example.com";
            realName = "Test";
            userName = "test";
            notmuch.enable = true;
          };
        }
        extra
      ];
    };

  aercOn = {
    programs.aerc.enable = true;
    programs.aerc.extraConfig.general.unsafe-accounts-conf = true;
    accounts.email.accounts.test.aerc.enable = true;
  };
  alotOn = {
    programs.alot.enable = true;
    accounts.email.accounts.test.alot.sendMailCommand = "true";
  };

  names = c: builtins.attrNames c.config.programs.television.channels;
  chans = c: c.config.programs.television.channels;

  aerc = mk aercOn;
  alot = mk alotOn;
  both = mk {imports = [aercOn alotOn];};
  neither = mk {};
  # aerc enabled, but its only account is not indexed by notmuch. Home Manager
  # throws on any failed assertion, so evaluation itself must fail.
  noNotmuch = mk {
    imports = [aercOn];
    accounts.email.accounts.test.notmuch.enable = lib.mkForce false;
  };
  noNotmuchRejected = !(builtins.tryEval (builtins.deepSeq (names noNotmuch) true)).success;

  # The module alone, against stubs of the Home Manager options it reads, to see
  # the assertion text (Home Manager hides it behind a throw) and the account choice.
  stub = accounts: aercEnable:
    (lib.evalModules {
      modules = [
        module
        ({lib, ...}: {
          options = {
            assertions = lib.mkOption {type = lib.types.listOf lib.types.raw;};
            home.sessionVariables = lib.mkOption {type = lib.types.attrsOf lib.types.str;};
            programs.television.channels = lib.mkOption {type = lib.types.attrsOf lib.types.raw;};
            programs.aerc = {
              enable = lib.mkEnableOption "aerc";
              package = lib.mkOption {
                type = lib.types.nullOr lib.types.package;
                default = null;
              };
            };
            programs.alot = {
              enable = lib.mkEnableOption "alot";
              package = lib.mkOption {
                type = lib.types.nullOr lib.types.package;
                default = null;
              };
            };
            accounts.email.accounts = lib.mkOption {
              type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
                options = {
                  name = lib.mkOption {default = name;};
                  primary = lib.mkEnableOption "primary";
                  aerc.enable = lib.mkEnableOption "aerc";
                  notmuch.enable = lib.mkEnableOption "notmuch";
                };
              }));
            };
          };
          config = {
            _module.args.pkgs = pkgs;
            programs.notmuch-tv.enable = true;
            programs.aerc.enable = aercEnable;
            accounts.email.accounts = accounts;
          };
        })
      ];
    }).config;
  acct = primary: aerc: notmuch: {
    inherit primary;
    aerc.enable = aerc;
    notmuch.enable = notmuch;
  };
  failedStub = c: map (a: a.message) (lib.filter (a: !a.assertion) c.assertions);

  none = stub {a = acct true true false;} true;
  firstQualifying =
    stub {
      a = acct true true false;
      b = acct false true true;
      c = acct false true true;
    }
    true;
  primaryWins =
    stub {
      a = acct false true true;
      b = acct true true true;
    }
    true;
  # Without aerc, nothing needs an account.
  noAerc = stub {a = acct true false false;} false;

  eq = what: got: want:
    lib.optional (got != want) "${what}: expected ${builtins.toJSON want}, got ${builtins.toJSON got}";

  aercCable = (chans aerc).notmuch-aerc;
  failures = lib.concatLists [
    (eq "aerc only" (names aerc) ["notmuch-aerc" "notmuch-menu"])
    (eq "alot only" (names alot) ["notmuch-alot" "notmuch-menu"])
    (eq "both" (names both) ["notmuch-aerc" "notmuch-alot" "notmuch-menu"])
    (eq "neither" (names neither) ["notmuch-mails" "notmuch-menu"])
    # The notmuch config path is baked in, so tv works without NOTMUCH_CONFIG in its environment.
    (eq "baked config path" (lib.hasSuffix "/notmuch/default/config" aercCable.preview.env.NOTMUCH_CONFIG) true)
    (eq "aerc account" aercCable.actions.open.env.NOTMUCH_TV_AERC_ACCOUNT "test")
    (eq "aerc binary" (lib.hasInfix (builtins.unsafeDiscardStringContext "${pkgs.aerc}/bin/aerc") aercCable.actions.open.command) true)
    (eq "alot -n" (lib.hasInfix "-n /home/test/.config/notmuch/default/config" (chans alot).notmuch-alot.actions.open.command) true)
    (eq "aerc without notmuch rejected" noNotmuchRejected true)
    (eq "assertion text" (lib.any (m: lib.hasInfix "notmuch.enable" m) (failedStub none)) true)
    (eq "no account" none.programs.notmuch-tv.aerc.account null)
    (eq "first qualifying account" firstQualifying.programs.notmuch-tv.aerc.account "b")
    (eq "primary account" primaryWins.programs.notmuch-tv.aerc.account "b")
    (eq "no aerc, no assertion" (failedStub noAerc) [])
    (eq "null package means PATH" (lib.hasInfix "/bin/aerc" firstQualifying.programs.television.channels.notmuch-aerc.actions.open.command) false)
  ];
in
  pkgs.runCommand "check-module" {} (
    if failures == []
    then "touch $out"
    else ''
      cat >&2 <<'MSG'
      ${lib.concatStringsSep "\n" failures}
      MSG
      exit 1
    ''
  )
