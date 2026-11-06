# Assert helpers sourced by checks.

# squeeze <string>: trim and collapse runs of spaces.
squeeze() {
  printf '%s\n' "$1" | sed -E 's/ +/ /g; s/^ //; s/ $//'
}

# assert_line <file> <expected>: some line of <file> equals <expected>
# after squeezing leading/trailing spaces and runs of spaces.
assert_line() {
  local file=$1 expected line
  expected=$(squeeze "$2")
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$(squeeze "$line")" = "$expected" ]; then
      return 0
    fi
  done <"$file"
  echo "assert_line failed: no line equals '$expected' in $file" >&2
  echo "--- $file ---" >&2
  cat "$file" >&2
  return 1
}

# assert_lines <file> <n>: <file> has exactly <n> lines.
assert_lines() {
  local file=$1 want=$2 got
  got=$(grep -c "" "$file" || true)
  if [ "$got" -ne "$want" ]; then
    echo "assert_lines failed: $file has $got lines, expected $want" >&2
    cat "$file" >&2
    return 1
  fi
}

# use_fixture <storePath>: copy a fixture to a writable temp dir, point its
# config at the copy, and export NOTMUCH_CONFIG and HOME.
use_fixture() {
  local src=$1 dest
  dest=$(mktemp -d)
  cp -r "$src"/. "$dest"/
  chmod -R u+w "$dest"
  sed -i "s|$src|$dest|g" "$dest/config"
  export HOME=${TMPDIR:-/tmp}
  export NOTMUCH_CONFIG=$dest/config
}
