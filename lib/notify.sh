#!/bin/bash
# lib/notify.sh — digestible a2h message builder + sender. Sourced by `hun`.
# Expects globals from lib/check.sh + config thresholds.
#   hun_build_message <mode> [note]   # mode: breach|recovery|forced
# Sets HUN_MSG. hun_send_message sends via a2h (honors HUN_DRY_RUN=1).
HUN_MSG_MAX=1800

# hun_breach_list populates HUN_BREACHES ("key|label|current|limit" lines) and
# HUN_OK_LINE (single-line summary of everything within limits).
hun_breach_list() {
  HUN_BREACHES=""
  local ok_parts=()
  local t_cpu t_mem t_swap t_disk t_load
  t_cpu="$(hun_cfg thresholds.cpu_percent)"; t_mem="$(hun_cfg thresholds.mem_percent)"
  t_swap="$(hun_cfg thresholds.swap_gb)"; t_disk="$(hun_cfg thresholds.disk_free_gb)"
  t_load="$(hun_cfg thresholds.load_per_core)"

  if awk -v a="$HUN_CPU" -v b="$t_cpu" 'BEGIN {exit !(a>=b)}'; then
    HUN_BREACHES+="cpu|CPU|${HUN_CPU}%|${t_cpu}%${NL}"
  else ok_parts+=("CPU ${HUN_CPU}%"); fi

  if awk -v a="$HUN_MEM_PCT" -v b="$t_mem" 'BEGIN {exit !(a>=b)}'; then
    HUN_BREACHES+="mem|Memory|${HUN_MEM_PCT}% (${HUN_MEM_USED_GB}/${HUN_MEM_TOTAL_GB} GB)|${t_mem}%${NL}"
  else ok_parts+=("Memory ${HUN_MEM_PCT}%"); fi

  if awk -v a="$HUN_SWAP_GB" -v b="$t_swap" 'BEGIN {exit !(a>=b)}'; then
    HUN_BREACHES+="swap|Swap|${HUN_SWAP_GB} GB|${t_swap} GB${NL}"
  else ok_parts+=("Swap ${HUN_SWAP_GB} GB"); fi

  if awk -v a="$HUN_DISK_FREE_GB" -v b="$t_disk" 'BEGIN {exit !(a<b)}'; then
    HUN_BREACHES+="disk|Disk free|${HUN_DISK_FREE_GB} GB|${t_disk} GB${NL}"
  else ok_parts+=("Disk ${HUN_DISK_FREE_GB} GB free"); fi

  if awk -v a="$HUN_LOAD_PER_CORE" -v b="$t_load" 'BEGIN {exit !(a>=b)}'; then
    HUN_BREACHES+="load|Load|${HUN_LOAD_PER_CORE}/core|${t_load}/core${NL}"
  else ok_parts+=("Load ${HUN_LOAD_PER_CORE}/core"); fi

  if [[ ${#ok_parts[@]} -gt 0 ]]; then
    HUN_OK_LINE="$(IFS=' · '; echo "${ok_parts[*]}") — OK"
  else
    HUN_OK_LINE=""
  fi
}

hun_hint_for() {
  case "$1" in
    mem)  echo "Memory is climbing — quit or restart the heaviest app if this repeats." ;;
    cpu)  echo "CPU is hot — check for a runaway helper in Activity Monitor." ;;
    swap) echo "Swap is heavy — macOS is paging; closing big apps will relieve it." ;;
    disk) echo "Disk is getting full — empty Trash and prune caches to stay safe." ;;
    load) echo "Load is high — something is queueing hard; give it a few minutes." ;;
    *)    echo "" ;;
  esac
}

hun_build_message() {
  local mode="$1" note="$2"
  local interval interval_min cooldown
  interval="$(hun_cfg interval_seconds)"; interval_min=$((interval / 60))
  cooldown="$(hun_cfg cooldown_minutes)"
  local title body breach_count worst hint
  breach_count="$(printf '%s' "$HUN_BREACHES" | grep -c . || true)"
  worst="$(printf '%s' "$HUN_BREACHES" | head -1 | cut -d'|' -f1)"

  case "$mode" in
    breach)
      if [[ "$breach_count" -gt 1 ]]; then
        title="⚠️ **Mac hardware — $breach_count need attention** · $HUN_HOST · $HUN_TIME"
      else
        title="⚠️ **Mac hardware alert** · $HUN_HOST · $HUN_TIME"
      fi
      ;;
    recovery) title="✅ **Mac hardware recovered** · $HUN_HOST · $HUN_TIME" ;;
    forced)   title="⏰ **Mac hardware status — as requested** · $HUN_HOST · $HUN_TIME" ;;
  esac

  body="$title"
  [[ -n "$note" ]] && body+="${NL}> $note"

  if [[ "$mode" == "forced" ]]; then
    body+="${NL}🔹 **CPU** ${HUN_CPU}% · 🔹 **Memory** ${HUN_MEM_PCT}% (${HUN_MEM_USED_GB}/${HUN_MEM_TOTAL_GB} GB)"
    body+="${NL}🔹 **Swap** ${HUN_SWAP_GB} GB · 🔹 **Disk** ${HUN_DISK_FREE_GB} GB free · 🔹 **Load** ${HUN_LOAD_PER_CORE}/core"
  else
    while IFS='|' read -r key label cur lim; do
      [[ -z "$key" ]] && continue
      local emoji="🟡"
      [[ "$key" == "mem" || "$key" == "disk" ]] && emoji="🔴"
      body+="${NL}${emoji} **${label}** ${cur} — limit ${lim}"
    done <<< "$(printf '%s' "$HUN_BREACHES")"
    [[ -n "$HUN_OK_LINE" ]] && body+="${NL}✅ $HUN_OK_LINE"
  fi

  [[ -n "$HUN_TOP_CPU" ]] && body+="${NL}${NL}Top CPU: \`$HUN_TOP_CPU\`"
  [[ -n "$HUN_TOP_MEM" ]] && body+="${NL}Top MEM: \`$HUN_TOP_MEM\`"

  if [[ "$mode" == "breach" ]]; then
    hint="$(hun_hint_for "$worst")"
    [[ -n "$hint" ]] && body+="${NL}> $hint"
  fi
  body+="${NL}${NL}_Next check ~${interval_min} min · cooldown ${cooldown} min · \`hun status\` for detail_"

  # Hard cut to HUN_MSG_MAX Unicode chars — notes and forced tables can't
  # sneak past Discord's 2000 limit (review #6).
  if command -v python3 >/dev/null 2>&1; then
    HUN_MSG="$(printf '%s' "$body" | python3 -c "import sys; s=sys.stdin.read(); print(s[:$HUN_MSG_MAX])")"
  else
    HUN_MSG="$(printf '%s' "$body" | cut -c1-$HUN_MSG_MAX)"
  fi
}

# Resolve a2h across launchd's minimal PATH plus the usual install spots.
hun_find_a2h() {
  local IFS=:
  for d in "$HOME/.local/bin" /opt/homebrew/bin /usr/local/bin /usr/bin /bin; do
    [[ -x "$d/a2h" ]] && { echo "$d/a2h"; return 0; }
  done
  return 1
}

hun_send_message() {
  local a2h_bin
  if [[ "${HUN_DRY_RUN:-0}" == "1" ]]; then
    printf '%s\n' "$HUN_MSG"
    return 0
  fi
  a2h_bin="$(hun_find_a2h)" || {
    echo "hun: a2h not found. Install it and run: a2h init" >&2
    return 3
  }
  "$a2h_bin" send "$HUN_MSG" || return 4
  return 0
}
