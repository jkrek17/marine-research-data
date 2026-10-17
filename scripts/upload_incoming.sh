#!/usr/bin/env bash
# Upload the files of an incoming/ folder to the releases of this repository (one shared step for
# .github/workflows/publish.yml, fill.yml and truth.yml).
#
#   scripts/upload_incoming.sh <folder>
#
# <folder> holds, relative to itself:
#   {natl,npac}/{YYYYMMDDHH}.zip                       -> release fields-{basin}-{YYYYMM},
#                                                          asset {basin}_{YYYYMMDDHH}.zip
#   truth/{analysis,obs,airsea,gridsat,airmass}/{natl,npac}/{YYYYMMDDHH}.npz
#                                                       -> release truth-{kind}-{basin}-{YYYYMM}, asset {YYYYMMDDHH}.npz
#   truth/{ascat,smap}/{YYYYMMDD}.npz                  -> release truth-{kind}-{YYYYMM}, asset {YYYYMMDD}.npz
# Anything else is reported and skipped. Missing releases are created. Assets are uploaded with --clobber
# (the producer, tools/publish_store.py, has already merged each file with the published asset).
# Needs the gh CLI and GH_TOKEN; the repository is GITHUB_REPOSITORY, else the current git remote.
set -euo pipefail

dir="${1:?usage: upload_incoming.sh <folder>}"
[ -d "$dir" ] || { echo "upload_incoming: no folder $dir (nothing to upload)"; exit 0; }
repo=()
[ -n "${GITHUB_REPOSITORY:-}" ] && repo=(--repo "$GITHUB_REPOSITORY")

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
declare -A title note
n=0
while IFS= read -r f; do
  rel="${f#"$dir"/}"
  if [[ "$rel" =~ ^(natl|npac)/([0-9]{10})\.zip$ ]]; then
    b="${BASH_REMATCH[1]}"; s="${BASH_REMATCH[2]}"
    tag="fields-${b}-${s:0:6}"; asset="${b}_${s}.zip"
    title[$tag]="Model fields, ${b}, ${s:0:4}-${s:4:2}"
    note[$tag]="One zip per ${b} cycle (${b}_YYYYMMDDHH.zip), ZIP_STORED npz files in the layout of rk.store. See README.md."
  elif [[ "$rel" =~ ^truth/(analysis|obs|airsea|gridsat|airmass)/(natl|npac)/([0-9]{10})\.npz$ ]]; then
    k="${BASH_REMATCH[1]}"; b="${BASH_REMATCH[2]}"; s="${BASH_REMATCH[3]}"
    tag="truth-${k}-${b}-${s:0:6}"; asset="${s}.npz"
    title[$tag]="Truth ${k}, ${b}, ${s:0:4}-${s:4:2}"
    note[$tag]="One npz per valid time (YYYYMMDDHH.npz): truth kind ${k}, basin ${b}. See README.md."
  elif [[ "$rel" =~ ^truth/(ascat|smap)/([0-9]{8})\.npz$ ]]; then
    k="${BASH_REMATCH[1]}"; s="${BASH_REMATCH[2]}"
    tag="truth-${k}-${s:0:6}"; asset="${s}.npz"
    title[$tag]="Truth ${k}, ${s:0:4}-${s:4:2}"
    note[$tag]="One npz per UTC day (YYYYMMDD.npz), both basins: truth kind ${k}. See README.md."
  else
    echo "skip $rel"
    continue
  fi
  mkdir -p "$stage/$tag"
  cp "$f" "$stage/$tag/$asset"
  n=$((n+1))
done < <(find "$dir" -type f | sort)

retry() {  # retry <command...>: three tries, 20 s apart
  local i
  for i in 1 2 3; do
    "$@" && return 0
    echo "attempt $i failed: $*" >&2
    sleep 20
  done
  return 1
}

for d in "$stage"/*/; do
  [ -d "$d" ] || continue
  tag=$(basename "$d")
  if ! gh release view "$tag" "${repo[@]}" >/dev/null 2>&1; then
    gh release create "$tag" "${repo[@]}" --target main --latest=false \
      --title "${title[$tag]}" --notes "${note[$tag]}" \
      || gh release view "$tag" "${repo[@]}" >/dev/null   # lost a race with another job: fine
  fi
  mapfile -t files < <(find "$d" -type f | sort)
  for ((i = 0; i < ${#files[@]}; i += 50)); do   # at most 50 assets per call
    retry gh release upload "$tag" "${files[@]:i:50}" "${repo[@]}" --clobber \
      || { echo "upload to $tag failed" >&2; exit 1; }
  done
  echo "uploaded ${#files[@]} asset(s) to $tag"
done
echo "upload_incoming: $n file(s) from $dir"
