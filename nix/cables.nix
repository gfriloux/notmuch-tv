# mkCables: television cable channels for notmuch, as plain attrsets that
# pkgs.formats.toml can serialise (Home Manager's programs.television.channels
# takes the same shape).
{
  pkgs,
  notmuch-tv,
  notmuchConfig ? null,
  aerc ? null,
  alot ? null,
  aercAccount ? null,
  withMails ? false,
}: let
  inherit (pkgs) lib;
  q = lib.escapeShellArg;

  ntv = q "${notmuch-tv}/bin/notmuch-tv";
  less = q "${pkgs.less}/bin/less";

  # television formats `{split:\t:N}` itself; the two characters `\t` are what
  # its template syntax expects for a tab.
  field = n: "{split:\\t:${toString n}}";
  id = field 0;

  # television runs commands through $SHELL by default; the commands below are
  # written for bash.
  shell = "bash";
  env = lib.optionalAttrs (notmuchConfig != null) {NOTMUCH_CONFIG = notmuchConfig;};
  specWith = extra: command: let
    e = env // extra;
  in
    {inherit command shell;} // lib.optionalAttrs (e != {}) {env = e;};
  spec = specWith {};

  binary = pkg: name:
    if pkg == "PATH"
    then name
    else q "${pkg}/bin/${name}";

  menu = {
    metadata = {
      name = "notmuch-menu";
      description = "Mailbox statistics for notmuch";
    };
    source =
      spec "${ntv} menu"
      // {
        display = field 1;
        output = id;
        no_sort = true;
      };
    # tv kills preview jobs after 3 s; `preview` computes in the background and
    # caches. tv's own per-entry cache would pin the "Computing…" placeholder.
    preview = spec "${ntv} preview '${id}'" // {cached = false;};
    keybindings.enter = "actions:run";
    actions.run =
      spec "${ntv} run '${id}' | ${less} -R"
      // {
        description = "Open the full output in a pager";
        mode = "fork";
      };
  };

  mailCable = name: description: action:
    {
      metadata = {inherit name description;};
      source =
        spec [
          {
            name = "Unread";
            run = "${ntv} mails unread";
          }
          {
            name = "All";
            run = "${ntv} mails all";
          }
        ]
        // {
          display = "${field 1}  ${field 2}  ${field 3}";
          output = id;
          no_sort = true;
        };
      preview = spec "${ntv} show '${id}'";
    }
    // lib.optionalAttrs (action != null) {
      keybindings.enter = "actions:open";
      actions.open = action;
    };

  # The account name travels in the env table and is quoted at runtime, so no
  # user data is interpolated into the shell text. The single quotes are for
  # aerc's own command parser, which would otherwise split a name on spaces.
  aercAction = let
    setAccount = "a=; [ -n \"$NOTMUCH_TV_AERC_ACCOUNT\" ] && a=\"-a '$NOTMUCH_TV_AERC_ACCOUNT' \"; ";
    runAerc = "${binary aerc "aerc"} \":query $a-n notmuch-tv thread:${id}\"";
  in
    specWith (lib.optionalAttrs (aercAccount != null) {NOTMUCH_TV_AERC_ACCOUNT = aercAccount;}) (setAccount + runAerc)
    // {
      description = "Open the thread in aerc";
      mode = "fork";
    };

  alotAction =
    spec "${binary alot "alot"} ${lib.optionalString (notmuchConfig != null) "-n ${q notmuchConfig} "}search thread:${id}"
    // {
      description = "Open the thread in alot";
      mode = "execute";
    };
in
  {notmuch-menu = menu;}
  // lib.optionalAttrs (aerc != null) {
    notmuch-aerc = mailCable "notmuch-aerc" "Mail threads, opened in aerc" aercAction;
  }
  // lib.optionalAttrs (alot != null) {
    notmuch-alot = mailCable "notmuch-alot" "Mail threads, opened in alot" alotAction;
  }
  // lib.optionalAttrs withMails {
    notmuch-mails = mailCable "notmuch-mails" "Mail threads" null;
  }
