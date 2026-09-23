#!/bin/bash
# lib/check.sh — macOS-native metric collectors. Sourced by `hun`.
# Sets globals: HUN_CPU, HUN_MEM_PCT, HUN_MEM_USED_GB, HUN_MEM_TOTAL_GB,
# HUN_SWAP_GB, HUN_DISK_FREE_GB, HUN_DISK_PCT, HUN_LOAD_PER_CORE,
# HUN_NCPU, HUN_TOP_CPU, HUN_TOP_MEM, HUN_HOST, HUN_TIME.
# Returns 0 on success, 1 if sampling failed.

hun_collect() {
  HUN_NCPU="$(sysctl -n hw.ncpu 2>/dev/null || echo 1)"
  HUN_HOST="$(scutil --get ComputerName 2>/dev/null || hostname -s 2>/dev/null || echo Mac)"
  HUN_HOST="${HUN_HOST%%.*}"
  HUN_TIME="$(date '+%H:%M')"

  # --- CPU %: second report of iostat is the fresh 1s sample (first is since-boot).
  # macOS iostat -c columns: disk0(KB/t tps MB/s) cpu(us sy id) load(1m 5m 15m)
  local iostat_out us sy
  iostat_out="$(iostat -c 2 -w 1 2>/dev/null | tail -1)"
  us="$(echo "$iostat_out" | awk '{print $(NF-5)}')"
  sy="$(echo "$iostat_out" | awk '{print $(NF-4)}')"
  if [[ "$us" =~ ^[0-9]+$ && "$sy" =~ ^[0-9]+$ ]]; then
    HUN_CPU=$((us + sy))
  else
    # Fallback: sum ps %cpu over cores (lifetime average — coarse but harmless).
    local total
    total="$(ps -A -o %cpu 2>/dev/null | awk '{s+=$1} END {print int(s)}')"
    HUN_CPU=$(( ${total:-0} / HUN_NCPU ))
  fi

  # --- Memory %: (wired + active + compressor-occupied) x pagesize / memsize.
  # Excludes inactive/speculative (reclaimable) so healthy machines don't read full.
  local page_size memsize free_p active_p wired_p comp_p
  page_size="$(vm_stat 2>/dev/null | head -1 | grep -oE '[0-9]+' || echo 16384)"
  memsize="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
  active_p="$(vm_stat | awk '/Pages active:/ {gsub(/\./,"",$3); print $3}')"
  wired_p="$(vm_stat | awk '/Pages wired down:/ {gsub(/\./,"",$4); print $4}')"
  comp_p="$(vm_stat | awk '/Pages occupied by compressor:/ {gsub(/\./,"",$5); print $5}')"
  if [[ -n "$active_p" && -n "$wired_p" && "$memsize" -gt 0 ]]; then
    comp_p="${comp_p:-0}"
    local used_bytes
    used_bytes=$(( (active_p + wired_p + comp_p) * page_size ))
    HUN_MEM_PCT=$(( used_bytes * 100 / memsize ))
    HUN_MEM_USED_GB="$(awk -v b="$used_bytes" 'BEGIN {printf "%.1f", b/1073741824}')"
    HUN_MEM_TOTAL_GB="$(awk -v b="$memsize" 'BEGIN {printf "%.0f", b/1073741824}')"
  else
    return 1
  fi

  # --- Swap used GB: vm.swapusage flips between M and G — honor the suffix.
  local swap_raw swap_num swap_unit
  swap_raw="$(sysctl -n vm.swapusage 2>/dev/null | grep -oE 'used = [0-9.]+[MG]' | grep -oE '[0-9.]+[MG]')"
  swap_num="$(echo "$swap_raw" | grep -oE '[0-9.]+')"
  swap_unit="$(echo "$swap_raw" | grep -oE '[MG]')"
  if [[ -z "$swap_num" ]]; then return 1; fi
  if [[ "$swap_unit" == "M" ]]; then
    HUN_SWAP_GB="$(awk -v m="$swap_num" 'BEGIN {printf "%.1f", m/1024}')"
  else
    HUN_SWAP_GB="$swap_num"
  fi

  # --- Disk: free GB + used % of /.
  local df_line
  df_line="$(df -k / 2>/dev/null | tail -1)"
  HUN_DISK_FREE_GB="$(echo "$df_line" | awk '{printf "%.0f", $4/1048576}')"
  HUN_DISK_PCT="$(echo "$df_line" | awk '{gsub(/%/,"",$5); print $5}')"
  if [[ -z "$HUN_DISK_FREE_GB" ]]; then return 1; fi

  # --- Load per core (1-min avg / ncpu).
  local load1
  load1="$(sysctl -n vm.loadavg 2>/dev/null | grep -oE '\{ [0-9.]+' | grep -oE '[0-9.]+')"
  HUN_LOAD_PER_CORE="$(awk -v l="${load1:-0}" -v n="$HUN_NCPU" 'BEGIN {printf "%.1f", l/n}')"

  # --- Top offenders. rss (KB) -> GB for memory; comm truncated to 24 chars.
  # ucomm = short process name (no path prefix); parse the number from the right
  # so names containing spaces don't shift fields.
  HUN_TOP_CPU="$(ps -Ao ucomm=,%cpu= 2>/dev/null | awk '{c=$NF+0; n=$0; sub(/[ \t]+[0-9.]+[ \t]*$/,"",n); sub(/^ +/,"",n); printf "%.1f\t%s\n", c, substr(n,1,24)}' | sort -rn | head -3 | awk -F'\t' '{printf "%s %.0f%%; ", $2, $1}' | sed 's/; $//')"
  HUN_TOP_MEM="$(ps -Ao ucomm=,rss= 2>/dev/null | awk '{r=$NF+0; n=$0; sub(/[ \t]+[0-9]+[ \t]*$/,"",n); sub(/^ +/,"",n); printf "%d\t%s\n", r, substr(n,1,24)}' | sort -rn | head -1 | awk -F'\t' '{printf "%s %.1f GB", $2, $1/1048576}')"

  return 0
}
