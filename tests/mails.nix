{
  pkgs,
  fx,
  tv,
}: let
  # tvWith {notmuch = stub;}: the package with a runtime dependency replaced.
  tvWith = args: import ../nix/notmuch-tv.nix ({inherit pkgs;} // args);

  # notmuch search that prints its first thread, then waits for a line on
  # the $GATE fifo before printing the rest.
  slowNotmuch = pkgs.writeShellScriptBin "notmuch" ''
    obj() { printf '{"thread": "%s", "timestamp": 1700000000, "authors": "A", "subject": "S%s"}' "$1" "$1"; }
    printf '['; obj 01; printf ',\n'
    read -r _ <"$GATE"
    obj 02; printf ']\n'
  '';
  tvSlow = tvWith {notmuch = slowNotmuch;};

  # w3m that logs each call to $W3M_LOG and prints 30 lines.
  loggingW3m = pkgs.writeShellScriptBin "w3m" ''
    echo call >>"$W3M_LOG"
    cat >/dev/null
    for i in $(seq 30); do echo "line $i"; done
  '';
  tvW3m = tvWith {w3m = loggingW3m;};
in
  pkgs.runCommand "check-mails" {nativeBuildInputs = [tv pkgs.coreutils pkgs.gawk pkgs.notmuch pkgs.gnused pkgs.gnugrep];} ''
          source ${./lib.sh}
          out_=$TMPDIR/o
          tab=$(printf '\t')

          export NO_COLOR=1
          use_fixture ${fx.fixture}

          notmuch-tv mails unread >$out_
          assert_lines $out_ 2
          [ "$(sed -n 1p $out_ | cut -f2-4)" = "$(printf '2026-06-01\tAlice\tLunch')" ]
          [ "$(sed -n 2p $out_ | cut -f4)" = "Old news" ]
          tid=$(sed -n 1p $out_ | cut -f1)
          case "$tid" in thread:*|"") echo "bad thread id '$tid'" >&2; exit 1;; esac

          notmuch-tv mails all >$out_
          assert_lines $out_ 10
          [ "$(awk -F'\t' 'NF != 4' $out_ | wc -l)" = 0 ]
          [ "$(sed -n 1p $out_ | cut -f4)" = "Lunch" ]
          if grep -q 'Receipt 2' $out_; then echo "spam thread listed" >&2; exit 1; fi
          [ "$(grep 'Price' $out_ | cut -f4)" = 'Price: "50$" $HOME' ]
          [ "$(grep -c 'Lettre d.été' $out_)" = 1 ]
          grep -q "Lettre d'été" $out_

          notmuch-tv show "$tid" >$out_
          assert_line $out_ "Subject: Lunch"
          [ "$(grep -c "" $out_)" -le 500 ]

          export TZ=UTC
          sep=$(printf '─%.0s' $(seq 60))

          # Project thread: three messages, newest first, no notmuch text markers.
          ptid=$(notmuch search --output=threads 'id:m02@fixture.example.com' | sed 's/^thread://')
          notmuch-tv show "$ptid" >$out_
          for marker in 'header{' 'part{' 'body{'; do
            if grep -qF "$marker" $out_; then echo "marker $marker in show output" >&2; exit 1; fi
          done
          [ "$(grep -c '^Date:' $out_)" = 3 ]
          [ "$(grep '^Date:' $out_ | tr -s ' ' | paste -sd'|')" = 'Date: 2025-02-12 12:00|Date: 2025-02-11 12:00|Date: 2025-02-10 12:00' ]
          [ "$(grep -cxF "$sep" $out_)" = 3 ]
          grep -qxF 'From:    Alice <alice@example.com>' $out_
          grep -q '^Tags:    ' $out_
          grep -qxF 'Subject: Project' $out_
          [ "$(sed -n 1p $out_)" = "$sep" ]
          [ "$(awk 'p == "" && $0 == "" && NR > 1 { n++ } { p = $0 } END { print n + 0 }' $out_)" = 0 ]

          itid=$(notmuch search --output=threads 'id:m11@fixture.example.com' | sed 's/^thread://')
          notmuch-tv show "$itid" >$out_
          grep -qF '[attachment: invoice.pdf, application/pdf,' $out_

          ctid=$(notmuch search --output=threads 'id:m15@fixture.example.com' | sed 's/^thread://')
          notmuch-tv show "$ctid" >$out_
          grep -qxF 'Subject: Price: "50$" $HOME' $out_

          ltid=$(notmuch search --output=threads 'id:m08@fixture.example.com' | sed 's/^thread://')
          notmuch-tv show "$ltid" >$out_
          grep -qxF "Subject: Lettre d'été" $out_

          # Tiny separate databases: HTML-only mail and a mail with escape codes.
          mkdb() {
            local d=$TMPDIR/$1
            mkdir -p $d/mail/cur $d/mail/new $d/mail/tmp
            printf '%s\n' "Content-Type: $2" 'From: X <x@example.com>' 'To: me@example.com' \
              'Subject: T' 'Date: Mon, 10 Feb 2025 12:00:00 +0000' 'Message-ID: <t@example.com>' \
              'MIME-Version: 1.0' "" "$3" >$d/mail/cur/t:2,S
            printf '[database]\npath=%s\n[user]\nname=Me\nprimary_email=me@example.com\n[new]\ntags=inbox\nignore=\n[search]\nexclude_tags=spam\n[maildir]\nsynchronize_flags=false\n' $d/mail >$d/config
            NOTMUCH_CONFIG=$d/config notmuch new >/dev/null
            NOTMUCH_CONFIG=$d/config notmuch search --output=threads '*' | sed 's/^thread://'
          }
          htid=$(mkdb html 'text/html; charset=UTF-8' '<p>Hello <b>HTML</b></p>')
          NOTMUCH_CONFIG=$TMPDIR/html/config notmuch-tv show "$htid" >$out_
          grep -q 'Hello HTML' $out_
          if grep -q '<p>' $out_; then echo "html tags in output" >&2; exit 1; fi

          # A long thread of HTML-only mails: w3m stops once the 500 lines are out.
        d=$TMPDIR/long
        mkdir -p $d/mail/cur $d/mail/new $d/mail/tmp
        for i in $(seq 1 60); do
          {
            printf '%s\n' 'Content-Type: text/html; charset=UTF-8' 'From: X <x@example.com>' 'Subject: long' \
              "Date: Mon, 10 Feb 2025 12:$(printf %02d $i):00 +0000" "Message-ID: <long$i@example.com>" 'MIME-Version: 1.0'
            if [ $i -gt 1 ]; then printf 'In-Reply-To: <long1@example.com>\nReferences: <long1@example.com>\n'; fi
            printf '\n<p>message %s</p>\n' $i
          } >$d/mail/cur/long$i:2,S
        done
        printf '[database]\npath=%s\n[user]\nname=Me\nprimary_email=me@example.com\n[new]\ntags=inbox\nignore=\n[maildir]\nsynchronize_flags=false\n' $d/mail >$d/config
        NOTMUCH_CONFIG=$d/config notmuch new >/dev/null
        longtid=$(NOTMUCH_CONFIG=$d/config notmuch search --output=threads '*' | sed 's/^thread://')
        [ "$(echo "$longtid" | wc -l)" = 1 ]
        export W3M_LOG=$TMPDIR/w3m.log
        NOTMUCH_CONFIG=$d/config ${tvW3m}/bin/notmuch-tv show "$longtid" >$out_
        assert_lines $out_ 500
        calls=$(grep -c "" $W3M_LOG)
        # 38 lines per message: the 500th line is in the 14th.
        [ "$calls" -le 14 ] || { echo "w3m called $calls times for a 500-line preview" >&2; exit 1; }
        unset W3M_LOG

        etid=$(mkdb esc 'text/plain; charset=UTF-8' "$(printf 'a \033[31mRED\033[0m b')")
          NOTMUCH_CONFIG=$TMPDIR/esc/config notmuch-tv show "$etid" >$out_
          grep -q 'RED' $out_
          [ "$(grep -c "$(printf '\033')" $out_ || true)" = 0 ]

          c1tid=$(mkdb c1 'text/plain; charset=UTF-8' "$(printf 'a \302\233 31m été')")
          NOTMUCH_CONFIG=$TMPDIR/c1/config notmuch-tv show "$c1tid" >$out_
          grep -q 'été' $out_
          [ "$(grep -c "$(printf '\302\233')" $out_ || true)" = 0 ]

          # Colours (NO_COLOR empty counts as unset).
          esc=$(printf '\033')
          plain_=$TMPDIR/plain
          notmuch-tv show "$ptid" >$plain_
          if grep -q "$esc" $plain_; then echo "ESC in NO_COLOR output" >&2; exit 1; fi
          NO_COLOR= notmuch-tv show "$ptid" >$out_
          [ "$(sed -n 1p $out_)" = "$esc[2m$sep$esc[0m" ]
          grep -q "^$esc\[1mFrom:$esc\[0m" $out_
          grep -qF "$esc[1mSubject:$esc[0m $esc[1mProject$esc[0m" $out_
          [ "$(grep -c "" $out_)" = "$(grep -c "" $plain_)" ]
          [ "$(sed "s/$esc\[[0-9]*m//g" $out_)" = "$(cat $plain_)" ]

          NO_COLOR= notmuch-tv show "$itid" >$out_
          grep -q "^$esc\[2m\[attachment: invoice.pdf, application/pdf,.*\]$esc\[0m$" $out_

          qtid=$(mkdb quote 'text/plain; charset=UTF-8' "$(printf '> one\n>> two\n> > three\n>>> four\nplain')")
          NOTMUCH_CONFIG=$TMPDIR/quote/config NO_COLOR= notmuch-tv show "$qtid" >$out_
          grep -qxF "$esc[32m> one$esc[0m" $out_
          grep -qxF "$esc[36m>> two$esc[0m" $out_
          grep -qxF "$esc[36m> > three$esc[0m" $out_
          grep -qxF "$esc[33m>>> four$esc[0m" $out_
          grep -qxF "plain" $out_

          stid=$(mkdb sig 'text/plain; charset=UTF-8' "$(printf 'hello\n-- \nSig line')")
          NOTMUCH_CONFIG=$TMPDIR/sig/config NO_COLOR= notmuch-tv show "$stid" >$out_
          grep -qxF "hello" $out_
          grep -qxF "$esc[2m-- $esc[0m" $out_
          grep -qxF "$esc[2mSig line$esc[0m" $out_

          # A signature ends with its message: blank lines inside it and the blank line
      # before the next message are plain empty lines, and the next body is not dim.
      d=$TMPDIR/sig2
      mkdir -p $d/mail/cur $d/mail/new $d/mail/tmp
      printf 'From: X <x@example.com>\nSubject: s\nDate: Mon, 10 Feb 2025 12:00:00 +0000\nMessage-ID: <old@example.com>\n\nolder body\n' >$d/mail/cur/old:2,S
      printf 'From: X <x@example.com>\nSubject: s\nDate: Mon, 10 Feb 2025 13:00:00 +0000\nMessage-ID: <new@example.com>\nIn-Reply-To: <old@example.com>\n\nnewer body\n-- \nSig\n\nmore sig\n' >$d/mail/cur/new:2,S
      printf '[database]\npath=%s\n[user]\nname=Me\nprimary_email=me@example.com\n[new]\ntags=inbox\nignore=\n[maildir]\nsynchronize_flags=false\n' $d/mail >$d/config
      NOTMUCH_CONFIG=$d/config notmuch new >/dev/null
      s2tid=$(NOTMUCH_CONFIG=$d/config notmuch search --output=threads '*' | sed 's/^thread://')
      NOTMUCH_CONFIG=$d/config NO_COLOR= notmuch-tv show "$s2tid" >$out_
      grep -qxF "$esc[2mmore sig$esc[0m" $out_
      grep -qxF "older body" $out_
      if grep -qxF "$esc[2m$esc[0m" $out_; then echo "styled empty line" >&2; cat -v $out_ >&2; exit 1; fi
      [ "$(grep -cx "" $out_)" = 4 ] || { echo "expected 4 empty lines" >&2; cat -v $out_ >&2; exit 1; }

      # Marker bytes (\002S, \001) in mail data are dropped, never interpreted.
      d=$TMPDIR/markers
      mkdir -p $d/mail/cur $d/mail/new $d/mail/tmp
      {
        printf '%s\n' 'From: "=?UTF-8?Q?=02SFrom?=" <x@example.com>' 'Subject: =?UTF-8?Q?=02SSubj?=' \
          'Date: Mon, 10 Feb 2025 12:00:00 +0000' 'Message-ID: <markers@example.com>' 'MIME-Version: 1.0' \
          'Content-Type: multipart/mixed; boundary="b"' "" '--b' 'Content-Type: text/plain; charset=UTF-8' ""
        printf '\002Sbody one\n\001Ym9keQ==\n\002Hx: y\n'
        printf '%s\n' '--b' 'Content-Type: text/plain'
        printf 'Content-Disposition: attachment; filename*=UTF-8\047\047%%02Sa.txt\n'
        printf '%s\n' "" 'att' '--b--'
      } >$d/mail/cur/m:2,S
      printf '[database]
    path=%s
    [user]
    name=Me
    primary_email=me@example.com
    [new]
    tags=inbox
    ignore=
    [maildir]
    synchronize_flags=false
    ' $d/mail >$d/config
      NOTMUCH_CONFIG=$d/config notmuch new >/dev/null
      mtid=$(NOTMUCH_CONFIG=$d/config notmuch search --output=threads '*' | sed 's/^thread://')
      NOTMUCH_CONFIG=$d/config NO_COLOR= notmuch-tv show "$mtid" >$out_
      if grep -q "$(printf '[]')" $out_; then echo "marker bytes in output" >&2; cat -v $out_ >&2; exit 1; fi
      grep -qxF "$esc[1mFrom:$esc[0m    \"SFrom\" <x@example.com>" $out_ || { cat -v $out_ >&2; exit 1; }
      grep -qxF "$esc[1mSubject:$esc[0m $esc[1mSSubj$esc[0m" $out_
      grep -qxF "Sbody one" $out_
      grep -qxF "Ym9keQ==" $out_
      grep -qxF "Hx: y" $out_
      grep -q "^$esc\[2m\[attachment: Sa.txt, text/plain.*\]$esc\[0m$" $out_ || { cat -v $out_ >&2; exit 1; }
      [ "$(grep -cxF "$esc[2m$sep$esc[0m" $out_)" = 1 ]

      NOTMUCH_CONFIG=$TMPDIR/esc/config NO_COLOR= notmuch-tv show "$etid" >$out_
          grep -q 'RED' $out_
          [ "$(grep -c "$esc" $out_)" -gt 0 ]
          [ "$(grep -o "$esc.\{0,4\}" $out_ | grep -vcE "^$esc\[(0|1|2|32|36|33)m" || true)" = 0 ]

          # Control characters in authors and subject (ESC, U+009B) are dropped from
          # the list; UTF-8 text around them survives.
          b64() { printf '=?UTF-8?B?%s?=' "$(printf "$1" | base64 -w0)"; }
          ctl='E\033[31mvil \302\233x été'
          d=$TMPDIR/evil
          mkdir -p $d/mail/cur $d/mail/new $d/mail/tmp
          printf 'From: "%s" <evil@example.com>\nTo: me@example.com\nSubject: %s\nMessage-Id: <evil@example.com>\nDate: Mon, 02 Mar 2020 12:00:00 +0000\n\nhi\n' \
            "$(b64 "$ctl")" "$(b64 "$ctl")" >$d/mail/cur/e:2,S
          printf '[database]\npath=%s\n[user]\nname=Me\nprimary_email=me@example.com\n[new]\ntags=inbox\nignore=\n[maildir]\nsynchronize_flags=false\n' $d/mail >$d/config
          NOTMUCH_CONFIG=$d/config notmuch new >/dev/null
          NOTMUCH_CONFIG=$d/config notmuch-tv mails all >$out_
          assert_lines $out_ 1
          [ "$(cut -f3 $out_)" = "E[31mvil x été" ] || { cat -v $out_ >&2; exit 1; }
          [ "$(cut -f4 $out_)" = "E[31mvil x été" ] || { cat -v $out_ >&2; exit 1; }

          # The list is streamed: the first thread is out while notmuch still
          # waits on the gate. A buffering jq never prints it, so the wait
          # loop runs until timeout fails the check (no timing threshold).
          export GATE=$TMPDIR/gate
          mkfifo $GATE
          stream=$TMPDIR/stream
          rc=0
          timeout 60 bash -c '
            "$1" mails all >"$2" &
            until [ -s "$2" ]; do sleep 0.1; done
            cp "$2" "$2.first"
            echo go >"$GATE"
            wait $!
          ' _ ${tvSlow}/bin/notmuch-tv $stream || rc=$?
          if [ "$rc" != 0 ]; then
            timeout 5 sh -c 'echo go >"$GATE"' || true
            echo "mails all is not streamed (first line never came while notmuch was running; rc $rc)" >&2
            exit 1
          fi
          [ "$(cat $stream.first)" = "$(printf '01\t2023-11-14\tA\tS01')" ] || { echo "bad first line" >&2; cat $stream.first >&2; exit 1; }
          assert_lines $stream 2
          unset GATE

          # Messages with an exclude tag are not rendered.
          notmuch tag +spam id:m03@fixture.example.com
          notmuch-tv show "$ptid" >$out_
          [ "$(grep -c '^Date:' $out_)" = 2 ]

          rc=0
          notmuch-tv mails bogus >/dev/null 2>&1 || rc=$?
          [ "$rc" = 2 ]
          rc=0
          notmuch-tv show >/dev/null 2>&1 || rc=$?
          [ "$rc" = 2 ]
          rc=0
          notmuch-tv show 'x y"' >/dev/null 2>&1 || rc=$?
          [ "$rc" = 2 ]

          use_fixture ${fx.fixtureEmpty}
          for k in all unread; do
            notmuch-tv mails $k >$out_
            [ ! -s $out_ ] || { echo "mails $k not empty on empty db" >&2; exit 1; }
          done

          touch $out
  ''
