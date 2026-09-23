# macos-hardware-utilization-notifs

A tiny macOS monitor. A `launchd` agent samples CPU, memory, swap, disk, and
load every ~15 minutes, compares them against your thresholds in
`~/.macos-hun/config.json`, and pings you via
[`a2h`](https://github.com/TyrellD1/agenttohuman) only when something actually
breaches. No daemons to babysit, no sudo, no dependencies beyond `a2h`.

## Install

```bash
git clone https://github.com/TyrellD1/macos-hardware-utilization-notifs.git
cd macos-hardware-utilization-notifs
./install.sh            # installs hun + the launchd agent (every 15 min)
```

Prerequisites: [`a2h`](https://github.com/TyrellD1/agenttohuman) installed and
configured (`a2h status` should show a destination).

## The message

Built to be scannable in 5 seconds on a phone — breaches first, everything
else collapsed to one line, top processes, one plain-language hint, done:

```
⚠️ Mac hardware — 2 need attention · Ty's MacBook Pro · 15:30
🔴 Memory 91% (29.1/32 GB) — limit 85%
🟡 CPU 87% — limit 85%
✅ Swap 2.1 GB · Disk 344 GB free · Load 1.2/core — OK

Top CPU: `node 42%` · `Cursor 21%` · `mds 9%`
Top MEM: `Cursor 3.2 GB`
> Swap is climbing — quit or restart the heaviest app if this repeats.

_Next check ~15 min · cooldown 60 min · `hun status` for detail_
```

Sustained breaches re-notify at most hourly (cooldown), and you get a short
`✅ recovered` message when things settle.

## Usage

```bash
hun status                       # sample now, show table (never notifies)
hun check --force                # send the full status right now
hun test-notify                  # one canned message, proves a2h wiring

hun config show
hun config set mem_percent 90    # cpu|mem|swap|disk_free|load|interval|cooldown|recover
hun config reset

# Ping me at a time, whatever the readings:
hun remind-at "18:00" --note "wrap up and stretch"
hun remind-at "2026-09-24 09:00" --note "morning check"
hun remind-list
hun remind-cancel <id|all>

hun logs                         # what the background agent has been doing
hun history                      # every check run: metrics, verdict, notified?
hun uninstall [--purge]          # remove agent (--purge deletes ~/.macos-hun too)
```

`HH:MM` means today, or tomorrow if that time already passed (it tells you
which). Full dates in the past are rejected.

## Defaults (`~/.macos-hun/config.json`)

| Setting | Default | Why |
|---|---|---|
| `cpu_percent` | 85 | sustained 1s-sample CPU |
| `mem_percent` | 85 | wired + active + compressed / total (reclaimable memory excluded) |
| `swap_gb` | 16 | macOS pages routinely; 16 GB means real pressure on a 32 GB box |
| `disk_free_gb` | 20 | floor before macOS starts misbehaving |
| `load_per_core` | 2.0 | 1-min load average ÷ core count |
| `interval_seconds` | 900 | check every 15 min |
| `cooldown_minutes` | 60 | re-notify a sustained breach at most hourly |
| `notify_on_recovery` | true | one quiet ✅ when a breach clears |
| `log_retention_days` | 90 | how long per-run history is kept |

## How it works

- `hun` — the CLI (bash). `lib/check.sh` samples via `iostat`/`vm_stat`/
  `sysctl`/`df`/`ps`; `lib/notify.sh` builds the Discord-shaped message
  (hard-capped at 1800 chars, well under a2h's 2000 limit) and sends it.
- `launchd/dev.macos-hun.plist.template` → `~/Library/LaunchAgents/dev.macos-hun.plist`
  (`StartInterval` 900). Reminders are separate one-shot plists with a full
  `StartCalendarInterval` that clean up after firing.
- State (`last alert per metric`, `breach→ok` transitions) lives in
  `~/.macos-hun/state.json` so flapping at a threshold doesn't spam you.
- Every run appends one JSON line to `~/.macos-hun/logs/checks.jsonl`
  (~350 bytes, ~35 KB/day). Entries older than `log_retention_days` are
  pruned automatically (at most once a day, so the hot path stays a pure
  append); `hun history --purge` wipes it manually. Deleting the file is
  always safe — it's recreated on the next run.

Deliberately skipped: per-core temperature / `powermetrics` (needs sudo), GPU
stats, network throughput (too noisy on a 15-min cadence).

## Uninstall

```bash
./uninstall.sh           # removes agent + hun, keeps ~/.macos-hun
./uninstall.sh --purge   # also deletes config/state/logs
```
