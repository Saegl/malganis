# Rented GPU boxes (lab's experiments): datasets in, results out, over rsync.
#
# Each direction has its own user and a key made only for boxes, copied onto
# machines we don't own. Each key's one entry is forced to rrsync inside its
# directory, so a leaked copy can do that one thing: no shell, no forwarding.
#
# Datasets, read-only. saegl pushes over their own login:
#   rsync -a data/chess/cclr saegl@saegl.me:/srv/datasets/chess/
# and boxes pull:
#   rsync -a -e 'ssh -i ~/.ssh/lab_datasets_ed25519' datasets@saegl.me:chess/cclr data/chess/
#
# Results, write-only: a box can add and update files under /srv/results but
# not read them back or delete any, and symlinks it sends are munged. saegl
# pulls them over their own login.
#   rsync -a -e 'ssh -i ~/.ssh/lab_results_ed25519' data/logs/exp/ results@saegl.me:exp/logs/
{pkgs, ...}: let
  datasets = "/srv/datasets";
  results = "/srv/results";
  # Private halves: ~/.ssh/lab_datasets_ed25519 and lab_results_ed25519 on frostmourne
  datasetsKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHB8tKDiPeV8Xh/ncm8B4RQPP5kbHMaqVyO4Um0uKmmk lab-datasets-readonly";
  resultsKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC359Y7Swa5lfr3McJzAtL+1fzmHIJHazghwLv0Hc6Wt lab-results-writeonly";

  # sshd runs even a forced command through the login shell, so nologin would
  # refuse every transfer.
  boxUser = name: dir: flags: key: {
    groups.${name} = {};
    users.${name} = {
      isSystemUser = true;
      group = name;
      useDefaultShell = true;
      openssh.authorizedKeys.keys = [
        ''restrict,command="${pkgs.rrsync}/bin/rrsync ${flags} ${dir}" ${key}''
      ];
    };
  };
  d = boxUser "datasets" datasets "-ro" datasetsKey;
  r = boxUser "results" results "-wo -no-del -munge" resultsKey;
in {
  systemd.tmpfiles.rules = [
    "d ${datasets} 0755 saegl users -"
    "d ${results} 0755 results results -"
  ];
  users.groups = d.groups // r.groups;
  users.users = d.users // r.users;
}
