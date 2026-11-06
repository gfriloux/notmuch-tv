# notmuch-tv: data source for the notmuch television cables.
# Read-only: never writes to the notmuch database.

die() {
  echo "notmuch-tv: $*" >&2
  exit 2
}

menu() {
  printf '%s\t%s\n' \
    top-senders "Top senders" \
    top-domains "Top sender domains" \
    top-noreply "Top noreply senders" \
    top-newsletters "Top newsletter senders" \
    top-recipients "Top recipients" \
    per-year "Mails per year" \
    per-month "Mails per month (last 12)" \
    old-unread "Old unread mails" \
    largest "Largest mails" \
    attachments "Attachments by type" \
    per-tag "Mails per tag" \
    per-folder "Mails per folder" \
    largest-threads "Largest threads" \
    duplicates "Duplicate mails"
}

# top <n>: first n lines of stdin. Reads all input so upstream commands never
# get SIGPIPE (which pipefail would turn into exit 141), unlike `head`.
top() {
  awk -v n="$1" 'NR <= n'
}

# addresses <notmuch address args>: notmuch address, always with --exclude=false.
addresses() {
  notmuch address --exclude=false --deduplicate=address "$@"
}

# counted <output> <query>: "<count> <address-or-sender>", biggest first.
counted() {
  addresses --output="$1" --output=count "$2" |
    awk -F'\t' '{ n = $1; sub(/^[^\t]*\t/, ""); print n " " $0 }' |
    sort -k1,1nr -s
}

# reference_date: NOTMUCH_TV_NOW or today, as YYYY-MM-DD.
reference_date() {
  date -d "${NOTMUCH_TV_NOW:-today}" +%Y-%m-%d
}

# folders: file paths on stdin, their folder relative to the mail root on
# stdout (maildir cur/new/tmp stripped). The mail root is database.mail_root,
# which notmuch reports as database.path when unset.
folders() {
  local root
  root=$(notmuch config get database.mail_root)
  if [ -z "$root" ]; then root=$(notmuch config get database.path); fi
  awk -v db="${root%/}/" '
    index($0, db) == 1 { $0 = substr($0, length(db) + 1) }
    { sub(/\/[^\/]*$/, ""); sub(/\/(cur|new|tmp)$/, ""); print }'
}

# clean (jq): drops control characters, C0 except tab and newline, DEL and C1
# (U+009B is a one-character CSI). It works on code points, so UTF-8 text
# around them is untouched. Every jq program printing mail data starts with it.
jq_clean='def clean: tostring | gsub("[\u0000-\u0008\u000b-\u001f\u007f-\u009f]"; "");'

# sanitise: stdin to stdout, line by line, through clean.
sanitise() {
  jq -Rr "$jq_clean clean"
}

newsletter_query='body:unsubscribe or body:désabonner or body:desabonner or body:"se désinscrire"'

