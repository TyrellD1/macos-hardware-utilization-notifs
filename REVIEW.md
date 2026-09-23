# Plan review — grok-4.7-high-fast (via `agent -p --trust`)

> Note: `grok-4.7-high` was capacity-exhausted (`resource_exhausted` on 3
> attempts), so the review ran on `grok-4.7-high-fast` — same model, same
> high-effort tier. `auto` ping confirmed the API itself was healthy.

Grok returned 8 findings. Disposition: **accepted all 8**. No rejections —
each was a genuine correctness/robustness bug. Details and what changed:

## 1. Memory formula counts inactive/speculative, ignores pagesize — ACCEPTED
`inactive + speculative + compressor-stored` made memory read near-full
always; missing `× pagesize` (16 KB on Apple silicon) made units wrong.
**Fix:** `used = (wired + active + occupied_by_compressor) × pagesize /
hw.memsize` in `lib/check.sh`.

## 2. CPU from `ps %cpu` / first `iostat` line is stale — ACCEPTED
`ps %cpu` is a lifetime average (can exceed 100%); `iostat -c 1` prints only
the since-boot line.
**Fix:** second report of `iostat -c 2 -w 1`, `used = us + sy`.

## 3. Swap units + `%mem`-as-GB — ACCEPTED
`vm.swapusage` flips between `M`/`G`; `ps %mem` is a percent, message showed GB.
**Fix:** honor the suffix when parsing swap; use `rss` (KB → GB) for top-memory.

## 4. launchd env: PATH, log dir, re-bootstrap — ACCEPTED
launchd's minimal PATH wouldn't find `a2h`; missing log dir fails the job;
re-running `bootstrap` while loaded errors.
**Fix:** resolve `a2h` dynamically across
`~/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`;
`install.sh` creates log dir first; `hun install` always `bootout`s before
`bootstrap` (errors ignored).

## 5. `remind-at` contradictions + self-cleanup race — ACCEPTED (adapted)
Plan both rejected past times and moved them to tomorrow; bare `HH:MM`
without a date fires daily; a job `bootout`ing itself often doesn't stick.
**Fix:** full `YYYY-MM-DD HH:MM` in the past → reject. Bare `HH:MM` already
passed today → schedule tomorrow **and say so loudly** (better UX than a bare
reject). Plists carry full Year/Month/Day/Hour/Minute. Cleanup is two-layer:
the fired job removes its own plist best-effort (`--reminder-id` hook), and
`remind-list` prunes anything past/missing on every run.

## 6. 1800-char cap bypassable via `--note`/`--force` — ACCEPTED
Trim steps never cut the user note or forced table.
**Fix:** after building the body, hard-cut to 1800 Unicode chars in python3
(`HUN_DRY_RUN` shows the cut), then send. `a2h`'s own 2000 guard is the
backstop, not the plan.

## 7. Recovery/`--force` poison the cooldown — ACCEPTED
Stamping `last_alert_at` on forced sends (or never clearing on recovery) hides
the next real breach for the whole cooldown window.
**Fix:** stamp only metrics included in a **real breach send**; clear a metric
when it recovers; recovery message only on breach→ok transition.

## 8. Can't tell it's working; breach exit code alarms launchd — ACCEPTED
`check` exiting 2 on breach makes `launchctl list` show a failed job; `status`
showed no scheduler state.
**Fix:** exit codes are about the *check*, not the *machine*: 0 = sampled fine
(breach or not), 1 = usage/config error, 3 = a2h missing/unconfigured,
4 = send failed. `hun status` prints loaded/last-run/next-run.

## Deliberate deviations from PLAN.md (not from review)
- `hun` + `lib/` stays as planned (no change).
- `swap_gb` default raised 8 → 16: this machine idles at ~14 GB swap and that
  is normal macOS behavior; 8 would alert on a healthy machine.
- No `assets/hero.png`: no image-generation tool is available in this
  environment, so the README ships without a hero image (recorded, not silent).
