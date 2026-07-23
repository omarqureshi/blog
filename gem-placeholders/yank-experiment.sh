#!/usr/bin/env bash
# Empirical test of rubygems.org yank semantics, on a throwaway gem name.
#
# Question this answers (for the aws/aws-cdk-rfcs#939 name-governance
# discussion): if a placeholder gem is yanked, what actually happens to the
# name? Does the owner keep it? Can the owner re-push? Is the yanked version
# burned? Every step captures raw API evidence into a timestamped log that
# can be shared verbatim.
#
# Protocol:
#   1. reserve   — build + push omars-test-gem 0.0.0.pre.reserved.1
#                  (same shape as the real placeholders: prerelease version,
#                  LoadError stub, rubygems_mfa_required metadata)
#   2. yank      — gem yank the only version (name becomes fully yanked)
#   3. re-check  — (a) re-push the SAME version: expected to be rejected
#                  (yanked versions are burned), (b) push a NEW version
#                  .reserved.2: tests whether the owner can still use the name
#   4. cleanup   — yank .reserved.2 too, leaving the name fully yanked
#
# Ownership continuity is captured via the public owners endpoint before and
# after each yank.
#
# MUST RUN INTERACTIVELY: the gem carries rubygems_mfa_required, so yank and
# re-push prompt for an OTP. Run it from a terminal (in a Claude session:
# `! gem-placeholders/yank-experiment.sh`).
#
# Limitation stated up front: with a single account we cannot test whether a
# *different* account could claim the fully-yanked name. The owners-endpoint
# evidence is the proxy: if ownership persists after full yank, the name is
# not up for grabs.
set -euo pipefail
cd "$(dirname "$0")"

NAME="${NAME:-omars-test-gem}"
V1="0.0.0.pre.reserved.1"
V2="0.0.0.pre.reserved.2"
RFC_URL="https://github.com/aws/aws-cdk-rfcs/pull/939"
LOG="yank-experiment-$(date +%Y%m%d-%H%M%S).log"

# ---- safety guard: never operate on a real reserved name -------------------
case "$NAME" in
  aws-*|jsii*|constructs*)
    echo "REFUSING: '$NAME' matches a protected reserved name." >&2
    exit 1
    ;;
esac

log() { printf '%s\n' "$*" | tee -a "$LOG"; }
run() { log ""; log "\$ $*"; "$@" 2>&1 | tee -a "$LOG"; }

