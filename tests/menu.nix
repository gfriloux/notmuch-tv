{
  pkgs,
  fx,
  tv,
}:
pkgs.runCommand "check-menu" {nativeBuildInputs = [tv pkgs.coreutils pkgs.notmuch];} ''
  source ${./lib.sh}
  export NOTMUCH_TV_NOW=2026-06-15
  out_=$TMPDIR/o

  use_fixture ${fx.fixture}

  notmuch-tv menu >$out_
  assert_lines $out_ 14
  [ "$(head -n1 $out_)" = "$(printf 'top-senders\tTop senders')" ]

  notmuch-tv run top-senders >$out_
  [ "$(head -n1 $out_)" = "4 Alice <alice@example.com>" ]
  assert_line $out_ "3 News <news@example.org>"
  assert_line $out_ "2 noreply@example.net"

  notmuch-tv run top-domains >$out_
  [ "$(sed -n 1p $out_)" = "7 example.com" ]
  [ "$(sed -n 2p $out_)" = "4 example.org" ]
  [ "$(sed -n 3p $out_)" = "3 example.net" ]

  notmuch-tv run top-noreply >$out_
  assert_lines $out_ 1
  assert_line $out_ "2 noreply@example.net"

  notmuch-tv run top-newsletters >$out_
  [ "$(head -n1 $out_)" = "3 News <news@example.org>" ]

  notmuch-tv run top-recipients >$out_
  assert_line $out_ "1 alice@example.com"
  assert_line $out_ "1 bob@example.com"

  notmuch-tv run per-year >$out_
  assert_lines $out_ 3
  [ "$(sed -n 1p $out_)" = "2020 1" ]
  [ "$(sed -n 2p $out_)" = "2025 12" ]
  [ "$(sed -n 3p $out_)" = "2026 1" ]

  notmuch-tv run per-month >$out_
  assert_lines $out_ 12
  [ "$(sed -n 1p $out_)" = "2025-07 1" ]
  assert_line $out_ "2025-10 3"
  assert_line $out_ "2026-01 0"
  [ "$(sed -n 12p $out_)" = "2026-06 1" ]

  notmuch-tv run old-unread >$out_
  [ "$(sed -n 1p $out_)" = "1" ]
  sed -n 2p $out_ | grep -q 'Old news'

  notmuch-tv run largest >$out_
  assert_lines $out_ 15
  sed -n 1p $out_ | grep -qE '^[0-9.]+[KMG]?[[:space:]].*/m11\.fixture:2,S$'

  notmuch-tv run attachments >$out_
  grep -qE '^pdf 1 [0-9.]+[KMG]?$' $out_
  assert_line $out_ "zip 0 0"
  assert_line $out_ "video 0 0"

  notmuch-tv run per-tag >$out_
  [ "$(sed -n 1p $out_)" = "12 inbox" ]
  assert_line $out_ "2 sent"
  assert_line $out_ "2 unread"
  assert_line $out_ "1 attachment"
  assert_line $out_ "1 spam"
  [ "$(sort -k1,1nr -s $out_)" = "$(cat $out_)" ]

  notmuch-tv run per-folder >$out_
  [ "$(sed -n 1p $out_)" = "12 INBOX" ]
  assert_line $out_ "2 Sent"
  assert_line $out_ "1 Archive"

  notmuch-tv run largest-threads >$out_
  [ "$(sed -n 1p $out_)" = "3 Project" ]

  notmuch-tv run duplicates >$out_
  [ "$(sed -n 1p $out_)" = "1 messages stored in several files (same Message-Id)" ]
  [ "$(sed -n 2p $out_)" = "" ]
  [ "$(sed -n 3p $out_)" = "2025-01-10  Alice <alice@example.com>  Hello" ]
  # Files in the order notmuch returns them.
  notmuch search --exclude=false --output=files id:m01@fixture.example.com |
    sed -E 's#.*/mail/##; s#/[^/]*$##; s#/(cur|new|tmp)$##; s#^#    #' >$TMPDIR/want-dirs
  [ "$(sort $TMPDIR/want-dirs | paste -sd ,)" = "    Archive,    INBOX" ]
  [ "$(sed -n '4,$p' $out_)" = "$(cat $TMPDIR/want-dirs)" ]
  assert_lines $out_ 5

  rc=0
  notmuch-tv run nope >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ]

  use_fixture ${fx.fixtureEmpty}
  for id in top-senders top-domains top-noreply top-newsletters top-recipients per-year largest; do
    notmuch-tv run $id >$out_
    [ ! -s $out_ ] || { echo "$id not empty on empty db" >&2; exit 1; }
  done

  for id in per-tag per-folder largest-threads; do
    notmuch-tv run $id >$out_
    [ ! -s $out_ ] || { echo "$id not empty on empty db" >&2; exit 1; }
  done
  notmuch-tv run duplicates >$out_
  [ "$(cat $out_)" = "No duplicate messages." ]

  notmuch-tv run old-unread >$out_
  [ "$(sed -n 1p $out_)" = 0 ]
  notmuch-tv run per-month >$out_
  assert_lines $out_ 12
  [ "$(sort -u $out_ | grep -vc ' 0$' || true)" = 0 ]
  notmuch-tv run attachments >$out_
  assert_line $out_ "pdf 0 0"

  # Regression: thousands of distinct senders must not trip SIGPIPE (exit 141)
  # in `... | head` pipelines under pipefail.
  big=$(mktemp -d)
  mkdir -p $big/mail/cur
  for i in $(seq 1 3000); do
    printf 'From: Noreply Sender %s <noreply%s@d%s.example.com>\nTo: r%s@d%s.example.com\nSubject: s%s\nMessage-Id: <b%s@big.example.com>\nDate: Mon, 01 Jan 2024 12:00:00 +0000\n\nunsubscribe\n' \
      $i $i $i $i $i $i $i >$big/mail/cur/m$i:2,S
  done
  printf '[database]\npath=%s/mail\n[user]\nname=Me\nprimary_email=me@example.com\n[new]\ntags=sent\nignore=\n[maildir]\nsynchronize_flags=false\n' $big >$big/config
  export NOTMUCH_CONFIG=$big/config
  notmuch new >/dev/null
  for id in top-senders top-domains top-noreply top-newsletters top-recipients; do
    notmuch-tv run $id >$out_ || { echo "$id exited $? on large db" >&2; exit 1; }
  done
  assert_lines $out_ 15

  # tiny_db <name> <file>...: a maildir holding the given mail files, indexed,
  # with NOTMUCH_CONFIG pointing at it.
  tiny_db() {
    local d=$TMPDIR/$1
    shift
    mkdir -p $d/mail/INBOX/cur $d/mail/INBOX/new $d/mail/INBOX/tmp
    cp "$@" $d/mail/INBOX/cur/
    printf '[database]\npath=%s/mail\n[user]\nname=Me\nprimary_email=me@example.com\n[new]\ntags=inbox\nignore=\n[maildir]\nsynchronize_flags=false\n' $d >$d/config
    export NOTMUCH_CONFIG=$d/config
    notmuch new >/dev/null
  }

  # per-year when the oldest mail is recent: notmuch's summary prints a
  # relative date then ("Today", "Yest.", "May 16"), so it must not be parsed.
  export NOTMUCH_TV_NOW=$(date -u +%Y-%m-%d)
  recent=$(LC_ALL=C date -u -d "$NOTMUCH_TV_NOW -30 days" '+%a, %d %b %Y 12:00:00 +0000')
  printf 'From: R <r@example.com>\nTo: me@example.com\nSubject: recent\nMessage-Id: <r@example.com>\nDate: %s\n\nhi\n' "$recent" >$TMPDIR/recent.eml
  tiny_db recent $TMPDIR/recent.eml
  notmuch-tv run per-year >$out_ || { echo "per-year failed on a recent-only db" >&2; exit 1; }
  assert_lines $out_ 1
  [ "$(cat $out_)" = "$(date -u -d "$NOTMUCH_TV_NOW -30 days" +%Y) 1" ]

  # per-year counts by local year, and so does the start of its range: west of
  # UTC, a mail sent just after New Year UTC belongs to the year before.
  # (EST5 is a POSIX TZ string: no tzdata needed.)
  printf 'From: R <r@example.com>\nTo: me@example.com\nSubject: ny\nMessage-Id: <ny@example.com>\nDate: Thu, 01 Jan 2026 03:00:00 +0000\n\nhi\n' >$TMPDIR/ny.eml
  tiny_db newyear $TMPDIR/ny.eml
  TZ=EST5 NOTMUCH_TV_NOW=2026-06-15 notmuch-tv run per-year >$out_
  [ "$(cat $out_)" = "2025 1" ] || { echo "per-year in EST5: expected '2025 1'" >&2; cat $out_ >&2; exit 1; }

  # per-folder with the database outside the mail root: folder names are
  # relative to database.mail_root.
  d=$TMPDIR/split
  mkdir -p $d/db $d/mail/Lists/cur $d/mail/Lists/new $d/mail/Lists/tmp
  cp $TMPDIR/recent.eml $d/mail/Lists/cur/
  printf '[database]\npath=%s/db\nmail_root=%s/mail\n[user]\nname=Me\nprimary_email=me@example.com\n[new]\ntags=inbox\nignore=\n[maildir]\nsynchronize_flags=false\n' $d $d >$d/config
  export NOTMUCH_CONFIG=$d/config
  notmuch new >/dev/null
  notmuch-tv run per-folder >$out_
  assert_lines $out_ 1
  [ "$(cat $out_)" = "1 Lists" ] || { echo "per-folder not relative to mail_root" >&2; cat $out_ >&2; exit 1; }

  # Control characters in names and subjects (ESC, and U+009B, the one-character
  # CSI) never reach the terminal; UTF-8 text around them survives.
  b64() { printf '=?UTF-8?B?%s?=' "$(printf "$1" | base64 -w0)"; }
  ctl='E\033[31mvil \302\233x été'
  # The quotes keep notmuch's address parser from dropping the sender.
  printf 'From: "%s" <evil@example.com>\nTo: me@example.com\nSubject: %s\nMessage-Id: <evil@example.com>\nDate: Mon, 02 Mar 2020 12:00:00 +0000\n\nhi\n' \
    "$(b64 "$ctl")" "$(b64 "$ctl")" >$TMPDIR/evil-a.eml
  cp $TMPDIR/evil-a.eml $TMPDIR/evil-b.eml
  tiny_db evil $TMPDIR/evil-a.eml $TMPDIR/evil-b.eml
  notmuch tag +unread -- '*'
  for id in top-senders largest-threads old-unread duplicates; do
    notmuch-tv run $id >$out_
    grep -q 'été' $out_ || { echo "$id lost the UTF-8 text" >&2; cat $out_ >&2; exit 1; }
    if grep -q "$(printf '\033')" $out_ || grep -q "$(printf '\302\233')" $out_; then
      echo "$id output has control characters" >&2
      cat -v $out_ >&2
      exit 1
    fi
  done

  touch $out
''
