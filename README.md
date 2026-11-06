# notmuch-tv

Cable channels for [television](https://github.com/alexpasmantier/television)
(`tv`) that read a [notmuch](https://notmuchmail.org) mailbox. I wrote them to
clean up my mail: the menu answers "who fills my mailbox?" with top senders,
noreply and newsletter senders, mails per year, the largest mails, duplicates
and a few more counts. The mail cables list threads (unread or all) with a
preview, and open the selected thread in aerc or alot.

The flake ships a Home Manager module, a `nix run` entry point and a demo on a
fake mailbox.

```
╭────────────────────── notmuch-menu ──────────────────────╮╭────────────────────── Top senders ───────────────────────╮
│>                                                  1 / 14 ││ 4 Alice <alice@example.com>                              ▲
╰──────────────────────────────────────────────────────────╯│ 3 News <news@example.org>                                █
╭──────────────────────── Results ─────────────────────────╮│ 2 Me <me@example.com>                                    █
│> Top senders                                             ││ 2 noreply@example.net                                    █
│  Top sender domains                                      ││ 1 Carol <carol@example.org>                              █
│  Top noreply senders                                     ││ 1 Bob <bob@example.com>                                  █
│  Top newsletter senders                                  ││ 1 Dave <dave@example.net>                                █
│  Top recipients                                          ││                                                          █
│  Mails per year                                          ││                                                          █
│  Mails per month (last 12)                               ││                                                          █
│  Old unread mails                                        ││                                                          █
│  Largest mails                                           ││                                                          █
│  Attachments by type                                     ││                                                          █
│  Mails per tag                                           ││                                                          █
│  Mails per folder                                        ││                                                          █
│  Largest threads                                         ││                                                          █
│  Duplicate mails                                         ││                                                          █
│                                                          ││                                                          █
│                                                          ││                                                          █
│                                                          ││                                                          █
│                                                          ││                                                          █
│                                                          ││                                                          █
│                                                          ││                                                          ║
│                                                          ││                                                          ║
│                                                          ││                                                          ║
│                                                          ││                                                          ║
│                                                          ││                                                          ▼
╰──────────────────────────────────────────────────────────╯╰──────────────────────────────────────────────────────────╯
  CHANNEL  notmuch-menu          Remote Control: ctrl-t • Actions: ctrl-x • Help: ctrl-h                        v0.15.9
```

The `notmuch-menu` channel in `nix run .#demo` (fake data, tv 0.15.9).

## Try it

```sh
# On your own mailbox (notmuch finds its config as usual, NOTMUCH_CONFIG included)
nix run github:gfriloux/notmuch-tv

# On a small fake mailbox shipped with the flake
nix run github:gfriloux/notmuch-tv#demo
```

`nix run` starts `tv` on the `notmuch-menu` channel with three cables:
`notmuch-menu`, `notmuch-aerc` and `notmuch-alot`. aerc and alot are taken
from your `PATH`. Arguments replace the default channel and go straight to
`tv`, for example `nix run github:gfriloux/notmuch-tv -- notmuch-aerc`.

The demo copies the fixture mailbox to a temporary directory, removed when
`tv` exits. Its preview cache lives in that directory too.

Supported systems: `x86_64-linux`, `aarch64-linux`.

## Home Manager

```nix
# flake.nix
{
  inputs.notmuch-tv = {
    url = "github:gfriloux/notmuch-tv";
    inputs.nixpkgs.follows = "nixpkgs";
    # notmuch-tv only uses home-manager in its own checks.
    inputs.home-manager.follows = "home-manager";
  };
}
```

```nix
# your Home Manager configuration
{ inputs, ... }:
{
  imports = [ inputs.notmuch-tv.homeManagerModules.default ];

  programs.television.enable = true;
  programs.notmuch-tv.enable = true;
}
```

This snippet expects `inputs` as a module argument: pass it through
`extraSpecialArgs` (standalone Home Manager) or `specialArgs` (NixOS or
nix-darwin module), or write the `imports` line where `inputs` is in scope.

The module is exported twice, as `homeManagerModules.default` and
`homeModules.default`. Both are the same module; use whichever name your
configuration already uses.

The module writes the cables to `programs.television.channels`. It does not
turn on television itself: set `programs.television.enable = true`, or the
cables are never installed.

### Options

| Option | Default | Description |
| --- | --- | --- |
| `programs.notmuch-tv.enable` | `false` | Add the cables. |
| `programs.notmuch-tv.package` | this flake's `notmuch-tv` package | The script the cables call. |
| `programs.notmuch-tv.aerc.enable` | `config.programs.aerc.enable` | Add the `notmuch-aerc` cable. |
| `programs.notmuch-tv.aerc.account` | the primary account with `aerc.enable` and `notmuch.enable`, else the first such account, else `null` | aerc account the threads open in. |
| `programs.notmuch-tv.alot.enable` | `config.programs.alot.enable` | Add the `notmuch-alot` cable. |
| `programs.notmuch-tv.notmuchConfig` | `config.home.sessionVariables.NOTMUCH_CONFIG or null` | notmuch config path written into the cables, so they work when `tv` runs without `NOTMUCH_CONFIG` in its environment. Home Manager's `programs.notmuch` sets that variable. |

aerc and alot run from `programs.aerc.package` and `programs.alot.package`.
When that package is `null` (the client is installed some other way), the
cable calls `aerc` or `alot` from `PATH`.

Evaluation fails with an assertion when the aerc cable is on and no account
qualifies. Fix it by setting `notmuch.enable = true` on an
`accounts.email.accounts.<name>` that has `aerc.enable = true`, or by setting
`programs.notmuch-tv.aerc.account`.

## Cables

| Cable | Installed when | Enter |
| --- | --- | --- |
| `notmuch-menu` | always | runs the entry and opens its full output in `less -R` |
| `notmuch-aerc` | `aerc.enable` is true | opens the thread in aerc |
| `notmuch-alot` | `alot.enable` is true | opens the thread in alot |
| `notmuch-mails` | neither aerc nor alot is enabled | nothing: list and preview only |

With the Home Manager module, `aerc.enable` and `alot.enable` follow
`programs.aerc.enable` and `programs.alot.enable` unless you set them.
`nix run` always has `notmuch-menu`, `notmuch-aerc` and `notmuch-alot`.

The three mail cables show one line per thread, newest first: date (UTC),
authors and subject. Each mail cable has two sources: Unread (`tag:unread`)
first, then All (`*`). Ctrl+S switches between them.

The preview shows every message of the thread, newest first: From, To, Date,
Subject and Tags, then the text body. The preview's `Date:` is in local time,
so it can differ from the UTC date in the list. A mail with only an HTML part
is rendered with w3m. Attachments are listed after the body. The preview stops
at 500 lines. Separators and attachment lines are dim, header labels and the
subject are bold, quoted lines are green, cyan and yellow by depth, and a
signature (from a `-- ` line on) is dim. Set `NO_COLOR` to turn colours off.
Control characters in mail data (terminal escape sequences included) are
removed from the lists, the preview and the menu output.

Pager and aerc return to `tv` when you quit them. alot replaces `tv`.

### aerc needs a notmuch account

The aerc cable opens a thread with aerc's `:query` command, which only exists
on accounts that use aerc's notmuch backend. Home Manager configures that
backend for an account that has both `aerc.enable` and `notmuch.enable`. With
`nix run`, no account is passed, so the thread opens in the account aerc
selects at startup; that account must be a notmuch one.

## Menu entries

| Entry | What it shows |
| --- | --- |
| Top senders | The 15 senders with the most messages. |
| Top sender domains | The 20 sender domains with the most messages. |
| Top noreply senders | The 20 biggest senders whose name or address contains `noreply`, `no-reply` or `donotreply`. |
| Top newsletter senders | The 20 biggest senders of mails whose body mentions unsubscribing (English or French wording). |
| Top recipients | The 15 addresses you wrote to most (`tag:sent`). |
| Mails per year | Message count for each year that has mail, oldest first. |
| Mails per month (last 12) | Message count for each of the last 12 months, empty months included. |
| Old unread mails | How many unread mails are older than one year, then the 50 oldest threads. |
| Largest mails | The 20 largest mail files. |
| Attachments by type | Number and total file size of mail files with a PDF, ZIP or video part. A message stored in two files counts twice. |
| Mails per tag | Message count for each tag. |
| Mails per folder | Mail files per maildir folder, relative to the mail root (`database.mail_root`, else `database.path`). |
| Largest threads | The 20 threads with the most messages. |
| Duplicate mails | Messages stored in several files (same Message-Id); the first 50 with the folders holding each copy. |

## Preview cache

`tv` kills a preview command after 3 seconds. On a large mailbox some entries
take longer, so the menu preview computes in a detached process and waits at
most 2 seconds for it. If the result is not ready, the preview shows
"Computing…"; move to another entry and come back, or press Enter to wait for
the full run.

Results go to `${XDG_CACHE_HOME:-~/.cache}/notmuch-tv`, a directory only you
can read (mode 0700, since outputs contain addresses and mail paths). A cached
result is keyed on the notmuch config, the message count, the database revision
and the date, so new mail, deleted mail (once `notmuch new` has seen the
deletion), any tag change and a new day make it stale. Enter reads the same
cache. A failed run shows its error once in the preview, and the next preview
retries.

## Environment variables

| Variable | Effect |
| --- | --- |
| `NOTMUCH_CONFIG` | notmuch config to read. The Home Manager module sets it in the cables from `programs.notmuch-tv.notmuchConfig`. |
| `XDG_CACHE_HOME` | Parent of the preview cache directory. |
| `NOTMUCH_TV_NOW` | Date used as "today" by Mails per year, Mails per month and Old unread mails, in any form `date -d` accepts. Defaults to today. |
| `NOTMUCH_TV_PREVIEW_BUDGET` | Seconds a menu preview waits before showing "Computing…". Default `2`. Keep it under 3, or `tv` kills the preview first. |
| `NO_COLOR` | When set and non-empty, the mail preview uses no colours. |
| `NOTMUCH_TV_AERC_ACCOUNT` | aerc account passed to `:query -a`. The aerc cable sets it from `programs.notmuch-tv.aerc.account`; unset, aerc uses its startup account. |

## Notes and limitations

- The cables run their commands with `shell = "bash"`, and `tv` looks up
  `bash` in `PATH`. A system without bash in `PATH` cannot run them.
- Multi-select is not handled. Enter acts on the thread id of the entry under
  the cursor; the cables do nothing with `tv`'s selection.
- The cables are read-only: they never write to the notmuch database or
  change tags.
- Tested with television 0.15.9. The cable file format can change between
  `tv` releases, so a newer `tv` may reject or misread these cables.
- Menu statistics count every message, including ones carrying your exclude
  tags (spam, deleted): they use `--exclude=false`. The mail lists respect
  your exclude tags, like `notmuch search` does.

## Without Nix

The generated cables reference Nix store paths, so they will not work as-is on
a machine without Nix. You can build them once on a machine with Nix and adapt
them:

```sh
nix build github:gfriloux/notmuch-tv
cables=$(grep -o '/nix/store/[^ ]*-notmuch-tv-cables' result/bin/notmuch-television)
mkdir -p ~/.config/television/cable
for f in "$cables"/*.toml; do
  sed -E 's|/nix/store/[^/]+/bin/||g' "$f" > ~/.config/television/cable/"$(basename "$f")"
done
```

The `sed` turns every store path into a bare command name (`notmuch-tv`,
`less`). You then need a `notmuch-tv` executable in `PATH`: take
`src/notmuch-tv.sh`, add `#!/usr/bin/env bash` and
`set -o errexit -o nounset -o pipefail` at the top (Nix adds these when it
builds the script), and make it executable. It calls `notmuch`, `jq`, GNU
coreutils, `gawk`, GNU `sed`, `findutils`, GNU `grep`, `w3m` and util-linux
(`flock`, `setsid`). This route is not tested.

Without Home Manager but with Nix, `lib.mkCables` returns the cables as an
attribute set ready for `pkgs.formats.toml`; see `nix/package.nix` for an
example.

## Development

```sh
nix flake check   # tests on the fixture mailbox, module evaluation, cable files
nix fmt -- .      # alejandra
```

The fixture mailbox is built by `tests/fixture.nix` and
`tests/fixture/gen-mails.sh`. It uses only reserved domains
(`example.com`, `example.org`, `example.net`).

## License

Apache-2.0, see [LICENSE](LICENSE).
