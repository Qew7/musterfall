#!/usr/bin/env bash
# After an agent turn: if the backend submodule has dirty Ruby/Rake files,
# run leftover pre-commit (rubocop + leftovers). On failure, follow up so the
# agent must fix before stopping.
#
# Full leftover pre-push (minitest) is intentionally NOT auto-run here: the
# suite is slow and a dirty WIP tree would loop-fail every turn. The project
# rule asks the agent to run pre-push when behavior under app/test/ext/lib
# changes.

set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo '{}'; exit 0; }
cd "$ROOT" || { echo '{}'; exit 0; }

INPUT="$(cat)"
STATUS="$(python3 -c '
import json, sys
try:
    d = json.loads(sys.argv[1] or "{}")
except Exception:
    d = {}
print(d.get("status") or "")
' "$INPUT")"
LOOP_COUNT="$(python3 -c '
import json, sys
try:
    d = json.loads(sys.argv[1] or "{}")
except Exception:
    d = {}
print(int(d.get("loop_count") or 0))
' "$INPUT")"

if [ "$STATUS" != "completed" ]; then
  echo '{}'
  exit 0
fi

# backend/ is a git submodule — dirty files live in that repo.
DIRTY="$(git -C backend status --porcelain --untracked-files=all \
  | awk '{
      path=$2
      if ($1 ~ /^R/ && NF>=3) path=$NF
      sub(/^"/, "", path); sub(/"$/, "", path)
      if (path != "") print path
    }' | sort -u)"

if [ -z "$DIRTY" ]; then
  echo '{}'
  exit 0
fi

RUBY_FILES=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    *.rb|*.rake)
      if [ -z "$RUBY_FILES" ]; then
        RUBY_FILES="backend/$f"
      else
        RUBY_FILES="$RUBY_FILES
backend/$f"
      fi
      ;;
  esac
done <<EOF
$DIRTY
EOF

if [ -z "$RUBY_FILES" ]; then
  echo '{}'
  exit 0
fi

export BUNDLE_GEMFILE="$ROOT/backend/Gemfile"
LEFTHOOK="$(bundle exec ruby -e 'print Gem.bin_path("lefthook", "lefthook")' 2>/dev/null)" || {
  echo '{}'
  exit 0
}

set -- "$LEFTHOOK" run pre-commit --no-tty --colors off --no-auto-install
while IFS= read -r f; do
  [ -z "$f" ] && continue
  set -- "$@" --file "$f"
done <<EOF
$RUBY_FILES
EOF

OUT="$("$@" 2>&1)"
RC=$?

if [ "$RC" -eq 0 ]; then
  echo '{}'
  exit 0
fi

if [ "${LOOP_COUNT:-0}" -ge 3 ]; then
  echo '{}'
  exit 0
fi

FAILURES="$(printf '%s\n' "$OUT" | tail -n 80)"
python3 -c '
import json, sys
msg = """Lefthook pre-commit failed after your backend Ruby changes. Fix the root cause, re-run leftover pre-commit, then stop.

If you changed behavior under backend/app, backend/test, backend/ext, or backend/lib, also run leftover pre-push (minitest) before claiming done.

""" + "```\n" + sys.argv[1] + "\n```"
print(json.dumps({"followup_message": msg}, ensure_ascii=False))
' "$FAILURES"
exit 0
