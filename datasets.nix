# Datasets for rented GPU boxes (lab's experiments): a read-only rsync mirror.
#
# saegl pushes over their own ssh login:
#   rsync -a data/chess/cclr saegl@saegl.me:/srv/datasets/chess/
# Boxes pull as the `datasets` user with a key made only for them, which is
# copied onto machines we don't own. Its one entry below is forced to rrsync,
# read-only and inside /srv/datasets, so a leaked copy can read datasets and do
# nothing else: no shell, no writes, no forwarding.
#   rsync -a -e 'ssh -i ~/.ssh/lab_datasets_ed25519' datasets@saegl.me:chess/cclr data/chess/
{pkgs, ...}: let
  dir = "/srv/datasets";
  # Private half: ~/.ssh/lab_datasets_ed25519 on frostmourne
  boxKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHB8tKDiPeV8Xh/ncm8B4RQPP5kbHMaqVyO4Um0uKmmk lab-datasets-readonly";
in {
  systemd.tmpfiles.rules = ["d ${dir} 0755 saegl users -"];

  users.groups.datasets = {};
  users.users.datasets = {
    isSystemUser = true;
    group = "datasets";
    # sshd runs even a forced command through the login shell, so nologin
    # would refuse every pull.
    useDefaultShell = true;
    openssh.authorizedKeys.keys = [
      ''restrict,command="${pkgs.rrsync}/bin/rrsync -ro ${dir}" ${boxKey}''
    ];
  };
}
