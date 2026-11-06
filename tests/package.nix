# The nix run package and the demo, with a stub in place of television.
{
  pkgs,
  fx,
  tv,
  mkPackage,
  mkDemo,
}: let
  stub = pkgs.writeShellScriptBin "tv" ''
    echo "args: $*"
    echo "config: ''${NOTMUCH_CONFIG:-}"
    echo "cache: ''${XDG_CACHE_HOME:-}"
    if [ -n "''${NOTMUCH_CONFIG:-}" ] && [ -f "$NOTMUCH_CONFIG" ]; then
      ${pkgs.notmuch}/bin/notmuch count '*'
      echo "config-dir: $(dirname "$NOTMUCH_CONFIG")"
      touch "$(dirname "$NOTMUCH_CONFIG")/marker"
    fi
  '';
  package = mkPackage {
    inherit pkgs;
    notmuch-tv = tv;
    television = stub;
  };
  demo = mkDemo {
    inherit pkgs package;
    fixture = fx.fixture;
  };
in
  pkgs.runCommand "check-package" {nativeBuildInputs = [pkgs.coreutils pkgs.gnugrep];} ''
    out_=$TMPDIR/o

    # Package: tv with --cable-dir, notmuch-menu by default, extra args pass through.
    ${package}/bin/notmuch-television >$out_
    grep -q '^args: --cable-dir /nix/store/[^ ]* notmuch-menu$' $out_
    dir=$(sed -n 's/^args: --cable-dir \([^ ]*\) .*/\1/p' $out_)
    for c in notmuch-menu notmuch-aerc notmuch-alot; do
      [ -f $dir/$c.toml ] || { echo "$c.toml missing in $dir" >&2; exit 1; }
    done
    [ ! -e $dir/notmuch-mails.toml ]
    ${package}/bin/notmuch-television notmuch-aerc >$out_
    grep -q 'notmuch-aerc$' $out_

    # Demo: private writable copy of the fixture, NOTMUCH_CONFIG set, channel notmuch-menu.
    export HOME=$TMPDIR
    unset NOTMUCH_CONFIG
    ${demo}/bin/notmuch-tv-demo >$out_
    grep -q 'notmuch-menu$' $out_
    grep -q '^config: /' $out_
    if grep -q '^config: /nix/store' $out_; then echo "demo uses the store fixture" >&2; exit 1; fi
    grep -q "^13$" $out_
    # The copy is writable (the stub wrote a marker) and gone after exit.
    d=$(sed -n 's/^config-dir: //p' $out_)
    # The preview cache lives in the copy too, not in the user's cache.
    grep -qxF "cache: $d/cache" $out_ || { echo "demo cache outside $d" >&2; cat $out_ >&2; exit 1; }
    [ ! -e "$d" ] || { echo "demo left $d behind" >&2; exit 1; }

    touch $out
  ''
