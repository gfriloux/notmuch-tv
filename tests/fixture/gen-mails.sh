#!/usr/bin/env bash
# Write the fake maildir used by every check. Usage: gen-mails.sh <maildir>
set -euo pipefail

root=${1:?usage: gen-mails.sh <maildir>}

ME='Me <me@example.com>'
ALICE='Alice <alice@example.com>'
NEWS='News <news@example.org>'
NOREPLY='noreply@example.net'
BOB='Bob <bob@example.com>'
CAROL='Carol <carol@example.org>'
DAVE='Dave <dave@example.net>'

# mail <nn> <folder> <from> <to> <date> <subject> <body> [<in-reply-to nn>]
mail() {
  local nn=$1 folder=$2 from=$3 to=$4 day=$5 subject=$6 body=$7 parent=${8:-}
  local dir=$root/$folder/cur
  mkdir -p "$dir" "$root/$folder/new" "$root/$folder/tmp"
  if printf '%s' "$subject" | LC_ALL=C grep -q '[^ -~]'; then
    subject="=?UTF-8?B?$(printf '%s' "$subject" | base64 -w0)?="
  fi
  {
    printf 'From: %s\n' "$from"
    printf 'To: %s\n' "$to"
    printf 'Subject: %s\n' "$subject"
    printf 'Date: %s\n' "$(date -u -d "$day 12:00:00" '+%a, %d %b %Y %H:%M:%S +0000')"
    printf 'Message-ID: <%s@fixture.example.com>\n' "$nn"
    if [ -n "$parent" ]; then
      printf 'In-Reply-To: <%s@fixture.example.com>\n' "$parent"
      printf 'References: <%s@fixture.example.com>\n' "$parent"
    fi
    printf 'MIME-Version: 1.0\n'
    printf 'Content-Type: text/plain; charset=UTF-8\n'
    printf 'Content-Transfer-Encoding: 8bit\n'
    printf '\n%s\n' "$body"
  } >"$dir/$nn.fixture:2,S"
}

mail m01 INBOX "$ALICE" "$ME" 2025-01-10 'Hello' 'Hi there.'
mail m02 INBOX "$ALICE" "$ME" 2025-02-10 'Project' 'Project kickoff.'
mail m03 Sent "$ME" "$ALICE" 2025-02-11 'Re: Project' 'Sounds good.' m02
mail m04 INBOX "$ALICE" "$ME" 2025-02-12 'Re: Project' 'Great.' m03
mail m05 INBOX "$ALICE" "$ME" 2026-06-01 'Lunch' 'Lunch tomorrow?'
mail m06 INBOX "$NEWS" "$ME" 2025-05-01 'Newsletter 1' 'News of the month. To stop receiving this, unsubscribe here.'
mail m07 INBOX "$NEWS" "$ME" 2025-06-01 'Newsletter 2' 'More news. To stop receiving this, unsubscribe here.'
mail m08 INBOX "$NEWS" "$ME" 2025-07-01 "Lettre d'été" 'Des nouvelles. Pour vous désabonner, cliquez ici.'
mail m09 INBOX "$NOREPLY" "$ME" 2025-08-01 'Receipt 1' 'Your receipt.'
mail m10 INBOX "$NOREPLY" "$ME" 2025-09-01 'Receipt 2' 'Your receipt.'
mail m12 INBOX "$CAROL" "$ME" 2020-03-10 'Old news' 'Long time ago.'
mail m13 Sent "$ME" "$BOB" 2025-10-02 'Re: Invoice' 'Thanks, paid.' m11
mail m15 INBOX "$DAVE" "$ME" 2025-10-15 'Price: "50$" $HOME' 'Price is "50$" for $HOME.'

# m11: invoice with a ~30 KB PDF attachment.
{
  printf 'From: %s\n' "$BOB"
  printf 'To: %s\n' "$ME"
  printf 'Subject: Invoice\n'
  printf 'Date: %s\n' "$(date -u -d '2025-10-01 12:00:00' '+%a, %d %b %Y %H:%M:%S +0000')"
  printf 'Message-ID: <m11@fixture.example.com>\n'
  printf 'MIME-Version: 1.0\n'
  printf 'Content-Type: multipart/mixed; boundary="fixture-boundary"\n'
  printf '\n--fixture-boundary\n'
  printf 'Content-Type: text/plain; charset=UTF-8\n\n'
  printf 'Invoice attached.\n'
  printf '\n--fixture-boundary\n'
  printf 'Content-Type: application/pdf; name="invoice.pdf"\n'
  printf 'Content-Disposition: attachment; filename="invoice.pdf"\n'
  printf 'Content-Transfer-Encoding: base64\n\n'
  head -c 22000 /dev/zero | tr '\0' 'x' | base64
  printf '\n--fixture-boundary--\n'
} >"$root/INBOX/cur/m11.fixture:2,S"

# m14: same Message-Id as m01, stored in another folder.
mkdir -p "$root/Archive/cur" "$root/Archive/new" "$root/Archive/tmp"
cp "$root/INBOX/cur/m01.fixture:2,S" "$root/Archive/cur/m14.fixture:2,S"
