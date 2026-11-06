# Cables parse in television and their commands work from a clean environment.
{
  pkgs,
  fx,
  tv,
  mkCables,
}: let
  toml = pkgs.formats.toml {};
  dirOf = name: cables:
    pkgs.linkFarm name (pkgs.lib.mapAttrsToList (n: v: {
        name = "${n}.toml";
        path = toml.generate "${n}.toml" v;
      })
      cables);

  # Cables as the Home Manager module will build them: absolute binaries, a baked config path.
  full = mkCables {
    inherit pkgs;
    notmuch-tv = tv;
    notmuchConfig = "${fx.fixture}/config";
    aerc = pkgs.aerc;
    alot = pkgs.alot;
    aercAccount = "acc";
    withMails = true;
  };
  fullDir = dirOf "cables-full" full;

  # Same shapes with a fake config path, to read the generated text.
  fake = dirOf "cables-fake" (mkCables {
    inherit pkgs;
    notmuch-tv = tv;
    notmuchConfig = "/x/config";
    aerc = pkgs.aerc;
    alot = pkgs.alot;
    aercAccount = "acc";
  });

  # nix run flavour: aerc/alot from PATH, account read at runtime.
  runDir = dirOf "cables-run" (mkCables {
    inherit pkgs;
    notmuch-tv = tv;
    aerc = "PATH";
    alot = "PATH";
  });

  # aerc stand-in that prints its argv, with an account name a shell would mangle.
  stubAerc = pkgs.writeShellScriptBin "aerc" ''printf '%s\n' "$@"'';
  oddAccount = ''Work "Mail" $x `y`'';
  oddDir = dirOf "cables-odd" (mkCables {
    inherit pkgs;
    notmuch-tv = tv;
    aerc = stubAerc;
    aercAccount = oddAccount;
  });

  bare = mkCables {
    inherit pkgs;
    notmuch-tv = tv;
  };
in
  pkgs.runCommand "check-cables" {nativeBuildInputs = [pkgs.television pkgs.python3 pkgs.coreutils pkgs.notmuch pkgs.gnugrep];} ''
    source ${./lib.sh}
    export HOME=$TMPDIR
    out_=$TMPDIR/o

    # Key sets.
    expect() { [ "$1" = "$2" ] || { echo "expected '$2', got '$1': $3" >&2; exit 1; }; }
    expect "${toString (builtins.attrNames bare)}" "notmuch-menu" "bare cables"
    expect "${toString (builtins.attrNames full)}" "notmuch-aerc notmuch-alot notmuch-mails notmuch-menu" "full cables"

    # television parses every generated cable.
    for d in ${fullDir} ${fake} ${runDir}; do
      tv --cable-dir $d list-channels >$out_ 2>&1
      if grep -q 'Failed to parse' $out_; then cat $out_ >&2; exit 1; fi
      for c in notmuch-menu notmuch-aerc; do
        grep -q "$c" $out_ || { echo "$c missing from list-channels of $d" >&2; cat $out_ >&2; exit 1; }
      done
    done
    tv --cable-dir ${fullDir} list-channels 2>&1 | grep -q notmuch-alot
    tv --cable-dir ${fullDir} list-channels 2>&1 | grep -q notmuch-mails

    # Generated text.
    grep -q '/x/config' ${fake}/notmuch-aerc.toml
    grep -q 'NOTMUCH_TV_AERC_ACCOUNT = "acc"' ${fake}/notmuch-aerc.toml
    if grep -q -e '-a acc' ${fake}/notmuch-aerc.toml; then echo "account interpolated into the command" >&2; exit 1; fi
    grep -q '${pkgs.aerc}/bin/aerc' ${fake}/notmuch-aerc.toml
    grep -q -e '-n /x/config' ${fake}/notmuch-alot.toml
    grep -q '${pkgs.alot}/bin/alot' ${fake}/notmuch-alot.toml
    grep -q 'NOTMUCH_TV_AERC_ACCOUNT' ${runDir}/notmuch-aerc.toml
    if grep -q '/nix/store.*/bin/aerc' ${runDir}/notmuch-aerc.toml; then echo "aerc not from PATH" >&2; exit 1; fi
    if grep -q 'NOTMUCH_CONFIG' ${runDir}/notmuch-menu.toml; then echo "NOTMUCH_CONFIG baked into a cable that has no path" >&2; exit 1; fi
    grep -q '${tv}/bin/notmuch-tv' ${runDir}/notmuch-menu.toml
    grep -q '${pkgs.less}/bin/less' ${runDir}/notmuch-menu.toml
    # Menu preview goes through the cache, with tv's own per-entry cache off so
    # coming back to an entry re-runs it.
    python3 -I -c 'import sys, tomllib; p = tomllib.load(open(sys.argv[1], "rb"))["preview"]; assert " preview " in p["command"] and " run " not in p["command"], p; assert p["cached"] is False, p' ${runDir}/notmuch-menu.toml

    # Commands, run the way tv runs them: bash -c with an empty environment plus
    # the cable's own env table, against the fixture.
    run_cable() { # <toml> <section: source|preview> <index> <subst>
      python3 -I - "$@" <<'PY'
    import sys, tomllib, os, subprocess
    path, section, subst = sys.argv[1], sys.argv[2], sys.argv[3]
    d = tomllib.load(open(path, "rb"))
    spec = d
    for k in section.split("."):
        spec = spec[k]
    cmd = spec["command"]
    if isinstance(cmd, list):
        cmd = cmd[int(sys.argv[4]) if len(sys.argv) > 4 else 0]
        cmd = cmd["run"] if isinstance(cmd, dict) else cmd
    cmd = cmd.replace("{split:\\t:0}", subst)
    r = subprocess.run(["${pkgs.bash}/bin/bash", "-c", cmd], env={"HOME": os.environ["HOME"], **{k: v for k, v in os.environ.items() if k == "NO_COLOR"}, **spec.get("env", {})}, capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    sys.stderr.write(r.stderr)
    sys.exit(r.returncode)
    PY
    }

    export NOTMUCH_CONFIG=${fx.fixture}/config
    notmuch-tv() { ${tv}/bin/notmuch-tv "$@"; }
    notmuch-tv mails unread >$TMPDIR/want-unread
    notmuch-tv mails all >$TMPDIR/want-all
    notmuch-tv menu >$TMPDIR/want-menu
    unset NOTMUCH_CONFIG

    for c in aerc alot mails; do
      run_cable ${fullDir}/notmuch-$c.toml source x 0 >$out_
      cmp $out_ $TMPDIR/want-unread
      run_cable ${fullDir}/notmuch-$c.toml source x 1 >$out_
      cmp $out_ $TMPDIR/want-all
      tid=$(cut -f1 $TMPDIR/want-unread | head -n1)
      NO_COLOR=1 run_cable ${fullDir}/notmuch-$c.toml preview "$tid" >$out_
      assert_line $out_ "Subject: Lunch"
    done
    # The account reaches aerc as one intact argument, whatever characters it holds.
    run_cable ${oddDir}/notmuch-aerc.toml actions.open T1 >$out_
    expect "$(cat $out_)" ${pkgs.lib.escapeShellArg '':query -a 'Work "Mail" $x `y`' -n notmuch-tv thread:T1''} "odd account name"
    run_cable ${fullDir}/notmuch-menu.toml source x >$out_
    cmp $out_ $TMPDIR/want-menu
    run_cable ${fullDir}/notmuch-menu.toml preview per-year >$out_
    [ -s $out_ ]

    touch $out
  ''
