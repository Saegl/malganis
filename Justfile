# Deploy malganis (Linode VPS)
deploy:
    nh os switch --hostname malganis --target-host root@saegl.me --elevation-strategy none .

# For when an update leaves systemd services unable to restart.
deploy-boot:
    nixos-rebuild boot --target-host root@saegl.me --flake .#malganis

# Push every secret. On a fresh machine run it BEFORE the first deploy: beszel-hub
# won't start without its SSH key.
push-secrets: push-machineplay-secrets push-beszel-secrets

# Push gitignored secrets/{backend.env,runner.env,registry-auth.key,.crt} and
# restart. The cert is also embedded in machineplay.nix.
push-machineplay-secrets:
    ssh root@saegl.me 'mkdir -p /etc/machineplay && chmod 700 /etc/machineplay'
    scp secrets/backend.env root@saegl.me:/etc/machineplay/backend.env
    scp secrets/runner.env root@saegl.me:/etc/machineplay/runner.env
    scp secrets/registry-auth.key root@saegl.me:/etc/machineplay/registry-auth.key
    scp secrets/registry-auth.crt root@saegl.me:/etc/machineplay/registry-auth.crt
    ssh root@saegl.me 'chmod 600 /etc/machineplay/backend.env /etc/machineplay/runner.env /etc/machineplay/registry-auth.key && chmod 644 /etc/machineplay/registry-auth.crt && systemctl restart machineplay machineplay-runner'

# Push gitignored secrets/beszel.env (admin account, first boot only) and
# beszel-hub.key (public half in beszel.nix), then restart the hub.
push-beszel-secrets:
    ssh root@saegl.me 'mkdir -p /etc/beszel && chmod 700 /etc/beszel'
    scp secrets/beszel.env root@saegl.me:/etc/beszel/hub.env
    scp secrets/beszel-hub.key root@saegl.me:/etc/beszel/hub.key
    # `|| true`: on a fresh machine the unit doesn't exist yet.
    ssh root@saegl.me 'chmod 600 /etc/beszel/hub.env /etc/beszel/hub.key && (systemctl restart beszel-hub || true)'

# Connect with ssh
ssh:
    ssh root@saegl.me

# Clean old generations and garbage collect on VPS
clean:
    ssh root@saegl.me 'nix-collect-garbage -d'

# Show free space on VPS
space:
    ssh root@saegl.me 'df -h /'

# Where the frostmourne NixOS config lives, as seen from this repo.
frostmourne := "../nixos"

# Match nixpkgs to frostmourne's so a deploy builds from this machine's store.
# Only `locked` changes, so `just up` still follows the channel.
sync-frostmourne:
    #!/usr/bin/env python3
    import json, pathlib, sys

    def nixpkgs_node(path):
        lock = json.loads(path.read_text())
        nodes = lock["nodes"]
        # Via the root node: the bare `nixpkgs` node may be a dependency's copy.
        name = nodes[lock["root"]]["inputs"]["nixpkgs"]
        # An input can be re-exported as ["parent", "input"] rather than a name.
        if not isinstance(name, str):
            sys.exit(f"{path}: nixpkgs is a follows chain ({name}), not a node")
        return lock, nodes[name]

    src = pathlib.Path("{{frostmourne}}") / "flake.lock"
    if not src.is_file():
        sys.exit(f"no flake.lock at {src} - set `frostmourne` to the config's path")

    _, theirs = nixpkgs_node(src)
    lock, ours = nixpkgs_node(pathlib.Path("flake.lock"))

    before, after = ours["locked"]["rev"], theirs["locked"]["rev"]
    if before == after:
        print(f"already in sync: {after}")
        raise SystemExit(0)

    ours["locked"] = theirs["locked"]
    # Nix writes its locks sorted, two-space indented, newline-terminated.
    pathlib.Path("flake.lock").write_text(
        json.dumps(lock, indent=2, sort_keys=True) + "\n"
    )
    print(f"nixpkgs {before[:12]} -> {after[:12]}")

# Update flake inputs
up:
    nix flake update --commit-lock-file --impure \
        --override-input nixpkgs github:NixOS/nixpkgs/$(curl -L https://channels.nixos.org/nixpkgs-unstable/git-revision)
