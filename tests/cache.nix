# The preview cache: detached computation, budget, invalidation, isolation.
{
  pkgs,
  fx,
  tv,
}:
pkgs.runCommand "check-cache" {nativeBuildInputs = [tv pkgs.coreutils pkgs.notmuch];} ''
  source ${./lib.sh}
  export NOTMUCH_TV_NOW=2026-06-15
  out_=$TMPDIR/o
  computing="$(printf '%s\n%s' \
    'Computing… this entry takes a while on your mailbox.' \
    'Move to another entry and come back, or press Enter to run it now.')"

  use_fixture ${fx.fixture}
  full=$NOTMUCH_CONFIG
  export XDG_CACHE_HOME=$TMPDIR/cache

  # cached <id>: number of stored outputs for <id>. (stdenv turns on nullglob.)
  cached() {
    local f n=0
    for f in $XDG_CACHE_HOME/notmuch-tv/$1.*.out; do n=$((n + 1)); done
    echo $n
  }

  # 1. No budget: the computing message, then the result once the detached job is done.
  NOTMUCH_TV_PREVIEW_BUDGET=0 notmuch-tv preview largest-threads >$out_
  [ "$(cat $out_)" = "$computing" ] || { echo "expected computing message" >&2; cat $out_ >&2; exit 1; }
  for _ in $(seq 1 300); do
    if [ "$(cached largest-threads)" = 1 ]; then break; fi
    sleep 0.1
  done
  [ "$(cached largest-threads)" = 1 ] || { echo "cache file never appeared" >&2; exit 1; }
  NOTMUCH_TV_PREVIEW_BUDGET=0 notmuch-tv preview largest-threads >$out_
  notmuch-tv run largest-threads >$TMPDIR/want
  diff $TMPDIR/want $out_
  [ "$(sed -n 1p $out_)" = "3 Project" ]

  # 2. Enough budget on a small mailbox: the result directly.
  NOTMUCH_TV_PREVIEW_BUDGET=10 notmuch-tv preview top-senders >$out_
  [ "$(sed -n 1p $out_)" = "4 Alice <alice@example.com>" ]
  if grep -q Computing $out_; then echo "computing message on a fast entry" >&2; exit 1; fi

  # 3. A tag change invalidates the cache.
  NOTMUCH_TV_PREVIEW_BUDGET=10 notmuch-tv preview per-tag >$out_
  if grep -q probe $out_; then echo "probe tag before tagging" >&2; exit 1; fi
  notmuch tag +probe -- id:m01@fixture.example.com
  NOTMUCH_TV_PREVIEW_BUDGET=10 notmuch-tv preview per-tag >$out_
  assert_line $out_ "1 probe"
  # Older entries for the same id are pruned.
  [ "$(cached per-tag)" = 1 ]

  # 4. run fills the cache.
  notmuch-tv run per-folder >$TMPDIR/want
  NOTMUCH_TV_PREVIEW_BUDGET=0 notmuch-tv preview per-folder >$out_
  diff $TMPDIR/want $out_

  # 4b. The reference date is part of the key (same DB, same cache dir).
  NOTMUCH_TV_NOW=2026-06-15 notmuch-tv run per-month >$TMPDIR/june
  NOTMUCH_TV_NOW=2026-08-15 notmuch-tv run per-month >$TMPDIR/august
  [ "$(sed -n 12p $TMPDIR/june)" = "2026-06 1" ]
  [ "$(sed -n 12p $TMPDIR/august)" = "2026-08 0" ]

  # 4c. An entry that exists but can't be read (as when another process prunes
  # it between check and read) is a miss, not an error.
  for f in $XDG_CACHE_HOME/notmuch-tv/per-folder.*.out; do chmod 000 "$f"; done
  notmuch-tv run per-folder >$out_
  diff $TMPDIR/want $out_
  for f in $XDG_CACHE_HOME/notmuch-tv/per-folder.*.out; do chmod 000 "$f"; done
  rc=0
  NOTMUCH_TV_PREVIEW_BUDGET=0 notmuch-tv preview per-folder >$out_ || rc=$?
  [ "$rc" = 0 ]
  [ "$(cat $out_)" = "$computing" ]
  for f in $XDG_CACHE_HOME/notmuch-tv/per-folder.*.out; do chmod 600 "$f"; done

  # 4d. Private cache, even under a permissive umask.
  (
    umask 022
    export XDG_CACHE_HOME=$TMPDIR/cache-perm
    notmuch-tv run top-senders >/dev/null
    NOTMUCH_TV_PREVIEW_BUDGET=10 notmuch-tv preview per-tag >/dev/null
    [ "$(stat -c %a $XDG_CACHE_HOME/notmuch-tv)" = 700 ]
    [ -z "$(find $XDG_CACHE_HOME/notmuch-tv -perm /077)" ] || { find $XDG_CACHE_HOME/notmuch-tv -perm /077 -ls >&2; exit 1; }
  )

  # 4e. Deleting mail invalidates the cache: notmuch new drops the message
  # without bumping the lastmod revision, so the count is part of the key.
  notmuch-tv run top-senders >$out_
  assert_line $out_ "2 noreply@example.net"
  rm "$(dirname $full)"/mail/INBOX/cur/m09.*
  notmuch new >/dev/null
  notmuch-tv run top-senders >$out_
  assert_line $out_ "1 noreply@example.net"

  # 5. Two configs never share an entry.
  use_fixture ${fx.fixtureEmpty}
  export XDG_CACHE_HOME=$TMPDIR/cache
  empty=$NOTMUCH_CONFIG
  NOTMUCH_CONFIG=$full NOTMUCH_TV_PREVIEW_BUDGET=10 notmuch-tv preview top-senders >$TMPDIR/a
  NOTMUCH_CONFIG=$empty NOTMUCH_TV_PREVIEW_BUDGET=10 notmuch-tv preview top-senders >$TMPDIR/b
  [ -s $TMPDIR/a ]
  [ ! -s $TMPDIR/b ] || { echo "empty config got the full config's entry" >&2; cat $TMPDIR/b >&2; exit 1; }

  # 6. Unknown id.
  rc=0
  notmuch-tv preview nope >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ]

  # 7. A failing computation leaves no cache file and shows its error: a mail
  # file removed behind notmuch's back makes `largest` fail (du), DB unchanged.
  export NOTMUCH_CONFIG=$full
  rm "$(dirname $full)"/mail/INBOX/cur/m11.*
  rc=0
  NOTMUCH_TV_PREVIEW_BUDGET=10 notmuch-tv preview largest >$out_ 2>&1 || rc=$?
  [ "$rc" = 0 ]
  if grep -q Computing $out_; then echo "computing message instead of the error" >&2; exit 1; fi
  grep -q m11 $out_ || { echo "error not shown" >&2; cat $out_ >&2; exit 1; }
  [ "$(cached largest)" = 0 ] || { echo "failed run cached" >&2; exit 1; }

  touch $out
''
