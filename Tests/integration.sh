#!/bin/bash
# End-to-end run of the command line over a temporary folder of files. Spotlight is bypassed
# (ASKMAC_WALK=1) so the run does not depend on indexing state; nothing real is read.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="${BIN:-.build/debug/AskMac}"
[ -x "$BIN" ] || swift build >/dev/null
export ASKMAC_HOME="$(mktemp -d)" ASKMAC_WALK=1
trap 'rm -rf "$ASKMAC_HOME"' EXIT
printf 'Residential lease.\n\nSecurity deposit: $2,400, due at signing. Rent $1,950 per month.\n' > "$ASKMAC_HOME/Lease.txt"
printf '# Dentist\n\nCrown, lower molar: 1,150.00\n' > "$ASKMAC_HOME/Dentist invoice.md"
pass=0; fail=0
check() { if eval "$2"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; echo "  command: $2"; fi; }
check "version" '"$BIN" version | grep -q askmac'
check "help exits 0" '"$BIN" help >/dev/null'
check "answers the deposit question" '"$BIN" lease deposit --quote | grep -q "2,400"'
check "names the source" '"$BIN" lease deposit --quote | grep -q "Lease"'
check "json has sources" '"$BIN" dentist crown --json | grep -q "\"title\" : \"Dentist invoice\""'
check "nothing found exits 1" '"$BIN" submarine periscope >/dev/null 2>&1; [ $? = 1 ]'
check "status runs" '"$BIN" status --json | grep -q folders'
check "folders lists the test home" '"$BIN" folders | grep -q "$ASKMAC_HOME"'
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