run() {
  tmp=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT
  case "$1" in
  top-senders) counted sender '*' | top 15 ;;
  top-domains)
    addresses --output=address --output=count '*' |
      awk -F'\t' '{ n = $1; a = $2; sub(/.*@/, "", a); c[a] += n }
        END { for (d in c) print c[d] " " d }' |
      sort -k1,1nr -k2,2 | top 20
    ;;
  top-noreply)
    counted sender '*' | { grep -iE 'no-?reply|donotreply' || true; } | top 20
    ;;
  top-newsletters) counted sender "$newsletter_query" | top 20 ;;
  top-recipients)
    addresses --output=recipients --output=address --output=count tag:sent |
      awk -F'\t' '{ print $1 " " $2 }' | sort -k1,1nr -s | top 15
    ;;
  per-year)
    # Years with at least one mail, oldest first.
    now=$(reference_date)
    # The timestamp, not the summary text: notmuch prints recent dates
    # relative to the wall clock ("Today", "Yest.", "May 16"). Local year, as
    # `notmuch count date:<year>` uses local time.
    first=$(notmuch search --format=json --exclude=false --sort=oldest-first --limit=1 '*' |
      jq -r '.[0].timestamp // empty | strflocaltime("%Y")')
    if [ -n "$first" ]; then
      for ((y = first; y <= ${now:0:4}; y++)); do
        n=$(notmuch count --exclude=false "date:$y")
        if [ "$n" -gt 0 ]; then echo "$y $n"; fi
      done
    fi
    ;;
  per-month)
    now=$(reference_date)
    for ((i = 11; i >= 0; i--)); do
      m=$(date -d "${now:0:7}-01 -$i month" +%Y-%m)
      echo "$m $(notmuch count --exclude=false "date:$m")"
    done
    ;;
  old-unread)
    cutoff=$(date -d "$(reference_date) -1 year" +%Y-%m-%d)
    q="tag:unread and date:..$cutoff"
    notmuch count --exclude=false "$q"
    notmuch search --exclude=false --sort=oldest-first "$q" | top 50
    ;;
  largest)
    notmuch search --exclude=false --output=files '*' |
      xargs -d '\n' -r du -h --apparent-size | sort -rh | top 20
    ;;
  attachments)
    for t in pdf:application/pdf zip:application/zip video:'video/*'; do
      read -r count bytes < <(notmuch search --exclude=false --output=files "mimetype:${t#*:}" |
        xargs -d '\n' -r stat -c %s | awk '{ s += $1; n++ } END { print n + 0, s + 0 }')
      if [ "$count" -eq 0 ]; then
        echo "${t%%:*} 0 0"
      else
        echo "${t%%:*} $count $(numfmt --to=iec "$bytes")"
      fi
    done
    ;;
  per-tag)
    # One notmuch process for all tags: queries go through `count --batch`.
    notmuch search --exclude=false --output=tags '*' >"$tmp/tags"
    if [ -s "$tmp/tags" ]; then
      sed 's/"/""/g; s/^/tag:"/; s/$/"/' "$tmp/tags" |
        notmuch count --exclude=false --batch >"$tmp/counts"
      paste -d ' ' "$tmp/counts" "$tmp/tags" | sort -k1,1nr -s
    fi
    ;;
  per-folder)
    notmuch search --exclude=false --output=files '*' | folders |
      awk '{ c[$0]++ } END { for (f in c) print c[f] " " f }' |
      sort -k1,1nr -k2 -s
    ;;
  largest-threads)
    notmuch search --format=json --exclude=false '*' |
      jq -r 'sort_by(-.total)[] | "\(.total) \(.subject | gsub("[\\t\\n\\r]+"; " "))"' |
      top 20
    ;;
  duplicates)
    notmuch search --exclude=false --output=messages --duplicate=2 '*' >"$tmp/dups"
    n=$(grep -c '' "$tmp/dups" || true)
    if [ "$n" -eq 0 ]; then
      echo "No duplicate messages."
      return
    fi
    echo "$n messages stored in several files (same Message-Id)"
    top 50 <"$tmp/dups" | while IFS= read -r id; do
      id=${id#id:}
      notmuch show --exclude=false --format=json --body=false --entire-thread=false \
        "id:\"${id//\"/\"\"}\"" >"$tmp/msg"
      echo
      jq -r '.. | objects | select(has("headers")) | .headers as $h
        | [(.timestamp | strftime("%Y-%m-%d")), ($h.From // ""), ($h.Subject // "")]
        | map(gsub("[\\t\\n\\r]+"; " ")) | join("  ")' "$tmp/msg"
      notmuch search --exclude=false --output=files "id:\"${id//\"/\"\"}\"" |
        folders | sed 's/^/    /'
    done
    ;;
  *) die "unknown entry '$1'" ;;
  esac
}

# mails unread|all: one line per thread, newest first:
# <thread-id>\t<YYYY-MM-DD>\t<authors>\t<subject>. Respects the user's exclude
# tags. Dates are UTC (jq strftime). jq parses notmuch's array as a stream and
# prints each thread as soon as it is read, so tv fills the list while notmuch
# is still searching.
mails() {
  case "$1" in
  unread) q='tag:unread' ;;
  all) q='*' ;;
  *) die "unknown mail list '$1'" ;;
  esac
  notmuch search --format=json --sort=newest-first "$q" |
    jq -rn --stream --unbuffered "$jq_clean"'fromstream(1 | truncate_stream(inputs))
      | [.thread, (.timestamp | strftime("%Y-%m-%d")), .authors, .subject]
      | map(gsub("[\\t\\n\\r]"; " ") | clean) | join("\t")'
}

