#!/usr/bin/env bash
# Pushes the placeholder gems built by generate.rb to rubygems.org.
#
# Prerequisites (see README.md): a rubygems.org account, MFA enabled, and a
# signed-in credential (`gem signin`). Each push will prompt for an OTP when
# MFA is set to "UI and API" — that is expected; there are 8 of them.
set -euo pipefail

cd "$(dirname "$0")"

if ! ls pkg/*.gem >/dev/null 2>&1; then
  echo "No built gems found — run: ruby generate.rb" >&2
  exit 1
fi

echo "== Re-checking availability (abort rather than collide with a squatter) =="
taken=0
for gem_file in pkg/*.gem; do
  name=$(basename "$gem_file" | sed 's/-0\.0\.0\.pre\.reserved\.1\.gem$//')
  code=$(curl -s -o /dev/null -w '%{http_code}' "https://rubygems.org/api/v1/gems/${name}.json")
  if [ "$code" = "200" ]; then
    echo "  ${name}: ALREADY TAKEN — investigate before pushing anything"
    taken=1
  else
    echo "  ${name}: available (${code})"
  fi
done
[ "$taken" = "1" ] && exit 1

echo
echo "== Pushing =="
for gem_file in pkg/*.gem; do
  echo "--- gem push ${gem_file}"
  gem push "$gem_file"
done

echo
echo "== Verifying ownership =="
sleep 5
for gem_file in pkg/*.gem; do
  name=$(basename "$gem_file" | sed 's/-0\.0\.0\.pre\.reserved\.1\.gem$//')
  code=$(curl -s -o /dev/null -w '%{http_code}' "https://rubygems.org/api/v1/gems/${name}.json")
  # Prerelease-only gems report 404 on the default endpoint; the versions
  # endpoint shows them.
  vcode=$(curl -s -o /dev/null -w '%{http_code}' "https://rubygems.org/api/v1/versions/${name}.json")
  echo "  ${name}: gems=${code} versions=${vcode} (versions=200 means the push landed)"
done

echo
echo "Done. Record the date in the RFC's Gem name governance section."
