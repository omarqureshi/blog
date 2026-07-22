#!/usr/bin/env bash
# Python-vs-Ruby CDK synth benchmark (RFC #939 performance FAQ evidence).
#
# Both languages are jsii guests running the identical stack (see python/app.py
# and ruby/app.rb — kept in mirror). Measures full-process wall time (what a
# `cdk synth` user experiences), peak RSS, and in-process phase breakdown
# (library load / construct / synth) reported by each app on stderr.
#
# Usage: ./run.sh [iterations]   (default 5, plus 1 discarded warmup each)
set -Eeuo pipefail
trap 'echo "FAILED at line $LINENO: $BASH_COMMAND (exit $?)" >&2' ERR
cd "$(dirname "$0")"

N="${1:-5}"
PY=python/.venv/bin/python

echo "== setup =="
if [ ! -x "$PY" ]; then
  python3 -m venv python/.venv
  "$PY" -m pip install --quiet --upgrade pip
fi
"$PY" -m pip install --quiet aws-cdk-lib
( cd ruby
  bundle config set --local path vendor/bundle >/dev/null
  bundle install --quiet
  # --prefix pins node_modules HERE: without it npm walks up to the blog repo
  # root (which has its own package.json) and installs there instead.
  [ -d node_modules/@jsii/runtime ] || npm install --prefix . --no-fund --no-audit @jsii/runtime >/dev/null
)
# NOTE: JSII_RUNTIME is scoped to the Ruby invocation below — python's jsii
# resolves its own bundled runtime, and exporting this globally would hijack it.
RUBY_JSII_RUNTIME="$PWD/ruby/node_modules/@jsii/runtime/bin/jsii-runtime"

PY_VER=$("$PY" -c 'from importlib.metadata import version; print(version("aws-cdk-lib"))')
RB_VER=$(cd ruby && bundle exec gem list aws-cdk-lib | grep -oE '[0-9][^)]*' | head -1)
echo "python aws-cdk-lib: $PY_VER  (python $("$PY" -V 2>&1 | cut -d' ' -f2))"
echo "ruby   aws-cdk-lib: $RB_VER  (ruby $(ruby -e 'print RUBY_VERSION'))"
echo "node: $(node --version)"

run_one() { # $1 = label, $2... = command; echoes "wall_s rss_kb phases_json"
  local out; out=$(mktemp -d)
  local metrics; metrics=$(mktemp)
  local phases; phases=$(mktemp)
  BENCH_OUTDIR="$out" /usr/bin/time -f '%e %M' -o "$metrics" "${@:2}" 2>"$phases" >/dev/null
  # parity data: resource count from the synthesized template
  local resources
  resources=$(python3 -c "import json,sys; t=json.load(open('$out/BenchStack.template.json')); print(len(t['Resources']))")
  echo "$(awk '{print $1"|"$2}' "$metrics")|$(grep -o '{.*}' "$phases" | tail -1)|$resources"
  rm -rf "$out" "$metrics" "$phases"
}

bench() { # $1 = label, $2... = command
  local label=$1; shift
  echo
  echo "== $label =="
  run_one "$label" "$@" >/dev/null # warmup, discarded
  local walls=() rss=()
  for i in $(seq 1 "$N"); do
    local line; line=$(run_one "$label" "$@")
    local wall; wall=$(echo "$line" | cut -d'|' -f1)
    local mem; mem=$(echo "$line" | cut -d'|' -f2)
    local phases_json; phases_json=$(echo "$line" | cut -d'|' -f3)
    local res; res=$(echo "$line" | cut -d'|' -f4)
    walls+=("$wall"); rss+=("$mem")
    echo "  run $i: wall=${wall}s rss=$((mem / 1024))MB resources=${res} phases=${phases_json}"
  done
  local median_wall; median_wall=$(printf '%s\n' "${walls[@]}" | sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}')
  local median_rss; median_rss=$(printf '%s\n' "${rss[@]}" | sort -n | awk '{a[NR]=$1} END {print int(a[int((NR+1)/2)]/1024)}')
  echo "  median: wall=${median_wall}s rss=${median_rss}MB"
}

bench "python" "$PY" python/app.py
bench "ruby" bash -c "cd '$PWD/ruby' && export JSII_RUNTIME='$RUBY_JSII_RUNTIME' && exec bundle exec ruby app.rb"

echo
echo "done — copy medians into the RFC performance FAQ with version disclosure."