# show <thread-id>: the thread as readable text, newest message first, first
# 500 lines. One jq pass renders everything; an HTML-only body comes out as a
# "\001<base64>" line and goes through w3m here, once per such message. Once
# 500 lines are out the rest of jq's output is drained unread (no w3m).
show() {
  [[ "$1" =~ ^[0-9a-f]+$ ]] || die "invalid thread id '$1'"
  local sep line html nl n=0
  sep=$(printf '─%.0s' {1..60})
  notmuch show --format=json --entire-thread=true --include-html "thread:$1" |
    jq -r --arg sep "$sep" "$jq_clean"'
      def parts: .[] | ., ((.content | arrays) | parts);
      def size: if . < 1024 then "\(.) B"
        elif . < 1048576 then "\(. / 1024 * 10 | round / 10) KB"
        else "\(. / 1048576 * 10 | round / 10) MB" end;
      def attached: (.filename? // "") != "" or ((."content-disposition"? // "") == "attachment");
      def render:
        . as $m
        | [.body | parts] as $p
        | ([$p[] | select(attached | not)]) as $t
        | ([$t[] | select(."content-type" == "text/plain" and (.content | type) == "string")][0]) as $plain
        | ([$t[] | select(."content-type" == "text/html" and (.content | type) == "string")][0]) as $html
        | "\u0002S" + $sep,
          "\u0002HFrom:    \(($m.headers.From // "") | clean)",
          (if $m.headers.To then "\u0002HTo:      \($m.headers.To | clean)" else empty end),
          "\u0002HDate:    \($m.timestamp | strflocaltime("%Y-%m-%d %H:%M"))",
          "\u0002HSubject: \(($m.headers.Subject // "") | clean)",
          "\u0002HTags:    \($m.tags | map(clean) | join(" "))",
          "",
          (if $plain then ($plain.content | clean | sub("\n+$"; ""))
           elif $html then "\u0001" + ($html.content | @base64)
           else "\u0002A(no text body)" end),
          ($p[] | select(attached)
            | "\u0002A[attachment: \((.filename // "unnamed") | clean), \(."content-type" | clean)"
              + (if (."content-length"? | type) == "number" then ", \(."content-length" | size)" else "" end)
              + "]");
      [.. | objects | select(has("headers") and has("timestamp") and (.excluded | not))]
      | sort_by(-.timestamp) | to_entries[]
      | (if .key > 0 then "" else empty end), (.value | render)' |
    {
      while IFS= read -r line; do
        if [[ "$line" == $'\001'* ]]; then
          html=$(printf '%s' "${line#$'\001'}" | base64 -d |
            w3m -dump -T text/html -I UTF-8 -O UTF-8 -cols 100 |
            jq -Rrs "$jq_clean clean") ||
            html=$'\002A(could not render HTML)'
          printf '%s\n' "$html"
          nl=${html//[!$'\n']/}
          n=$((n + ${#nl} + 1))
        else
          printf '%s\n' "$line"
          n=$((n + 1))
        fi
        if [ "$n" -ge 500 ]; then
          cat >/dev/null
          break
        fi
      done
    } | colorize | top 500
}

# colorize: last rendering step of show. Structural lines carry a marker that
# mail content cannot produce (clean strips C0 controls): \002S separator,
# \002H header, \002A dim line. Unmarked lines are body text. Markers are
# always removed; escapes are added only unless NO_COLOR is set and non-empty.
colorize() {
  local color=1
  if [ -n "${NO_COLOR:-}" ]; then color=0; fi
  awk -v color="$color" '
    function wrap(code, s) { return color ? "\033[" code "m" s "\033[0m" : s }
    # spans(s, urls): s with email addresses (and, when urls is set, URLs)
    # coloured, whichever starts first; a URL wins a tie, so an address inside
    # a URL stays part of it. Trailing punctuation is left out of a URL.
    function spans(s, urls,    out, us, ul, as, al, u) {
      out = ""
      while (s != "") {
        us = urls && match(s, /(https?|ftp):\/\/[^[:space:]]+/) ? RSTART : 0
        ul = RLENGTH
        as = match(s, /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z][A-Za-z]+/) ? RSTART : 0
        al = RLENGTH
        if (us && (!as || us <= as)) {
          u = substr(s, us, ul)
          while (u != "" && match(u, "[]\047\".,;:!?)>]$")) u = substr(u, 1, length(u) - 1)
          if (u ~ /^(https?|ftp):\/\/$/) { out = out substr(s, 1, us + ul - 1); s = substr(s, us + ul); continue }
          out = out substr(s, 1, us - 1) wrap("4;36", u)
          s = substr(s, us + length(u))
        } else if (as) {
          out = out substr(s, 1, as - 1) wrap(36, substr(s, as, al))
          s = substr(s, as + al)
        } else break
      }
      return out s
    }
    function tags(s,    out) {
      if (!color) return s
      out = ""
      while (match(s, /[^ ]+/)) {
        out = out substr(s, 1, RSTART - 1) wrap(substr(s, RSTART, RLENGTH) == "unread" ? "1;33" : 33, substr(s, RSTART, RLENGTH))
        s = substr(s, RSTART + RLENGTH)
      }
      return out s
    }
    {
      kind = substr($0, 1, 1) == "\002" ? substr($0, 2, 1) : ""
      line = kind == "" ? $0 : substr($0, 3)
    }
    kind == "S" { sig = 0; print wrap(2, line); next }
    kind == "H" {
      c = index(line, ":")
      label = substr(line, 1, c)
      rest = substr(line, c + 1)
      if (label == "Subject:" && match(rest, /[^ ]/)) {
        rest = substr(rest, 1, RSTART - 1) wrap(1, substr(rest, RSTART))
      } else if (label == "From:" || label == "To:") rest = spans(rest, 0)
      else if (label == "Tags:") rest = tags(rest)
      print wrap("1;35", label) rest
      next
    }
    kind == "A" { print wrap(2, line); next }
    {
      t = line
      sub(/ +$/, "", t)
      if (t == "--") sig = 1
      if (sig) { print line == "" ? "" : wrap(2, line); next }
      depth = 0
      while (match(t, /^ *>/)) { depth++; t = substr(t, RLENGTH + 1) }
      if (depth == 0) print spans(line, 1)
      else print wrap(depth == 1 ? 32 : depth == 2 ? 36 : 33, line)
    }'
}

# Cache for menu entries, outside the notmuch database. An entry is keyed by
# its id, a hash of the config path, the message count, the database uuid +
# lastmod revision and the reference date, so new mail, deleted mail, any tag
# change or a new day invalidates it. (notmuch new does not bump the revision
# when it removes a message, hence the count.)
# Private to the user (umask 077: they hold mail paths). Files, all in
# ${XDG_CACHE_HOME:-~/.cache}/notmuch-tv:
#   <id>.<cfg>.<count>.<uuid>.<rev>.<date>.out   the output (written atomically)
#   <id>.<cfg>.<count>.<uuid>.<rev>.<date>.err   stderr of a failed run (shown once)
#   <id>.<cfg>.<count>.<uuid>.<rev>.<date>.lock  held while computing
# Another process may prune an entry at any time, so reads go through
# `cat ... 2>/dev/null` and a failed read counts as a miss.

# valid_entry <id>: dies (exit 2) unless <id> is a menu entry.
valid_entry() {
  grep -qxF -- "$1" < <(menu | cut -f1) || die "unknown entry '$1'"
}

# cache_key <id>: sets prefix and key. Fails when the cache dir is unusable.
cache_key() {
  local dir cfg rev
  umask 077
  dir=${XDG_CACHE_HOME:-$HOME/.cache}/notmuch-tv
  if ! mkdir -p "$dir" 2>/dev/null || [ ! -w "$dir" ]; then return 1; fi
  chmod 700 "$dir" 2>/dev/null || true
  cfg=$(printf '%s' "${NOTMUCH_CONFIG:-default}" | sha256sum | cut -c1-16)
  rev=$(notmuch count --exclude=false --lastmod '*' |
    awk -F'\t' 'NF >= 3 { print $1 "." $2 "." $3 }') || return 1
  if [ -z "$rev" ]; then return 1; fi
  prefix=$dir/$1.$cfg
  key=$prefix.$rev.$(reference_date)
}

# compute <id>: run the entry in its own process. On success store its output
# as $key.out and drop older entries for the same id and config; on failure
# store its stderr as $key.err. Returns the run's status.
compute() {
  local t rc=0 f
  t=$(mktemp "$key.XXXXXX.tmp")
  "$0" _run "$1" >"$t" 2>"$t.err" || rc=$?
  if [ "$rc" -eq 0 ]; then
    mv -f "$t" "$key.out"
    rm -f "$t.err" "$key.err"
    for f in "$prefix".*.out "$prefix".*.err "$prefix".*.lock; do
      case "$f" in "$key".*) ;; *) rm -f "$f" ;; esac
    done
  else
    [ -s "$t.err" ] || echo "notmuch-tv: '$1' failed (exit $rc)" >"$t.err"
    mv -f "$t.err" "$key.err"
    rm -f "$t"
  fi
  return "$rc"
}

# cached_run <id>: the run subcommand. Cached output if fresh, else computed
# in the foreground (waiting for a background computation of the same key).
cached_run() {
  local rc
  valid_entry "$1"
  cache_key "$1" || exec "$0" _run "$1"
  if cat "$key.out" 2>/dev/null; then return; fi
  exec 9>"$key.lock"
  flock 9
  if cat "$key.out" 2>/dev/null; then return; fi
  rm -f "$key.err"
  rc=0
  compute "$1" || rc=$?
  if [ "$rc" -ne 0 ]; then
    cat "$key.err" >&2 2>/dev/null || true
    rm -f "$key.err"
    exit "$rc"
  fi
  # Pruned in between by a newer key: run uncached.
  cat "$key.out" 2>/dev/null || exec "$0" _run "$1"
}

# background <id>: compute unless another process already is (detached job).
background() {
  cache_key "$1" || exit 0
  exec 9>"$key.lock"
  flock -n 9 || exit 0
  [ -f "$key.out" ] || compute "$1" || true
}

# preview <id>: what tv shows. tv kills preview jobs after 3 s, so the work
# runs detached and the preview waits at most NOTMUCH_TV_PREVIEW_BUDGET seconds.
preview() {
  local budget ticks i
  valid_entry "$1"
  cache_key "$1" || exec "$0" _run "$1"
  if show_cached; then return; fi
  setsid -f "$0" _background "$1" </dev/null >/dev/null 2>&1
  budget=${NOTMUCH_TV_PREVIEW_BUDGET:-2}
  ticks=$(awk -v b="$budget" 'BEGIN { t = int(b * 10); print (t > 0 ? t : 0) }')
  for ((i = 0; i < ticks; i++)); do
    sleep 0.1
    if show_cached; then return; fi
  done
  echo "Computing… this entry takes a while on your mailbox."
  echo "Move to another entry and come back, or press Enter to run it now."
}

# show_cached: print $key.out, or $key.err once (the next preview retries).
show_cached() {
  if cat "$key.out" 2>/dev/null; then return 0; fi
  if cat "$key.err" 2>/dev/null; then
    rm -f "$key.err"
    return 0
  fi
  return 1
}

case "${1:-}" in
menu) menu ;;
run) cached_run "${2:-}" ;;
preview) preview "${2:-}" ;;
_run) run "${2:-}" | sanitise ;;
_background) background "${2:-}" ;;
mails) mails "${2:-}" ;;
show) show "${2:-}" ;;
*) die "usage: notmuch-tv menu | run <id> | preview <id> | mails unread|all | show <thread-id>" ;;
esac
