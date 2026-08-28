#!/bin/bash
# Claude Code status line that also feeds SideNotch.
#
# Claude Code pipes a JSON blob describing the session to this script on stdin
# (see code.claude.com/docs/en/statusline). We stash it under
# ~/.sidenotch/sessions/<session_id>.json for SideNotch to read, then print an
# ordinary status line so the terminal keeps working as usual.
#
# Install: chmod +x this file, then add to ~/.claude/settings.json:
#   { "statusLine": { "type": "command",
#                     "command": "~/SideNotch/scripts/statusline-sidenotch.sh",
#                     "refreshInterval": 60000 } }
set -uo pipefail

DIR="${SIDENOTCH_DIR:-$HOME/.sidenotch}/sessions"
mkdir -p "$DIR"

input=$(cat)
[ -n "$input" ] || exit 0

session=$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null) || exit 0

# Write atomically so SideNotch never reads a half-written file.
tmp=$(mktemp "$DIR/.tmp.XXXXXX") || exit 0
printf '%s' "$input" > "$tmp" && mv -f "$tmp" "$DIR/${session}.json"

# Forget sessions we have not heard from in a day.
find "$DIR" -name '*.json' -mtime +1 -delete 2>/dev/null

# ---- the visible status line ------------------------------------------------
printf '%s' "$input" | jq -r '
  [ "[" + (.model.display_name // "?") + "]",
    ((.workspace.current_dir // .cwd // "") | split("/") | last),
    (if .context_window.used_percentage != null
       then "\(.context_window.used_percentage | floor)% ctx" else empty end),
    (if .rate_limits.five_hour.used_percentage != null
       then "\(.rate_limits.five_hour.used_percentage | floor)% session" else empty end),
    (if (.cost.total_cost_usd // 0) > 0
       then "$\((.cost.total_cost_usd * 100 | round) / 100)" else empty end)
  ] | map(select(. != null and . != "")) | join(" | ")
'
