# Deploy malganis (Linode VPS)
deploy:
    nixos-rebuild switch --target-host root@saegl.me --flake .#malganis

# Update flake inputs
up:
    nix flake update --commit-lock-file --impure \
        --override-input nixpkgs github:NixOS/nixpkgs/$(curl -L https://channels.nixos.org/nixpkgs-unstable/git-revision)
