# Fake notmuch databases. Each output has $out/config and $out/mail.
{
  pkgs,
  system ? pkgs.stdenv.hostPlatform.system,
}: let
  mk = {
    name,
    withMails,
  }:
    pkgs.runCommand name {nativeBuildInputs = [pkgs.notmuch pkgs.coreutils pkgs.bash];} ''
      mkdir -p $out/mail
      ${pkgs.lib.optionalString withMails "bash ${./fixture/gen-mails.sh} $out/mail"}
      cat > $out/config <<EOF2
      [database]
      path=$out/mail

      [user]
      name=Me
      primary_email=me@example.com

      [new]
      tags=inbox
      ignore=

      [search]
      exclude_tags=spam

      [maildir]
      synchronize_flags=false
      EOF2
      export NOTMUCH_CONFIG=$out/config
      export HOME=$TMPDIR
      notmuch new
      ${pkgs.lib.optionalString withMails ''
        id() { echo "id:$1@fixture.example.com"; }
        notmuch tag +unread "$(id m05)" "$(id m12)"
        notmuch tag -inbox +sent "$(id m03)" "$(id m13)"
        notmuch tag +spam "$(id m10)"
      ''}
    '';
in {
  fixture = mk {
    name = "notmuch-tv-fixture";
    withMails = true;
  };
  fixtureEmpty = mk {
    name = "notmuch-tv-fixture-empty";
    withMails = false;
  };
}
