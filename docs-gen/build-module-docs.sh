#!/usr/bin/env bash
# Per-module YARD docs merged into one namespace-rooted tree:
#   <out>/AWSCDK/<Module>/<Class>.html   (+ shared css/js at <out>/)
# Each module is built in isolation (crash-safe), then its AWSCDK/<Module>/ subtree
# is merged in. Finally the docs theme is applied (YARD's common.css, loaded last).
# Built with the gem lib as CWD so source paths render clean ("dynamo_db/table.rb").
#
#   build-module-docs.sh <gem-lib-dir> <out-dir> [module ...]   (no args = all)
set -euo pipefail
GEM_LIB="$(cd "$1" && pwd)"; OUT="$(mkdir -p "$2" && cd "$2" && pwd)"; shift 2
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH="$(ruby -e 'print Gem.user_dir')/bin:$PATH"

# YARD's parser/registry recurse deeply on large modules (e.g. `interfaces` is ~3.3k
# files) and SystemStackError with the default 8 MB stack. Raise the C stack (main
# thread) and the VM stack so any single module builds in one run. Best-effort.
ulimit -s unlimited 2>/dev/null || ulimit -s 1048576 2>/dev/null || true
export RUBY_THREAD_VM_STACK_SIZE="${RUBY_THREAD_VM_STACK_SIZE:-536870912}"

modules=("$@")
[ ${#modules[@]} -eq 0 ] && modules=($(ls "$GEM_LIB"))
mkdir -p "$OUT/AWSCDK"

for mod in "${modules[@]}"; do
  [ -d "$GEM_LIB/$mod" ] || { echo "skip $mod (no dir)"; continue; }
  tmp=$(mktemp -d)
  pushd "$GEM_LIB" >/dev/null
  mapfile -t files < <(find "$mod" -name '*.rb')   # relative paths -> clean "Defined in"
  if [ ${#files[@]} -gt 0 ]; then
    printf 'yard %-22s %s files\n' "$mod" "${#files[@]}"
    if yard doc "${files[@]}" -o "$tmp" --no-cache --no-progress -q 2>/dev/null; then
      cp -r "$tmp/." "$OUT/"   # merge: AWSCDK/<Module>/ accumulates; css/js last-wins
    else
      echo "  (yard failed for $mod)"
    fi
  fi
  popd >/dev/null
  rm -rf "$tmp"
done

# Apply the theme: YARD loads common.css last, so this overrides style.css site-wide.
if [ -f "$SELF_DIR/docs-theme.css" ] && [ -d "$OUT/css" ]; then
  cp "$SELF_DIR/docs-theme.css" "$OUT/css/common.css"
  echo "applied theme -> css/common.css"
fi
