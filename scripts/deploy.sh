#!/usr/bin/env bash
# Infinity Arcade deploy helper. Deploys ONLY the canister you name, never game_assets
# (that canister holds the uploaded games; re-syncing it from the repo would delete them).
#
#   scripts/deploy.sh local frontend|backend|nft|both
#   scripts/deploy.sh ic    frontend|backend|nft|both
#   scripts/deploy.sh ic    first-time      # creates all four canisters once (empty game_assets is fine then)
set -euo pipefail
cd "$(dirname "$0")/.."
ENVNAME="${1:-}"; WHAT="${2:-}"
[[ "$ENVNAME" == "local" || "$ENVNAME" == "ic" ]] || { echo "usage: scripts/deploy.sh <local|ic> <frontend|backend|nft|both|first-time>"; exit 1; }
E=(); [[ "$ENVNAME" == "ic" ]] && E=(-e ic)

check_ic() {
  if [[ "$ENVNAME" == "ic" ]]; then
    if grep -q "PASTE_MAINNET" index.html; then echo "STOP: index.html still has PASTE_MAINNET placeholders in ARCADE_ENVS.ic"; exit 1; fi
    if grep -q "ALLOW_TEST_MINTING : Bool = true" backend/main.mo; then echo "note: ALLOW_TEST_MINTING is still true (admin-only test tools stay enabled on mainnet)"; fi
    echo "identity: $(icp identity principal)"
  fi
}

frontend() { check_ic; node scripts/build-frontend-publish.mjs && icp deploy frontend ${E[@]+"${E[@]}"}; }
backend()  { check_ic; icp deploy arcade_backend -m upgrade ${E[@]+"${E[@]}"} --yes; }
nft()      { check_ic; icp deploy nft_canister -m upgrade ${E[@]+"${E[@]}"} --yes; }

case "$WHAT" in
  frontend) frontend ;;
  backend)  backend ;;
  nft)      nft ;;
  both)     backend; frontend ;;
  first-time)
    [[ "$ENVNAME" == "ic" ]] || { echo "first-time is for ic only"; exit 1; }
    if [[ -f .icp/data/mappings/ic.ids.json ]]; then echo "STOP: .icp/data/mappings/ic.ids.json already exists - canisters are created. Use frontend/backend/nft."; exit 1; fi
    echo "identity: $(icp identity principal)"; echo "cycles:   $(icp cycles balance -e ic)"
    node scripts/build-frontend-publish.mjs
    icp deploy -e ic
    echo; echo "Canister IDs (also saved in .icp/data/mappings/ic.ids.json):"; cat .icp/data/mappings/ic.ids.json ;;
  *) echo "usage: scripts/deploy.sh <local|ic> <frontend|backend|nft|both|first-time>"; exit 1 ;;
esac
