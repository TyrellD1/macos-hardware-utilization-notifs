# macos-hardware-utilization-notifs — Plan

## 0. Goal
A tiny macOS monitor: a `launchd` agent runs a check ~every 15 min, compares
CPU / memory / swap / disk against user thresholds stored locally in
`~/.macos-hun/`, and notifies via [`a2h`](https://github.com/TyrellD1/agenttohuman)
only when something breaches (plus an opt-in "message me at TIME" path).
UX priority: the a2h message must be scannable in 5 seconds on a phone.

## 1. Repo layout (new public repo `TyrellD1/macos-hardware-utilization-notifs`)
```
hun                      # CLI (bash, no deps beyond python3 for JSON pretty-print, optional)
lib/check.sh             # metric collectors (sourced by hun)
lib/notify.sh            # a2h message builder + sender (sourced by hun)
launchd/dev.macos-hun.plist.template
install.sh               # copies hun to ~/.local/bin, installs LaunchAgent, writes default config
uninstall.sh             # bootout + remove plist (keeps ~/.macos-hun by default)
README.md                # install, CLI ref, message preview, uninstall
PLAN.md                  # this file
REVIEW.md                # grok 4.7 review + dispositions (added after review)
assets/hero.png          # optional hero image (only if image gen available; else skip)
```

No Homebrew deps. `a2h` must already be installed + configured (`a2h status`).

## 2. Config — `~/.macos-hun/config.json`
Created by `install.sh` with defaults; edited via CLI (never hand-edit required):
```json
{
  "interval_seconds": 900,
  "cooldown_minutes": 60,
  "thresholds": {
    "cpu_percent": 85,
    "mem_percent": 85,
    "swap_gb": 8,
    "disk_free_gb": 20,
    "load_per_core": 2.0
  },
  "notify_on_recovery": true
}
```
State (separate, CLI-managed): `~/.macos-hun/state.json`
`{ "last_alert_at": { "cpu": 0, "mem": 0, ... }, "last_status": "ok|breach", "reminders": [...] }`
Logs: `~/.macos-hun/logs/hun.{out,err}.log`

## 3. CLI spec — `hun`
| Command | Behavior |
|---|---|
| `hun status [--json]` | One-shot sample, print table vs thresholds, exit 0 ok / 2 breach. No notify. |
| `hun check [--force] [--json] [--note TEXT]` | Sample, compare, send a2h msg if breach (or if `--force`). Applies per-metric cooldown (default 60 min) so a sustained breach notifies at most hourly. Writes state. |
| `hun config show` | Pretty-print effective config + paths. |
| `hun config set <key> <value>` | Keys: `cpu_percent mem_percent swap_gb disk_free_gb load_per_core interval_seconds cooldown_minutes notify_on_recovery`. Validates ranges; re-installs LaunchAgent if interval changed. |
| `hun config reset` | Restore defaults (confirms). |
| `hun install [--interval SEC]` | Write plist from template, `bootstrap` it, persist interval to config. Idempotent. |
| `hun uninstall [--purge]` | `bootout` + remove plist. `--purge` also deletes `~/.macos-hun`. |
| `hun test-notify` | Send a canned sample alert via a2h (proves wiring without needing a real breach). |
| `hun remind-at "<HH:MM\|YYYY-MM-DD HH:MM>" [--note TEXT]` | Schedule a **one-shot** notification at TIME regardless of thresholds. Implemented as a separate one-shot LaunchAgent plist `dev.macos-hun.remind.<ts>.plist` with `StartCalendarInterval`, calling `hun check --force --note TEXT`. Prints confirmation + `remind-list` entry. Past times rejected. |
| `hun remind-list` | List pending one-shots (time + note). |
| `hun remind-cancel <id\|all>` | Bootout + delete one-shot plist(s). |
| `hun logs [-f]` | `tail` agent logs. |
| `hun --help` | Usage. |

Time parsing for `remind-at`: accept `HH:MM` (today, or tomorrow if already passed + `--tomorrow` implied with a note saying so) and `YYYY-MM-DD HH:MM`. No `at(1)` dependency.

## 4. Metric collection (`lib/check.sh`, macOS-native only)
- **CPU %**: sample `ps -A -o %cpu` sum / `hw.ncpu`, 1s `iostat -c 1 -w 1` fallback. Cheap, no sudo.
- **Memory %**: `vm_stat` + `hw.memsize` → `(wired+active+inactive+speculative+compressed)/total`. Report `used/total GB`.
- **Swap used GB**: `sysctl vm.swapusage` parse.
- **Disk free GB + %**: `df -k /`.
- **Load per core**: `sysctl -n vm.loadavg` 1-min / `hw.ncpu`.
- **Top offenders**: `ps -Ao pid,comm,%cpu,%mem` top 3 by CPU and top 1 by mem (comm truncated to 24 chars).
- Skip by design (document in README): per-core temp / powermetrics (needs sudo), GPU %, network throughput (noisy on 15-min cadence). Revisit only if asked.

Sampling budget: whole check < 5s.

## 5. a2h message design (the UX core, Discord markdown, ≤1800 chars hard cap)
`lib/notify.sh build_message` produces:

```
⚠️ **Mac hardware — 2 need attention** · MacBook · 15:30
🔴 **Memory** 91% (29.1/32 GB) — limit 85%
🟡 **CPU** 87% — limit 85%
✅ Swap 2.1 GB · Disk 344 GB free · Load 1.2/core — OK

Top CPU: `node 42%` · `Cursor 21%` · `mds 9%`
Top MEM: `Cursor 3.2 GB`
> Swap is climbing — quit or restart the heaviest app if this repeats.

_Next check ~15 min · cooldown 60 min · `hun status` for detail_
```

Rules:
- Title line: severity emoji (🔴 any critical / ⚠️ any breach / 🟢 forced all-clear), count, hostname (short), time.
- One line per breached metric: emoji + bold name + current (human units) + "— limit X". Breaches sorted worst-first, capped at 5.
- One collapsed OK line for the rest (no per-metric spam).
- Top-processes line(s), truncated to fit cap.
- One plain-language hint line (per worst metric: e.g. memory→quit heaviest app; disk→empty trash/caches; cpu→check runaway helper).
- Footer: next-check cadence, cooldown, `hun status` pointer. For `--force`/reminder: prefix `⏰ Reminder — as requested` + user note, then full status table regardless of thresholds.
- Recovery: if previous state was breach and now all OK and `notify_on_recovery=true`, send `✅ **Mac hardware recovered** …` (same compact shape).
- Never exceed 1800 chars: truncate process names first, then drop hint, then drop OK line. `a2h send` gets the whole body as one message (Discord 2000 limit respected).
- `--dry-run` env (`HUN_DRY_RUN=1`) prints instead of sending (used by tests).

## 6. launchd spec
- Template `launchd/dev.macos-hun.plist.template` → installed to `~/Library/LaunchAgents/dev.macos-hun.plist`.
  - `Label: dev.macos-hun`, `ProgramArguments: [<home>/.local/bin/hun, check]`, `StartInterval: 900` (from config), `RunAtLoad: false`, `StandardOutPath/StandardErrorPath` under `~/.macos-hun/logs/`, `ThrottleInterval: 60`.
- `hun install` renders template with `sed` (interval + paths), `launchctl bootstrap gui/$UID`, `kickstart -k` optional smoke. `hun check` is idempotent + fast so overlapping runs are harmless.
- One-shot reminders: separate plists `dev.macos-hun.remind.<epoch>.plist` with `StartCalendarInterval {Hour,Minute,(Day,Month,Year)}`; the job runs `hun check --force`, then self-removes its plist on success (best-effort; `remind-cancel` is the manual path).

## 7. Edge cases
- `a2h` missing/unconfigured → `hun check` exits 3 with `run: a2h init …` hint; launchd logs it, no crash loop.
- Discord 2000-char limit → our 1800 cap + `a2h`'s own guard; on reject, log + exit 4.
- Lid-closed/sleep → launchd coalesces; no backlog storm (no `ThrottleInterval` abuse, no catch-up queue).
- Flapping at threshold → cooldown per metric (60 min default) + recovery msg only on breach→ok transition.

## 8. Verification
1. `shellcheck hun lib/*.sh` (if available) + `bash -n`.
2. `hun status`, `hun config show`, `HUN_DRY_RUN=1 hun check --force` (inspect formatted msg).
3. Temporarily `hun config set cpu_percent 1` → `HUN_DRY_RUN=1 hun check` must show breach msg; set back.
4. `hun test-notify` → real a2h delivery (only step that pings Discord; run once).
5. `hun install && launchctl list | grep macos-hun`, `hun remind-at` with +2 min future time → expect forced msg → `remind-list` empty after fire.
6. Fresh-machine sanity: `uninstall.sh` then `install.sh` on clean `~/.macos-hun`.

## 9. Build order
1. `lib/check.sh` + `lib/notify.sh` + `hun` (status/check/config/test-notify/logs).
2. launchd template + `install.sh`/`uninstall.sh` + `install`/`uninstall` subcommands.
3. `remind-at/list/cancel` one-shots.
4. README (install, thresholds table, message preview, FAQ) + hero image iff generatable.
5. Push to GitHub, `gh repo view` sanity.

## 10. Non-goals
No sudo, no Swift binary, no Sparkle/auto-update, no multi-Mac fan-out, no Prometheus endpoint. If thresholds need per-time-of-day profiles, that's a later plan.