capture() { # capture <label> <url>  — log status code + body
  local label=$1 url=$2 body code
  body=$(curl -s -w '\n%{http_code}' "$url")
  code=${body##*$'\n'}
  body=${body%$'\n'*}
  log ""
  log "== $label"
  log "GET $url -> HTTP $code"
  log "$body"
  echo "$code"
}

wait_for() { # wait_for <expected-code> <url> <what>  — poll up to 3 minutes
  local expected=$1 url=$2 what=$3 code
  for _ in $(seq 1 36); do
    code=$(curl -s -o /dev/null -w '%{http_code}' "$url")
    [ "$code" = "$expected" ] && { log "  $what: reached HTTP $expected"; return 0; }
    sleep 5
  done
  log "  $what: TIMED OUT waiting for HTTP $expected (last: $code) — continuing, check manually"
  return 0
}

GEMS_URL="https://rubygems.org/api/v1/gems/${NAME}.json"
VERSIONS_URL="https://rubygems.org/api/v1/versions/${NAME}.json"
OWNERS_URL="https://rubygems.org/api/v1/gems/${NAME}/owners.json"

log "rubygems.org yank-semantics experiment — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
log "gem name: $NAME   versions: $V1 -> yank -> $V2 -> yank"

# ---- phase 0: preflight ----------------------------------------------------
log ""
log "#### PHASE 0: preflight"
gemcode=$(capture "name availability (gems endpoint)" "$GEMS_URL")
vercode=$(capture "name availability (versions endpoint)" "$VERSIONS_URL")
if [ "$gemcode" = "200" ] || [ "$vercode" = "200" ]; then
  log "'$NAME' already exists on rubygems.org."
  log "If this is a previous run of this experiment, delete/skip manually; refusing to guess."
  exit 1
fi

# ---- gem generation (same shape as generate.rb's placeholders) -------------
build_gem() { # build_gem <version> -> pkg path in $BUILT
  local version=$1 dir="build/$NAME"
  rm -rf "$dir"; mkdir -p "$dir/lib" pkg
  cat > "$dir/README.md" <<MD
# $NAME (yank-semantics test)

This gem is a **temporary, throwaway experiment** measuring what
rubygems.org does when a placeholder gem is yanked (ownership retention,
version burning, re-push behaviour). It exists to inform the gem-name
governance discussion in [aws/aws-cdk-rfcs#939]($RFC_URL) and will be
yanked as the final step of the experiment. It contains no functional code.
MD
  cat > "$dir/lib/$NAME.rb" <<RB
# frozen_string_literal: true

# Throwaway yank-semantics experiment for $RFC_URL. No code.
raise LoadError, "'$NAME' is a temporary rubygems.org behaviour test (see $RFC_URL); it contains no code."
RB
  cat > "$dir/$NAME.gemspec" <<SPEC
# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = "$NAME"
  s.version     = "$version"
  s.summary     = "Temporary yank-semantics experiment (aws/aws-cdk-rfcs#939)"
  s.description = "Throwaway gem measuring rubygems.org yank behaviour (ownership retention, version burning) to inform the AWS CDK Ruby bindings name-governance discussion ($RFC_URL). Will be yanked."
  s.authors     = ["Omar Qureshi"]
  s.email       = ["omar@omarqureshi.net"]
  s.homepage    = "$RFC_URL"
  s.license     = "Apache-2.0"
  s.files       = ["lib/$NAME.rb", "README.md"]
  s.metadata    = {
    "rubygems_mfa_required" => "true",
    "homepage_uri" => "$RFC_URL",
  }
end
SPEC
  BUILT="pkg/$NAME-$version.gem"
  (cd "$dir" && gem build "$NAME.gemspec" --output "../../$BUILT" >/dev/null)
  log "built $BUILT"
}

# ---- phase 1: reserve ------------------------------------------------------
log ""
log "#### PHASE 1: reserve (push $V1)"
build_gem "$V1"
run gem push "$BUILT"
wait_for 200 "$VERSIONS_URL" "push indexed"
capture "post-push versions" "$VERSIONS_URL" >/dev/null
capture "post-push owners" "$OWNERS_URL" >/dev/null

# ---- phase 2: yank ---------------------------------------------------------
log ""
log "#### PHASE 2: yank $V1 (name becomes fully yanked)"
run gem yank "$NAME" -v "$V1"
wait_for 404 "$VERSIONS_URL" "yank reflected"
capture "post-yank gems endpoint" "$GEMS_URL" >/dev/null
capture "post-yank versions endpoint" "$VERSIONS_URL" >/dev/null
capture "post-yank owners endpoint (KEY EVIDENCE: does ownership persist?)" "$OWNERS_URL" >/dev/null

# ---- phase 3: can we reserve again? ----------------------------------------
log ""
log "#### PHASE 3a: re-push the SAME version (expected: rejected — yanked versions are burned)"
set +e
run gem push "$BUILT"
same_version_rc=$?
set -e
log "re-push of $V1 exit code: $same_version_rc (non-zero expected)"

log ""
log "#### PHASE 3b: push a NEW version $V2 (tests whether the owner can still use the name)"
build_gem "$V2"
run gem push "$BUILT"
wait_for 200 "$VERSIONS_URL" "re-reservation indexed"
capture "post-re-push versions" "$VERSIONS_URL" >/dev/null
capture "post-re-push owners" "$OWNERS_URL" >/dev/null

# ---- phase 4: cleanup ------------------------------------------------------
log ""
log "#### PHASE 4: cleanup (yank $V2; final state = fully-yanked, still owned)"
run gem yank "$NAME" -v "$V2"
wait_for 404 "$VERSIONS_URL" "cleanup yank reflected"
capture "final gems endpoint" "$GEMS_URL" >/dev/null
capture "final versions endpoint" "$VERSIONS_URL" >/dev/null
capture "final owners endpoint" "$OWNERS_URL" >/dev/null

log ""
log "#### DONE — evidence in $LOG"
log "Interpretation guide:"
log "  * owners endpoint returning the owner after full yank => yanking does NOT release the name"
log "  * phase 3a rejection => yanked version numbers are permanently burned"
log "  * phase 3b success  => the owner can re-establish a placeholder at any time"
log "  * single-account limitation: whether a THIRD PARTY could claim the fully-"
log "    yanked name is not directly testable here; the owners evidence is the proxy."
