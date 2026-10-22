#!/usr/bin/env bash
# Build gpclient + gpauth against every nixpkgs revision a consumer pins, then write a signed,
# static Nix binary cache into $1 (default ./public) holding only the store paths that
# cache.nixos.org does not already serve. Clients put both caches in `substituters`.
#
#   NIX_SIGNING_KEY_FILE=/path/to/secret-key ci/build-cache.sh public
set -euo pipefail
key=${NIX_SIGNING_KEY_FILE:?set NIX_SIGNING_KEY_FILE}
out=${1:-public}
upstream=https://cache.nixos.org

# nixpkgs revisions: this flake's own lock, plus what vps-primary pins (it uses
# `inputs.nix-globalprotect.inputs.nixpkgs.follows = "nixpkgs"`, so its store paths are the
# ones built against its nixpkgs). Both the deployed branch and master (the next deploy).
revs=$(jq -r '.nodes[.nodes.root.inputs.nixpkgs].locked.rev' flake.lock)
for ref in deploy-vps-primary master; do
  lock=$(curl -fsSL "https://raw.githubusercontent.com/djbclark/site-djbclark/$ref/nixos/flake.lock") || continue
  revs+=" $(jq -r '.nodes[.nodes.root.inputs.nixpkgs].locked.rev' <<<"$lock")"
done
revs=$(tr ' ' '\n' <<<"$revs" | grep -E '^[0-9a-f]{40}$' | sort -u)

outs=()
for rev in $revs; do
  echo "== nixpkgs $rev"
  mapfile -t o < <(nix build --no-link --print-out-paths --no-write-lock-file \
    --override-input nixpkgs "github:NixOS/nixpkgs/$rev" .#gpclient .#gpauth)
  printf '   %s\n' "${o[@]}"
  outs+=("${o[@]}")
done

# Paths in the runtime closure that the upstream cache lacks.
missing=()
for p in $(nix path-info -r "${outs[@]}"); do
  h=$(basename "$p" | cut -d- -f1)
  curl -sfI -o /dev/null "$upstream/$h.narinfo" || missing+=("$p")
done
echo "== publishing ${#missing[@]} paths:"; printf '   %s\n' "${missing[@]}"

# A binary cache refuses a path whose references it does not hold. Drop in the upstream
# narinfos of the direct references for the copy, then delete them again: clients fetch
# those from cache.nixos.org, which they consult first (Priority 40 < 50).
mkdir -p "$out"
stubs=()
for p in "${missing[@]}"; do
  for r in $(nix-store -q --references "$p"); do
    [[ " ${missing[*]} " == *" $r "* ]] && continue
    h=$(basename "$r" | cut -d- -f1)
    [[ -e "$out/$h.narinfo" ]] && continue
    curl -sf "$upstream/$h.narinfo" -o "$out/$h.narinfo" && stubs+=("$h")
  done
done
nix copy --no-recursive --to "file://$PWD/$out?secret-key=$key&compression=zstd" "${missing[@]}"
for h in "${stubs[@]}"; do rm -f "$out/$h.narinfo"; done
rm -rf "$out/log" "$out/build-trace-v2"

printf 'StoreDir: /nix/store\nWantMassQuery: 1\nPriority: 50\n' > "$out/nix-cache-info"
printf '%s\n' "${missing[@]}" > "$out/store-paths.txt"
{
  echo '<!doctype html><title>nix-globalprotect binary cache</title>'
  echo '<h1>nix-globalprotect binary cache</h1>'
  echo '<p>Signed Nix binary cache for <a href="https://forgejo.mit.edu/djbclark/nix-globalprotect">nix-globalprotect</a>. Key and usage: see the README.</p>'
  echo '<p><a href="store-paths.txt">store-paths.txt</a>, built '"$(date -u +%FT%TZ)"' from '"${GITHUB_SHA:-local}"'.</p>'
} > "$out/index.html"
du -sh "$out"
