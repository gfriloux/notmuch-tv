# notmuch and w3m are arguments so checks can swap in stubs.
{
  pkgs,
  notmuch ? pkgs.notmuch,
  w3m ? pkgs.w3m,
}:
pkgs.writeShellApplication {
  name = "notmuch-tv";
  runtimeInputs = [notmuch w3m] ++ (with pkgs; [jq coreutils gawk gnused findutils gnugrep util-linux]);
  text = builtins.readFile ../src/notmuch-tv.sh;
}
