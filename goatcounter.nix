# GoatCounter web analytics for machineplay.org, at stats.machineplay.org.
# An instance with no sites serves a public "create your first site" form, so
# the database was built locally (`goatcounter db create site`) and copied to
# /var/lib/private/goatcounter before the vhost first went live.
{pkgs, ...}: {
  services.goatcounter = {
    enable = true;
    # Built without -trimpath, the binary embeds GOROOT source paths and drags
    # the 217M Go toolchain into the closure. Checks already ran upstream.
    package = pkgs.goatcounter.overrideAttrs {
      allowGoReference = false;
      doCheck = false;
    };
    port = 8081;
    proxy = true;
    extraArgs = ["-db" "sqlite+/var/lib/goatcounter/db.sqlite3"];
  };

  services.nginx.virtualHosts."stats.machineplay.org" = {
    enableACME = true;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8081";
      recommendedProxySettings = true;
    };
  };
}
