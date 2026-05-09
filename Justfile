# Deploy malganis (Linode VPS)
deploy:
    # nixos-rebuild switch --target-host root@saegl.me --flake .#malganis
    nh os switch --hostname malganis --target-host root@saegl.me --elevation-strategy none .

# Run this if after update some systemd services cannot be restarted
deploy-boot:
    nixos-rebuild boot --target-host root@saegl.me --flake .#malganis

# Connect with ssh
ssh:
    ssh root@saegl.me

# Clean old generations and garbage collect on VPS
clean:
    ssh root@saegl.me 'nix-collect-garbage -d'

# Show free space on VPS
space:
    ssh root@saegl.me 'df -h /'

# Update flake inputs
up:
    nix flake update --commit-lock-file --impure \
        --override-input nixpkgs github:NixOS/nixpkgs/$(curl -L https://channels.nixos.org/nixpkgs-unstable/git-revision)
