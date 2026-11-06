# `nix run .#demo`: the package on a private, writable copy of the fixture.
{
  pkgs,
  package,
  fixture,
}:
pkgs.writeShellApplication {
  name = "notmuch-tv-demo";
  runtimeInputs = with pkgs; [coreutils gnused];
  text = ''
    dest=$(mktemp -d)
    trap 'rm -rf "$dest"' EXIT
    cp -r ${fixture}/. "$dest"/
    chmod -R u+w "$dest"
    sed -i "s|${fixture}|$dest|g" "$dest/config"
    export NOTMUCH_CONFIG=$dest/config
    # The menu cache goes with the copy, not into the user's cache.
    export XDG_CACHE_HOME=$dest/cache
    ${package}/bin/notmuch-television notmuch-menu
  '';
}
