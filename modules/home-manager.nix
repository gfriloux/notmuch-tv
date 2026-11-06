# programs.notmuch-tv: television cables for notmuch, wired to the mail clients
# Home Manager already configures.
self: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.notmuch-tv;

  # Accounts aerc can open through its notmuch backend: both modules enabled.
  qualifying = lib.filter (a: a.aerc.enable && a.notmuch.enable) (lib.attrValues config.accounts.email.accounts);
  primary = lib.filter (a: a.primary) qualifying;
  defaultAccount =
    if primary != []
    then (lib.head primary).name
    else if qualifying != []
    then (lib.head qualifying).name
    else null;

  # A null package means the client is installed elsewhere: resolve it from PATH.
  pkgOrPath = pkg:
    if pkg == null
    then "PATH"
    else pkg;
in {
  options.programs.notmuch-tv = {
    enable = lib.mkEnableOption "television cables for notmuch";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.notmuch-tv;
      defaultText = lib.literalExpression "notmuch-tv.packages.\${system}.notmuch-tv";
      description = "The notmuch-tv package the cables call.";
    };

    aerc = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = config.programs.aerc.enable;
        defaultText = lib.literalExpression "config.programs.aerc.enable";
        description = "Add a cable that opens threads in aerc.";
      };
      account = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = defaultAccount;
        defaultText = lib.literalMD "the primary account with `aerc.enable` and `notmuch.enable`, else the first such account";
        description = "aerc account used to open threads. It needs the notmuch backend, which Home Manager sets up when the account has `notmuch.enable`.";
      };
    };

    alot.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.programs.alot.enable;
      defaultText = lib.literalExpression "config.programs.alot.enable";
      description = "Add a cable that opens threads in alot.";
    };

    notmuchConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = config.home.sessionVariables.NOTMUCH_CONFIG or null;
      defaultText = lib.literalExpression "config.home.sessionVariables.NOTMUCH_CONFIG or null";
      description = "Path of the notmuch config baked into the cables, so they work without NOTMUCH_CONFIG in television's environment.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.aerc.enable || cfg.aerc.account != null;
        message = "programs.notmuch-tv.aerc.enable needs an aerc account with notmuch: set `notmuch.enable = true` on an `accounts.email.accounts.<name>` that has `aerc.enable = true`, or set programs.notmuch-tv.aerc.account.";
      }
    ];

    programs.television.channels = self.lib.mkCables {
      inherit pkgs;
      notmuch-tv = cfg.package;
      notmuchConfig = cfg.notmuchConfig;
      aerc =
        if cfg.aerc.enable
        then pkgOrPath config.programs.aerc.package
        else null;
      alot =
        if cfg.alot.enable
        then pkgOrPath config.programs.alot.package
        else null;
      aercAccount = cfg.aerc.account;
      withMails = !(cfg.aerc.enable || cfg.alot.enable);
    };
  };
}
