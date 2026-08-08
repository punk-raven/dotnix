#!/usr/bin/env bash
# Bump the AXI tool pins in modules/agent-tooling/axi-packages.nix to their
# latest upstream release, resolving the new content hashes.
#
# Why this exists: `npx skills update` fetches the newest skill content at run
# time and writes it straight into ~/.agents/skills - the same paths
# modules/agent-tooling/axi.nix declares as store symlinks. That silently
# replaces a declared symlink with a real directory, and the next `rebuild`
# fails during activation. The fix is not to stop updating, it is to make the
# flake's pins the thing that moves, so the store already carries the newest
# skills and nothing needs to overwrite anything.
#
# This automates the manual loop documented in CLAUDE.md ("Agent-tooling
# version bumps"): set the version, set the hashes to fakeHash, build to
# surface the real ones, paste back. It only rewrites the file - it never
# activates. Review with `git diff` and run `rebuild` yourself.
#
# Scope: the mkAxi packages only. rtk/ccusage/codegraph/caveman carry a
# per-system source selector with four platform hashes each and are a different
# shape; chrome-devtools-mcp tracks a Google repo, not kunchenguid. Those stay
# manual, and the script says so rather than pretending it covered them.

set -euo pipefail

REPO_ROOT="${DOTNIX_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PKGS_FILE="$REPO_ROOT/modules/agent-tooling/axi-packages.nix"
GITHUB_OWNER="kunchenguid"

# The mkAxi-built attributes, in file order.
PACKAGES=(gh-axi chrome-devtools-axi lavish-axi tasks-axi quota-axi)

FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

die() { echo "update-axi: $*" >&2; exit 1; }

[[ -f "$PKGS_FILE" ]] || die "cannot find $PKGS_FILE"
command -v nix >/dev/null || die "nix is not on PATH"
command -v gh-axi >/dev/null || die "gh-axi is not on PATH"

# Line range of one `<name> = mkAxi {` ... `};` block, so every edit below is
# scoped to that attribute and cannot touch a same-named field elsewhere.
block_range() {
  local pkg="$1" start end
  start=$(grep -n "^  ${pkg} = mkAxi {" "$PKGS_FILE" | head -1 | cut -d: -f1) \
    || die "no mkAxi block for $pkg"
  [[ -n "$start" ]] || die "no mkAxi block for $pkg"
  end=$(awk -v s="$start" 'NR > s && /^  };$/ { print NR; exit }' "$PKGS_FILE")
  [[ -n "$end" ]] || die "unterminated mkAxi block for $pkg"
  echo "$start $end"
}

field_value() {
  local pkg="$1" field="$2" range
  read -r start end <<<"$(block_range "$pkg")"
  sed -n "${start},${end}p" "$PKGS_FILE" \
    | grep -E "^    ${field} = " | head -1 | sed -E 's/.*"([^"]*)".*/\1/'
}

set_field() {
  local pkg="$1" field="$2" value="$3" start end
  read -r start end <<<"$(block_range "$pkg")"
  # Anchored to the field name at its exact indentation, inside the block only.
  sed -i '' -E "${start},${end}s|^(    ${field} = ).*\$|\\1${value};|" "$PKGS_FILE"
}

# Latest non-draft, non-prerelease release tag. gh-axi prints one CSV row per
# release as `tag,name,draft,prerelease,published`.
latest_version() {
  local pkg="$1"
  gh-axi release list --repo "${GITHUB_OWNER}/${pkg}" 2>/dev/null \
    | grep -E "^  ${pkg}-v" \
    | awk -F, '$3 == "no" && $4 == "no" { print $1; exit }' \
    | sed -E "s/^  ${pkg}-v//"
}

# Build one attribute of the package and read the hash nix reports back. A
# fixed-output derivation with a wrong hash prints `got: <sri>`; that is the
# value we want, so a failed build here is the success path.
resolve_hash() {
  local pkg="$1" attr="$2" out
  out=$(nix build --impure --no-link --expr \
    "let f = builtins.getFlake (toString ${REPO_ROOT}); \
       pkgs = f.inputs.nixpkgs.legacyPackages.\${builtins.currentSystem}; \
     in (import ${PKGS_FILE} { inherit pkgs; }).\"${pkg}\".${attr}" 2>&1 || true)
  grep -oE 'got: +sha256-[A-Za-z0-9+/=]+' <<<"$out" | head -1 | sed -E 's/got: +//'
}

bumped=0
current=0
printf '%-22s %-10s %s\n' "PACKAGE" "PINNED" "LATEST"

for pkg in "${PACKAGES[@]}"; do
  pinned=$(field_value "$pkg" version)
  latest=$(latest_version "$pkg")

  if [[ -z "$latest" ]]; then
    printf '%-22s %-10s %s\n' "$pkg" "$pinned" "could not reach GitHub - skipped"
    continue
  fi

  if [[ "$pinned" == "$latest" ]]; then
    printf '%-22s %-10s %s\n' "$pkg" "$pinned" "current"
    current=$((current + 1))
    continue
  fi

  printf '%-22s %-10s -> %s\n' "$pkg" "$pinned" "$latest"
  if (( DRY_RUN )); then
    bumped=$((bumped + 1))
    continue
  fi

  set_field "$pkg" version "\"${latest}\""
  set_field "$pkg" srcHash "\"${FAKE_HASH}\""
  set_field "$pkg" pnpmHash "\"${FAKE_HASH}\""

  src_hash=$(resolve_hash "$pkg" src)
  [[ -n "$src_hash" ]] || die "could not resolve srcHash for $pkg (tag ${pkg}-v${latest} may not exist)"
  set_field "$pkg" srcHash "\"${src_hash}\""

  # pnpmDeps is fetched from the source, so it must resolve after srcHash.
  pnpm_hash=$(resolve_hash "$pkg" pnpmDeps)
  [[ -n "$pnpm_hash" ]] || die "could not resolve pnpmHash for $pkg"
  set_field "$pkg" pnpmHash "\"${pnpm_hash}\""

  bumped=$((bumped + 1))
done

echo
if (( bumped == 0 )); then
  echo "All ${current} AXI pins are already current. Nothing to do."
  exit 0
fi

if (( DRY_RUN )); then
  echo "${bumped} would be bumped. Re-run without --dry-run to apply."
  exit 0
fi

cat <<EOF
${bumped} bumped, hashes resolved. Nothing has been activated.

  git diff modules/agent-tooling/axi-packages.nix
  rebuild

Not covered by this script - bump these by hand if needed:
  rtk, ccusage, codegraph, caveman   (per-system selector, 4 hashes each)
  chrome-devtools-mcp                (tracks ChromeDevTools, not ${GITHUB_OWNER})
EOF
