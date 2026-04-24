#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .sisyphus/evidence

SCRIPTS=$(ls tests/qa/AC*.lua 2>/dev/null | sort)
PASS=0
FAIL=0

for script in $SCRIPTS; do
  AC=$(basename "$script" .lua)
  EVIDENCE=".sisyphus/evidence/qa-$AC.txt"
  rm -f "$EVIDENCE"
  nvim --headless --noplugin -u tests/qa/minimal_init.lua \
    -c "lua vim.defer_fn(function() vim.cmd('qa!') end, 5000)" \
    -c "luafile $script" > "/tmp/qa-$AC.log" 2>&1
  if [ -f "$EVIDENCE" ] && head -1 "$EVIDENCE" | grep -q '^PASS:'; then
    echo "PASS: $AC"
    PASS=$((PASS+1))
  else
    echo "FAIL: $AC -- see /tmp/qa-$AC.log and $EVIDENCE"
    cat "$EVIDENCE" 2>/dev/null || echo "(no evidence file)"
    FAIL=$((FAIL+1))
  fi
done

echo "----"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
