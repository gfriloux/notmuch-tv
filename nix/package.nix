# `nix run`: television with the notmuch cables. aerc and alot come from PATH.
{
  pkgs,
  notmuch-tv,
  television ? pkgs.television,
}: let
  cables = import ./cables.nix {
    inherit pkgs notmuch-tv;
    aerc = "PATH";
    alot = "PATH";
  };
  toml = pkgs.formats.toml {};
  cableDir = pkgs.linkFarm "notmuch-tv-cables" (pkgs.lib.mapAttrsToList (n: v: {
      name = "${n}.toml";
      path = toml.generate "${n}.toml" v;
    })
    cables);
in
  pkgs.writeShellApplication {
    name = "notmuch-television";
    text = ''
      if [ $# -eq 0 ]; then set -- notmuch-menu; fi
      exec ${pkgs.lib.getExe' television "tv"} --cable-dir ${cableDir} "$@"
    '';
  }
