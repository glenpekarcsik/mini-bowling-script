# mini-bowling.sh

Helper script for **mini-bowling.sh** Arduino + ScoreMore development workflow  
(Raspberry Pi / Linux focused)

This script simplifies common tasks when developing and deploying code for a mini-bowling setup that uses:

- Arduino Mega (`arduino:avr:mega`) for hardware control
- ScoreMore bowling scoring software (Linux AppImage version)

## Command Structure

Commands are grouped by area. Run `mini-bowling.sh` with no arguments to see the full reference.

```
status [--watch [N]]           Show system status (auto-refresh every N seconds)
info                           Dense single-screen summary
version                        Show version + check GitHub for updates

deploy [--flags]               Pull → upload Everything → restart ScoreMore
deploy schedule HH:MM          Schedule daily deploy
deploy unschedule              Remove scheduled deploy
deploy history [N]             Show last N deploys from logs (default: 20)

code sketch upload [--Name]    Compile + upload sketch (default: Everything)
code sketch list               List available sketches
code sketch test [--Name]      Compile-only check (no upload)
code sketch rollback [N]       Roll back N git commits and re-upload
code sketch info               Show sketch, branch, and commit currently on Arduino
code compile [--Name]          Compile without uploading (default: Everything)
code pull                      Pull latest for current branch
code pull <branch>             Switch to branch and pull latest
code switch [<branch>]         Permanently switch to branch (default: main)
code console                   Open interactive serial console
code config                    Open Arduino config tool in browser

code branch list               List local + remote branches with commit info
code branch checkout <n>       Temporarily checkout, compile, return to original
code branch switch <n>         Permanently switch to branch (fetches + pulls)
code branch update             Pull latest for current branch
code branch check              Check if remote has new commits

scoremore start|stop|restart   Manage ScoreMore process
scoremore download <ver>       Download version (or 'latest')
scoremore version              Show active version
scoremore check-update         Check scoremorebowling.com for updates
scoremore history              Manage downloaded versions
scoremore rollback             Switch to previous version
scoremore autostart enable     Enable autostart on login
scoremore autostart disable    Disable autostart
scoremore autostart status     Show whether autostart is configured
scoremore logs [tail|dump]     View ScoreMore application logs
scoremore watchdog run|enable|disable|status  ScoreMore crash watchdog

pi status|sysinfo|update|reboot|shutdown  Raspberry Pi management
pi temp [--watch [N]]                     CPU temperature (live monitor with --watch)
pi disk                                   Disk usage by key directory
pi wifi                                   Wi-Fi diagnostics
pi vnc status|start|stop|enable|disable   VNC management

logs [follow|dump|tail|clean]  Log file management (--date YYYY-MM-DD for specific day)

system health                  Full system health dashboard
system cron                    Show all mini-bowling cron jobs
system doctor                  Check dependencies + dialout group
system preflight [--quick]     9 pre-deploy checks
system backup [--include-appimage]  Archive sketches + config
system repair                  Auto-fix common broken states
system cleanup                 Remove old AppImages, caches, old logs
system ports                   List serial devices with USB info
system tail-all [N]            Interleave command + Arduino logs live
system serial start|stop|status|tail|console
system wait-for-network [N]

install setup|create-dir|cli
script version|update
```

## Features

**Arduino & Deploy**

- Browser-based Arduino config tool — opens `config-tool/index.html` from the project repo in the Pi's default browser (`code config`)
- Full deploy cycle — wait for network → pull → upload `Everything` → restart ScoreMore, with pass/fail recorded and `notify-send` desktop notification on finish
- Compile-only check before uploading — verify a sketch builds without touching hardware (`code sketch test`)
- Port and sketch existence verified before killing ScoreMore — nothing goes down for a typo
- Deploy lock file prevents watchdog from restarting ScoreMore mid-deploy
- Dry-run mode — preview what a deploy would do without making any changes (`deploy --dry-run`)
- Roll back to a previous git commit and re-upload the last-used sketch (`code sketch rollback`)
- Network wait tries multiple DNS hosts (8.8.8.8, 1.1.1.1, 9.9.9.9)

**Branch Management**
- List all local and remote branches with latest commit info (`code branch list`)
- Upload from any branch temporarily — fetches + pulls latest, returns to original after (`code sketch upload --branch`)
- Permanently switch the repo to a branch with fetch + pull (`code branch switch`)
- Check for remote commits without pulling (`code branch check`)

**ScoreMore**
- Download any version with disk space guard and integrity check (`scoremore download`)
- AppImage verified with a launch test before the symlink is switched
- One-command restart — kill and relaunch ScoreMore instantly (`scoremore restart`)
- ScoreMore launched with auto-detected display — works over VNC and non-`:0` sessions
- Watchdog auto-restarts ScoreMore if it crashes, skips restart during active deploys (`scoremore watchdog`)
- View ScoreMore's own application logs (`scoremore logs`)

**Diagnostics & Monitoring**
- Live-refreshing status with `status --watch [N]`
- Dense single-screen summary combining hardware, app, and Pi health (`info`)
- Full system health dashboard — deps, Pi vitals, ScoreMore, Arduino sketch state, serial, cron (`system health`)
- Deploy history from logs — timestamps and args for last N deploys (`deploy history`)
- `code sketch info` shows repo HEAD vs Arduino commit and tells you if a deploy is needed
- Pre-flight check with `--quick` flag to skip network checks (`system preflight`)
- Dependency checker with `dialout` group membership and re-login detection (`system doctor`)
- All mini-bowling cron jobs listed with human-readable descriptions (`system cron`)
- Auto-repair of common broken states (`system repair`)
- Serial port listing with USB vendor/product info (`system ports`)
- Interleaved live tail of command log and Arduino serial log (`system tail-all`)

**Raspberry Pi**
- Pi health, OS updates, reboot, and shutdown — sudo checked upfront (`pi status|update|reboot|shutdown`)
- CPU temperature one-shot or live monitor with color-coded warning levels (`pi temp [--watch]`)
- Disk usage breakdown by key directory with AppImage cleanup tip (`pi disk`)
- Wi-Fi diagnostics (`pi wifi`)
- Full VNC management — status, start/stop, autostart (`pi vnc`)

**Maintenance**
- Backup with AppImage excluded by default — opt in with `--include-appimage` (`system backup`)
- Disk cleanup with build cache warning (`system cleanup`)
- Log management with `--date` flag and `--keep N` retention (`logs`)
- Full bash tab completion for all commands, subcommands, flags, sketches, branches, and dates

## Requirements

- `arduino-cli` installed and configured — install via `mini-bowling.sh install cli`
- `git` in the project directory
- `curl`, `realpath`, `pgrep`, `pkill`, `nohup`
- Write access to `~/Desktop` (for the ScoreMore symlink)
- Write access to `~/.config/autostart` (for autostart configuration)
- An active X11 display session (auto-detected — works on `:0`, VNC, etc.)

## Installation / Configuration

Clone the script repo:
```bash
git clone https://github.com/glenpekarcsik/mini-bowling-script.git
cd mini-bowling-script
chmod +x mini-bowling.sh
```

Run the guided setup wizard:
```bash
./mini-bowling.sh install setup
```

The wizard runs 9 steps:

1. Create required directories
2. Install `arduino-cli`
3. Clone or pull the Arduino project repo (prompts for URL on first install)
4. Download latest ScoreMore
5. **Copy script to `/usr/bin/mini-bowling.sh` and install tab completion** to `/etc/bash_completion.d/`
6. Configure ScoreMore autostart on login
7. Run dependency check (`system doctor`)
8. Enable ScoreMore watchdog (Y/n prompt)
9. Schedule daily deploy (optional, enter HH:MM or skip)

After the wizard completes, there are two things to check manually:

**1. Verify the Arduino port and board:**

```bash
mini-bowling.sh system ports        # list detected serial devices
mini-bowling.sh code sketch list    # or: arduino-cli board list
```

Look for `/dev/ttyACM0` showing `Arduino Mega or Mega 2560`. If the port or board differs from the defaults, update these constants near the top of `/usr/bin/mini-bowling.sh`:
```bash
readonly DEFAULT_PORT="/dev/ttyACM0"
readonly BOARD="arduino:avr:mega"
```

**2. Run pre-flight to confirm everything is ready:**
```bash
mini-bowling.sh system preflight
```

Each setup step can also be run individually if needed:
```bash
mini-bowling.sh install create-dir
mini-bowling.sh install cli
git clone <repo-url> ~/Documents/Bowling/Arduino/mini-bowling
mini-bowling.sh scoremore download latest
mini-bowling.sh scoremore autostart enable
mini-bowling.sh system doctor
mini-bowling.sh scoremore watchdog enable
mini-bowling.sh deploy schedule 02:30
```

Then check status:
```bash
$ mini-bowling.sh status
Project dir : /home/gpekarcsik/Documents/Bowling/Arduino/mini-bowling
Port        : /dev/ttyACM0
Arduino     : detected
Sketch      : Everything  (a1b2c3d — Fix pin debounce timing)  @ 2026-03-07 02:31:04
Git branch  : main  [a1b2c3d] Fix pin debounce timing  (up to date)
ScoreMore   : running v1.8.0  (pid 82131, autostart enabled)
Watchdog    : enabled (every 5 min)
Serial log  : not running
Deploy sched: daily at 02:30  (Everything)
VNC         : running — 192.168.1.42:5900  (autostart enabled)
Last deploy : OK at 2026-03-07 02:31:08 — a1b2c3d: Fix pin debounce timing
Done.
```

## Available Commands

| Command | Description | Options | Example |
|---|---|---|---|
| `status` | Full system status | `--watch [N]` | `mini-bowling.sh status --watch` |
| `info` | Dense single-screen summary | — | `mini-bowling.sh info` |
| `version` | Script version + GitHub update check | — | `mini-bowling.sh version` |
| `deploy` | Pull latest → upload Everything → restart ScoreMore | `--dry-run` \| `--no-kill` \| `--branch <n>` | `mini-bowling.sh deploy` |
| `deploy schedule` | Schedule daily deploy | `HH:MM` | `mini-bowling.sh deploy schedule 02:30` |
| `deploy unschedule` | Remove scheduled deploy | — | `mini-bowling.sh deploy unschedule` |
| `deploy history` | Show last N deploys from logs | `[N]` (default: 20) | `mini-bowling.sh deploy history 10` |
| `code sketch upload` | Compile + upload sketch (default: Everything) | `[--Name]` \| `--branch <n>` \| `--no-kill` | `mini-bowling.sh code sketch upload --Master_Test` |
| `code sketch list` | List available sketch folders | — | `mini-bowling.sh code sketch list` |
| `code sketch test` | Compile only — no upload | `[--Name]` | `mini-bowling.sh code sketch test --Everything` |
| `code sketch rollback` | Roll back N git commits and re-upload | `[N]` (default: 1) | `mini-bowling.sh code sketch rollback` |
| `code sketch info` | Show sketch, branch, and commit on Arduino | — | `mini-bowling.sh code sketch info` |
| `code compile` | Compile sketch without uploading | `[--Name]` (default: Everything) | `mini-bowling.sh code compile --Master_Test` |
| `code pull` | Pull latest for current branch (or switch+pull) | `[<branch>]` \| `--branch <n>` | `mini-bowling.sh code pull feature/new-sensor` |
| `code switch` | Permanently switch to branch (default: main) | `[<branch>]` | `mini-bowling.sh code switch feature/new-sensor` |
| `code console` | Open interactive serial console | — | `mini-bowling.sh code console` |
| `code config` | Open Arduino config tool in browser | — | `mini-bowling.sh code config` |
| `code branch list` | List all branches with latest commit info | — | `mini-bowling.sh code branch list` |
| `code branch checkout` | Temporarily checkout branch, compile, return | `<branch> [--Sketch]` | `mini-bowling.sh code branch checkout feature/new-sensor` |
| `code branch switch` | Permanently switch to branch (fetch + pull) | `<branch>` | `mini-bowling.sh code branch switch feature/new-sensor` |
| `code branch update` | Pull latest for current branch | — | `mini-bowling.sh code branch update` |
| `code branch check` | Check remote for new commits | — | `mini-bowling.sh code branch check` |
| `scoremore start` | Launch ScoreMore | — | `mini-bowling.sh scoremore start` |
| `scoremore stop` | Kill ScoreMore | — | `mini-bowling.sh scoremore stop` |
| `scoremore restart` | Kill and relaunch ScoreMore | — | `mini-bowling.sh scoremore restart` |
| `scoremore download` | Download AppImage version | `<ver>` or `latest` | `mini-bowling.sh scoremore download latest` |
| `scoremore version` | Show active version details | — | `mini-bowling.sh scoremore version` |
| `scoremore check-update` | Check scoremorebowling.com for updates | — | `mini-bowling.sh scoremore check-update` |
| `scoremore history` | Manage downloaded versions | `list` \| `use <ver>` \| `clean` | `mini-bowling.sh scoremore history use 1.7.0` |
| `scoremore rollback` | Switch to previous downloaded version | — | `mini-bowling.sh scoremore rollback` |
| `scoremore autostart enable` | Enable ScoreMore autostart on login | — | `mini-bowling.sh scoremore autostart enable` |
| `scoremore autostart disable` | Disable ScoreMore autostart | — | `mini-bowling.sh scoremore autostart disable` |
| `scoremore autostart status` | Show whether autostart is configured | — | `mini-bowling.sh scoremore autostart status` |
| `scoremore logs` | List/tail/dump ScoreMore application logs | `show` \| `tail` \| `dump` | `mini-bowling.sh scoremore logs tail` |
| `pi status` | CPU temp, memory, disk, uptime, architecture, OS | — | `mini-bowling.sh pi status` |
| `pi sysinfo` | Full system identity (hostnamectl) | — | `mini-bowling.sh pi sysinfo` |
| `pi temp` | CPU temperature with color-coded warning levels | `--watch [N]` | `mini-bowling.sh pi temp --watch` |
| `pi disk` | Disk usage by key directory | — | `mini-bowling.sh pi disk` |
| `pi update` | Run apt update + upgrade | — | `mini-bowling.sh pi update` |
| `pi reboot` | Reboot with 5-second countdown | — | `mini-bowling.sh pi reboot` |
| `pi shutdown` | Shut down with 5-second countdown | — | `mini-bowling.sh pi shutdown` |
| `pi wifi` | Interface, IP, SSID, signal, internet | — | `mini-bowling.sh pi wifi` |
| `pi vnc status` | VNC installation, service, connect address | — | `mini-bowling.sh pi vnc status` |
| `pi vnc start` | Start VNC service | — | `mini-bowling.sh pi vnc start` |
| `pi vnc stop` | Stop VNC service | — | `mini-bowling.sh pi vnc stop` |
| `pi vnc enable` | Enable VNC autostart on boot | — | `mini-bowling.sh pi vnc enable` |
| `pi vnc disable` | Disable VNC autostart | — | `mini-bowling.sh pi vnc disable` |
| `logs` | List log files with sizes | — | `mini-bowling.sh logs` |
| `logs follow` | Live tail today's log | — | `mini-bowling.sh logs follow` |
| `logs dump` | Full output of today's log | `--date YYYY-MM-DD` | `mini-bowling.sh logs dump --date 2026-03-06` |
| `logs tail` | Last N lines of today's log | `[N]` \| `--date YYYY-MM-DD` | `mini-bowling.sh logs tail 100 --date 2026-03-06` |
| `logs clean` | Delete log files (confirms first) | `--keep N` | `mini-bowling.sh logs clean --keep 7` |
| `system health` | Full system health dashboard | — | `mini-bowling.sh system health` |
| `system cron` | Show all mini-bowling cron jobs | — | `mini-bowling.sh system cron` |
| `system doctor` | Check dependencies + dialout group | — | `mini-bowling.sh system doctor` |
| `system preflight` | 9 pre-deploy checks | `--quick` \| `-q` | `mini-bowling.sh system preflight --quick` |
| `system backup` | Archive sketches + config | `--include-appimage` | `mini-bowling.sh system backup` |
| `system repair` | Auto-fix common broken states | — | `mini-bowling.sh system repair` |
| `system cleanup` | Remove old AppImages, caches, old logs | — | `mini-bowling.sh system cleanup` |
| `system ports` | List serial devices with USB info | — | `mini-bowling.sh system ports` |
| `system tail-all` | Interleave command + Arduino logs (live) | `[N]` | `mini-bowling.sh system tail-all` |
| `install setup` | Guided first-time setup wizard | — | `mini-bowling.sh install setup` |
| `install create-dir` | Create required directories | — | `mini-bowling.sh install create-dir` |
| `install cli` | Install arduino-cli | — | `mini-bowling.sh install cli` |
| `script version` | Show version + check GitHub for updates | — | `mini-bowling.sh script version` |
| `script update` | Update script from GitHub (syntax-checked) | — | `mini-bowling.sh script update` |
| `system serial` | Arduino serial logging + console | `start\|stop\|status\|tail\|console` | `mini-bowling.sh system serial start` |
| `system wait-for-network` | Wait for internet connectivity | `[N]` (default: 30) | `mini-bowling.sh system wait-for-network 60` |
| `scoremore watchdog` | ScoreMore crash watchdog | `run\|enable\|disable\|status` | `mini-bowling.sh scoremore watchdog enable` |

## Usage Examples

```bash
# ── Quick admin ───────────────────────────────────────────────────────────────

mini-bowling.sh scoremore restart    # ScoreMore frozen? Kill and relaunch
mini-bowling.sh status               # What's running right now?
mini-bowling.sh status --watch       # Auto-refresh every 5 seconds
mini-bowling.sh info                 # Full picture: hardware + app + Pi
mini-bowling.sh system health        # Full system health dashboard
mini-bowling.sh system repair        # Fix common broken states automatically
mini-bowling.sh system cron          # What cron jobs are installed?
mini-bowling.sh system ports         # Which serial ports exist?
mini-bowling.sh system preflight --quick  # Ready to deploy? (fast, no network)
mini-bowling.sh code sketch test     # Does Everything compile?
mini-bowling.sh code sketch info     # What's on the Arduino? Is it up to date?
mini-bowling.sh system tail-all      # What did the script do + what did Arduino say?
mini-bowling.sh scoremore logs tail  # What is ScoreMore itself logging?

# ── Deploy ────────────────────────────────────────────────────────────────────

mini-bowling.sh deploy --dry-run     # Preview deploy without making changes
mini-bowling.sh deploy               # Pull latest, upload Everything, restart ScoreMore
mini-bowling.sh deploy --branch testing
mini-bowling.sh deploy schedule 02:30
mini-bowling.sh deploy unschedule
mini-bowling.sh deploy history       # What deploys have run recently?

# ── Sketch & branch ───────────────────────────────────────────────────────────

mini-bowling.sh code sketch upload --Everything
mini-bowling.sh code sketch upload --Master_Test
mini-bowling.sh code sketch upload --Master_Test --branch feature/new-sensor
mini-bowling.sh code sketch upload --Master_Test --no-kill
mini-bowling.sh code sketch list
mini-bowling.sh code sketch test --Everything
mini-bowling.sh code sketch rollback
mini-bowling.sh code sketch rollback 2
mini-bowling.sh code sketch info
mini-bowling.sh code compile --Everything
mini-bowling.sh code compile --Master_Test
mini-bowling.sh code pull
mini-bowling.sh code pull feature/new-sensor
mini-bowling.sh code switch feature/new-sensor
mini-bowling.sh code console
mini-bowling.sh code config
mini-bowling.sh code branch list
mini-bowling.sh code branch switch feature/new-sensor
mini-bowling.sh code branch switch main
mini-bowling.sh code branch checkout feature/new-sensor --Master_Test
mini-bowling.sh code branch update
mini-bowling.sh code branch check

# ── ScoreMore ─────────────────────────────────────────────────────────────────

mini-bowling.sh scoremore restart
mini-bowling.sh scoremore download latest
mini-bowling.sh scoremore download 1.8.0
mini-bowling.sh scoremore check-update
mini-bowling.sh scoremore version
mini-bowling.sh scoremore history
mini-bowling.sh scoremore history use 1.7.0
mini-bowling.sh scoremore history clean
mini-bowling.sh scoremore rollback
mini-bowling.sh scoremore autostart enable
mini-bowling.sh scoremore autostart disable
mini-bowling.sh scoremore autostart status
mini-bowling.sh scoremore logs tail

# ── Serial & monitoring ───────────────────────────────────────────────────────

mini-bowling.sh system serial start
mini-bowling.sh system serial stop
mini-bowling.sh system serial status
mini-bowling.sh system serial tail
mini-bowling.sh system serial console
mini-bowling.sh code console
mini-bowling.sh logs follow

# ── Config tool ───────────────────────────────────────────────────────────────

mini-bowling.sh code config
mini-bowling.sh logs tail 100
mini-bowling.sh logs dump
mini-bowling.sh logs clean --keep 7
mini-bowling.sh system tail-all

# ── Watchdog ──────────────────────────────────────────────────────────────────

mini-bowling.sh scoremore watchdog run
mini-bowling.sh scoremore watchdog enable
mini-bowling.sh scoremore watchdog disable
mini-bowling.sh scoremore watchdog status

# ── System ────────────────────────────────────────────────────────────────────

mini-bowling.sh system health
mini-bowling.sh system cron
mini-bowling.sh system doctor
mini-bowling.sh system preflight
mini-bowling.sh system preflight --quick
mini-bowling.sh system repair
mini-bowling.sh system backup
mini-bowling.sh system backup --include-appimage
mini-bowling.sh system cleanup
mini-bowling.sh system ports
mini-bowling.sh install setup
mini-bowling.sh install create-dir
mini-bowling.sh install cli
mini-bowling.sh script version
mini-bowling.sh script update

# ── Pi ────────────────────────────────────────────────────────────────────────

mini-bowling.sh pi status
mini-bowling.sh pi sysinfo
mini-bowling.sh pi temp
mini-bowling.sh pi temp --watch
mini-bowling.sh pi disk
mini-bowling.sh pi update
mini-bowling.sh pi reboot
mini-bowling.sh pi shutdown
mini-bowling.sh pi wifi
mini-bowling.sh pi vnc status
mini-bowling.sh pi vnc start
mini-bowling.sh pi vnc stop
mini-bowling.sh pi vnc enable
mini-bowling.sh pi vnc disable

# ── Testing ───────────────────────────────────────────────────────────────────

./mini-bowling-test.sh unit          # no hardware needed
./mini-bowling-test.sh unit -v       # verbose output on failures
./mini-bowling-test.sh integration   # requires Arduino connected
```

## Deploy Cycle

Run `deploy --dry-run` first to preview. Then `deploy` executes:

1. Verify project directory is a git repository
2. Write deploy lock file — prevents watchdog from restarting ScoreMore mid-deploy
3. Wait for network (tries 8.8.8.8 / 1.1.1.1 / 9.9.9.9, up to 60 seconds)
4. Warn if local repo has uncommitted changes
5. `git pull` from `main`
6. Verify Arduino port is connected and recognised
7. Verify sketch directory exists — exits before killing ScoreMore if missing
8. Stop serial logging if running
9. Kill ScoreMore gracefully
10. Compile + upload `Everything` (120 second timeout)
11. Restart serial logging if it was running
12. Start ScoreMore
13. Remove deploy lock file
14. Write pass/fail + commit info to deploy status file
15. Send `notify-send` desktop notification if available

## Deploy Status Tracking

Every deploy records its outcome to `~/Documents/Bowling/logs/.last-deploy-status`, visible in `status`:

```
Last deploy : OK at 2026-03-06 02:30:14 — a1b2c3d: Fix pin debounce timing
Last deploy : FAILED (started 2026-03-06 02:30:01) — a1b2c3d: Fix pin debounce timing
```

If `notify-send` is available (pre-installed on Pi OS desktop), a notification fires on finish — useful for unattended 2:30am deploys.

## Deploy Dry Run

`deploy --dry-run` shows what would happen without making any changes:

```
--- DRY RUN — no changes will be made ---

  ✓  Network reachable
  ✎  Local commit : abc1234 Fix pin assignment for lane 3
  ✎  Remote ahead : 2 commit(s)
  ✎  Repo state   : clean
  ✓  Arduino port: /dev/ttyACM0
  ✎  ScoreMore is running (pid 82131) — will be killed before upload
  ✓  Sketch found: Everything
  ✓  Disk space: 4823MB free

Dry run complete — no changes made. Run without --dry-run to deploy.
```

## Branch Management

**List branches:**
```bash
mini-bowling.sh code branch list
# → main                           [a1b2c3d] Fix pin debounce timing
#   feature/new-sensor             [e4f5g6h] Add proximity sensor support
```

**Upload from a branch temporarily** (returns to original branch after):
```bash
mini-bowling.sh code sketch upload --Everything --branch feature/new-sensor
# → Fetching latest from remote...
# Checking out branch: feature/new-sensor
# → Pulling latest commits...
# → Now at: [e4f5g6h] Add proximity sensor support
# ...compiles and uploads...
# Returning to original branch: main
```

**Permanently switch to a branch:**
```bash
mini-bowling.sh code branch switch feature/new-sensor
# ✓ Switched to feature/new-sensor: [e4f5g6h] Add proximity sensor support
# Note: you are now permanently on branch 'feature/new-sensor'.
#   To switch back: mini-bowling.sh code branch switch main
```

## ScoreMore Management

```bash
mini-bowling.sh scoremore download latest      # fetch newest version
mini-bowling.sh scoremore download 1.8.0       # specific version
mini-bowling.sh scoremore check-update         # check for updates
mini-bowling.sh scoremore version              # active version info
mini-bowling.sh scoremore history              # list downloaded versions
mini-bowling.sh scoremore history use 1.7.0    # switch to specific version
mini-bowling.sh scoremore history clean        # remove all except active
mini-bowling.sh scoremore rollback             # switch to previous version
```

## ScoreMore Process Management

ScoreMore runs as an Electron AppImage. The script kills it by targeting the AppImage launcher, which brings down the entire process tree. A `pkill` sweep then cleans up any orphaned child processes.

The active X display is auto-detected at launch — `$DISPLAY` from environment if set, otherwise scans `who` for a logged-in X session, falls back to `:0` with a warning. Works correctly over VNC and scheduled cron deploys.

## ScoreMore Watchdog

```bash
mini-bowling.sh scoremore watchdog run      # check once and restart if needed
mini-bowling.sh scoremore watchdog enable   # check every 5 minutes via cron
mini-bowling.sh scoremore watchdog disable
mini-bowling.sh scoremore watchdog status
```

The watchdog checks for a deploy lock before restarting — if a deploy is actively running, it skips the restart and exits cleanly. It also restarts serial logging if the Arduino was unplugged and the monitor process died.

## Scheduled Deploy

```bash
mini-bowling.sh deploy schedule 02:30   # every day at 2:30am
mini-bowling.sh deploy schedule 14:00   # every day at 2:00pm
mini-bowling.sh deploy unschedule
```

Re-running with a different time replaces the existing schedule. The deploy waits up to 60 seconds for network, so it works even if the Pi is still connecting to Wi-Fi. If the script is not in `/usr/bin` or `/usr/local/bin`, a warning is printed — cron uses a minimal PATH and won't find it elsewhere.

## System Preflight

`system preflight` runs 9 checks without making changes:

```
  ✓  arduino-cli installed
  ✓  Arduino port found: /dev/ttyACM0
  ✓  Internet reachable
  ✓  Disk space: 4823MB free
  ✓  CPU temperature: 48°C
  ✓  Git repo clean
  ✓  ScoreMore symlink valid
  ✓  Git repo up to date with remote
  !  ScoreMore update available: 1.8.0 → 1.8.2
```

`system preflight --quick` skips checks 3 (internet), 8 (git fetch), and 9 (ScoreMore version) for a fast local-only result.

## Logging

```bash
mini-bowling.sh logs                          # list log files
mini-bowling.sh logs follow                   # live tail today
mini-bowling.sh logs dump                     # full output of today
mini-bowling.sh logs dump --date 2026-03-06   # specific day
mini-bowling.sh logs tail 100                 # last 100 lines of today
mini-bowling.sh logs tail 100 --date 2026-03-06
mini-bowling.sh logs clean                    # delete all (confirms first)
mini-bowling.sh logs clean --keep 7           # keep last 7 days
```

The `--date` flag is useful the morning after a 2:30am deploy — the deploy completed in yesterday's log, not today's.

## Arduino Config Tool

The Arduino project includes a browser-based configuration tool at `config-tool/index.html` that helps configure settings in the Arduino code without editing source files directly.

```bash
mini-bowling.sh code config
```

Opens `$PROJECT_DIR/config-tool/index.html` in the default browser on the Pi. Browser detection order: `chromium-browser` → `chromium` → `firefox` → `epiphany` → `xdg-open`.

The browser is launched in the background and the terminal is returned immediately.

## System Serial

```bash
mini-bowling.sh system serial start    # start background Arduino serial logging
mini-bowling.sh system serial status   # check if running
mini-bowling.sh system serial tail     # live follow (Ctrl+C to exit)
mini-bowling.sh system serial stop     # stop
mini-bowling.sh system serial console  # interactive serial monitor
```

Serial logs auto-rotate at 10MB. The console is blocked if serial logging is active — both use the same port. After every `code sketch upload` or `deploy`, serial logging stops before upload and restarts after.

## Raspberry Pi Management

```bash
mini-bowling.sh pi status      # CPU temp, memory, disk, uptime, architecture, OS
mini-bowling.sh pi sysinfo     # full system identity (hostnamectl)
mini-bowling.sh pi temp        # CPU temperature (one-shot, color-coded)
mini-bowling.sh pi temp --watch       # live CPU temperature monitor (5s refresh)
mini-bowling.sh pi temp --watch 10    # live monitor, 10s interval
mini-bowling.sh pi disk        # disk usage: project, ScoreMore, logs, build cache
mini-bowling.sh pi update      # apt update + upgrade
mini-bowling.sh pi reboot      # 5-second countdown (checks sudo first)
mini-bowling.sh pi shutdown    # 5-second countdown (checks sudo first)
mini-bowling.sh pi wifi        # interface, IP, SSID, signal, internet
mini-bowling.sh pi vnc status  # VNC install state, service, connect address
mini-bowling.sh pi vnc start   # start VNC service
mini-bowling.sh pi vnc stop    # stop VNC service
mini-bowling.sh pi vnc enable  # enable VNC autostart on boot
mini-bowling.sh pi vnc disable # disable VNC autostart
```

## System Doctor

`system doctor` checks all required tools, optional tools, directories, and serial port access in two stages — whether the user is in `dialout`, and whether the current session has it active (it won't if added after login):

```
Serial port access:
  ✗  gpekarcsik is NOT in the dialout group
     Fix: sudo usermod -aG dialout gpekarcsik
     Then log out and back in (or reboot) for it to take effect.

  !  gpekarcsik is in dialout but needs to log out and back in
     The group was added but this session predates it.
     Fix: log out and back in, or run: newgrp dialout
```

## System Backup

`system backup` archives the Arduino project, ScoreMore config, and the script itself. AppImage excluded by default (100MB+, re-downloadable):

```bash
mini-bowling.sh system backup                    # fast, excludes AppImage
mini-bowling.sh system backup --include-appimage # complete, includes AppImage
```

The last 10 backups are kept automatically.

## System Repair

`system repair` checks and fixes the most common broken states automatically:

- Stale serial-log PID file — removed if process no longer exists
- Stale deploy lock — removed if deploy process is gone
- Broken ScoreMore symlink — reported with fix command
- ScoreMore not running — restarted automatically if autostart is enabled
- Missing required directories — created on the spot

## Tab Completion

`mini-bowling-completion.bash` provides tab completion for all commands and subcommands:

```bash
mini-bowling.sh <TAB>
→  status  info  version  deploy  code  scoremore  pi  logs  system  install  script

mini-bowling.sh code <TAB>
→  sketch  branch  compile  pull  switch  console

mini-bowling.sh code sketch <TAB>
→  upload  list  test  rollback

mini-bowling.sh code compile <TAB>
→  --Everything  --Master_Test  (sketch names from project dir)

mini-bowling.sh code pull <TAB>
→  --branch  main  feature/new-sensor  (branch names from git repo)

mini-bowling.sh code branch <TAB>
→  list  checkout  switch  update  check

mini-bowling.sh scoremore <TAB>
→  start  stop  restart  download  version  check-update  history  rollback  autostart  logs  watchdog

mini-bowling.sh scoremore autostart <TAB>
→  enable  disable  status

mini-bowling.sh scoremore watchdog <TAB>
→  run  enable  disable  status

mini-bowling.sh deploy <TAB>
→  --dry-run  --no-kill  --branch  schedule  unschedule  history

mini-bowling.sh pi <TAB>
→  status  sysinfo  temp  disk  update  reboot  shutdown  wifi  vnc

mini-bowling.sh pi temp <TAB>
→  --watch

mini-bowling.sh system <TAB>
→  health  cron  doctor  preflight  backup  repair  cleanup  ports  tail-all  serial  wait-for-network

mini-bowling.sh install <TAB>
→  setup  create-dir  cli

mini-bowling.sh script <TAB>
→  version  update

mini-bowling.sh code branch <TAB>
→  list  checkout  switch  update  check

mini-bowling.sh pi vnc <TAB>
→  status  start  stop  enable  disable

mini-bowling.sh code sketch upload <TAB>
→  --Everything  --Master_Test  --no-kill  --branch  (sketch names from project dir)

mini-bowling.sh code branch switch <TAB>
→  main  feature/new-sensor  feature/lane-2  (from git repo)

mini-bowling.sh logs tail <TAB>
→  50  100  200  --date

mini-bowling.sh scoremore history use <TAB>
→  1.8.2  1.8.0  1.7.1  (from downloaded AppImages)
```

**Install:**
```bash
sudo cp mini-bowling-completion.bash /etc/bash_completion.d/mini-bowling.sh
source /etc/bash_completion.d/mini-bowling.sh
```

## Updating the Script

```bash
mini-bowling.sh script update
```

Clones `~/.local/share/mini-bowling-script` on first run, `git pull`s on subsequent runs. Resets any local modifications in the clone before pulling (handles the case where a previous partial update left local changes). Validates with `bash -n` before installing — a bad update never reaches `/usr/bin`. Uses `sudo cp` automatically if installed in `/usr/bin`.

## Quick Reference

The commands most useful at the bowling alley when something needs fixing:

```bash
mini-bowling.sh scoremore restart        # ScoreMore frozen? Kill and relaunch
mini-bowling.sh status                   # What's running right now?
mini-bowling.sh status --watch           # Auto-refresh every 5 seconds
mini-bowling.sh system health            # Full health dashboard in one shot
mini-bowling.sh info                     # Full picture at a glance
mini-bowling.sh code sketch info         # What's on the Arduino? Deploy needed?
mini-bowling.sh deploy history           # What deploys have run recently?
mini-bowling.sh system repair            # Fix common broken states
mini-bowling.sh system cron              # What cron jobs are installed?
mini-bowling.sh system ports             # Which serial ports exist?
mini-bowling.sh system preflight --quick # Ready to deploy? (fast)
mini-bowling.sh code sketch test         # Does the sketch compile?
mini-bowling.sh system tail-all          # Script log + Arduino log together
mini-bowling.sh scoremore logs tail      # ScoreMore application logs
mini-bowling.sh pi temp --watch          # Is the Pi running hot?
mini-bowling.sh pi disk                  # How full is the disk?
```

## Changelog

### v4.4.0

**New commands**

- `system health` — full dashboard: deps, Pi vitals, ScoreMore status, Arduino sketch state, serial logging, cron jobs
- `system cron` — lists all mini-bowling cron entries with human-readable descriptions (watchdog, scheduled deploy)
- `deploy history [N]` — parses log files and shows last N deploy timestamps + args (default: 20)
- `pi temp [--watch [N]]` — CPU temperature one-shot or live monitor with color-coded warning levels (green/yellow/red)
- `pi disk` — disk breakdown by key directory (project, ScoreMore, logs, build cache, script repo) with AppImage count tip

**Enhancements**

- `code sketch info` now shows repo HEAD commit alongside the Arduino's recorded commit, with explicit "deploy needed (+N commits)" or "up to date" status
- `script update` now also updates the tab completion file if previously installed (checks `/etc/bash_completion.d/`, `/usr/share/bash-completion/completions/`, `/usr/local/share/bash-completion/completions/`)
- `script update` now updates `mini-bowling` (no `.sh`) in the same bin directory if a separate copy exists

---

### v4.0.0

> ⚠️ **Breaking changes** — if you have `system watchdog` or `scoremore autostart`/`scoremore remove-autostart` in any cron job or script, update those references before upgrading.

**Breaking command changes**
- `system watchdog` → `scoremore watchdog` (run/enable/disable/status)
- `scoremore autostart` (bare enable) + `scoremore remove-autostart` → `scoremore autostart enable/disable/status`
- `install preflight` removed — use `system preflight`

**New commands**
- `code pull [<branch>]` — pull latest for current branch, or switch+pull a named branch
- `code switch [<branch>]` — shorthand for `code branch switch` (default: main)
- `code compile [--Name]` — compile sketch without uploading (default: Everything)
- `code sketch info` — show sketch name, branch, and commit currently flashed to the Arduino
- `pi sysinfo` — full system identity via `hostnamectl`

**Enhancements**
- `pi status` now shows architecture (`dpkg --print-architecture`, `uname -m`) and OS name (`/etc/os-release`)
- `code sketch upload`, `deploy`, and `code sketch rollback` now record the git branch in `.last-arduino-upload` (line 5) — `code sketch info` reads this
- `code sketch upload` on the current branch skips unnecessary stash/fetch/checkout/restore

**Bug fixes**
- `system serial` commands crashed silently — a literal `\n` in the dispatch case arm caused `set -e` to exit on command not found
- `scoremore watchdog enable` wrote an invalid cron entry — used `mini-bowling` instead of `mini-bowling.sh` in `command -v` lookup
- `scoremore download` AppImage verification was dead code — `; exit 0` in the `bash -c` string forced the launch test to always pass, so corrupt downloads were never rejected
- `code branch update` bare `git pull` could fail in detached HEAD or without a tracking branch — now explicit `git pull origin <branch>`

---

### v2.0.0
Major overhaul from the original v1.0.0 release.

**Command structure**
- Commands grouped into `deploy`, `sketch`, `branch`, `scoremore`, `pi`, `logs`, `system`
- `status`, `info`, `version` remain at top level for quick access
- `install` group (top-level): `setup`, `create-dir`, `cli`, `preflight`
- `script` group (top-level): `version`, `update` (renamed from `update-script`)
- `system serial` subgroup; `scoremore watchdog` subgroup
- `pi vnc` subgroup for all VNC management
- `deploy schedule` / `deploy unschedule` instead of separate `schedule-deploy` / `unschedule-deploy`

**New commands**
- `scoremore restart` — kill and relaunch in one command
- `system repair` — auto-fix common broken states
- `system ports` — serial devices with USB vendor/product info
- `info` — dense single-screen summary
- `status --watch [N]` — auto-refresh
- `system tail-all [N]` — interleave command + Arduino logs
- `sketch test [--Sketch]` — compile-only check
- `scoremore logs` — view ScoreMore application logs
- `branch list`, `branch checkout`, `branch switch`, `branch update`, `branch check`

**Deploy improvements**
- Deploy lock file prevents watchdog from restarting ScoreMore mid-deploy
- `notify-send` desktop notification on deploy finish
- Git repo check before deploy
- Network wait tries multiple hosts
- Deploy records git commit and subject in status file
- `sketch upload --branch` / `deploy --branch` now correctly fetches + pulls latest remote commits before compiling

**Robustness**
- `require_git_repo()` guard on all git-dependent commands
- `start_scoremore` auto-detects active X display
- `system serial stop` cleans up stray processes without PID file
- `sketch rollback` reads last-uploaded sketch from history
- `scoremore rollback` gives specific error when only one version installed
- `scoremore download` verifies AppImage launches before switching symlink
- `pi reboot`/`pi shutdown` check sudo upfront
- `branch checkout` / `branch switch` names stash and restores on interrupt
- `deploy schedule` warns if script not in cron-accessible PATH
- `install setup` checks URL reachability before git clone
- `system script update` validates syntax before installing, resets clone before pull

**Bug fixes**
- `scoremore version` used hardcoded `arm64` instead of `$ARCH`
- `BOLD` colour constant was missing — caused crash in `info` and `status --watch`
- `upload --branch` never pulled latest remote commits

**Testing**
- 136 unit tests covering all major commands and edge cases

## Configuration Reference

| Variable | Default | Description |
|---|---|---|
| `SCRIPT_VERSION` | `4.0.0` | Script version — bump when deploying updates |
| `DEFAULT_GIT_BRANCH` | `main` | Branch used by `branch update` and `deploy` |
| `PROJECT_DIR` | `~/Documents/Bowling/Arduino/mini-bowling` | Arduino sketch root (override with `$MINI_BOWLING_DIR`) |
| `DEFAULT_PORT` | `/dev/ttyACM0` | Arduino serial port (override with `$PORT` at runtime) |
| `BOARD` | `arduino:avr:mega` | arduino-cli FQBN |
| `SCOREMORE_DIR` | `~/Documents/Bowling/ScoreMore` | Where downloaded AppImages are saved |
| `LOG_DIR` | `~/Documents/Bowling/logs` | Where daily log files are written |
| `SYMLINK_PATH` | `~/Desktop/ScoreMore.AppImage` | Desktop symlink maintained by `scoremore download` |
| `BAUD_RATE` | `9600` | Serial baud rate — must match `Serial.begin()` in your sketch |
| `ARCH` | `arm64` | AppImage architecture suffix |

Override `PORT` at runtime without editing the script:
```bash
PORT=/dev/ttyUSB0 mini-bowling.sh code sketch upload --Everything
```

## Project Structure

```
~/Documents/Bowling/Arduino/mini-bowling/
├── Everything/
│   └── Everything.ino
├── Master_Test/
│   └── Master_Test.ino
└── ...

~/Documents/Bowling/ScoreMore/ScoreMore-<ver>-arm64.AppImage
~/Desktop/ScoreMore.AppImage                    ← symlink to active AppImage
~/.config/autostart/scoremore.desktop           ← XDG autostart (when enabled)
~/Documents/Bowling/logs/mini-bowling-YYYY-MM-DD.log
~/Documents/Bowling/logs/arduino-serial-YYYY-MM-DD.log
~/Documents/Bowling/logs/.last-deploy-status
~/Documents/Bowling/backups/mini-bowling-backup-*.tar.gz
./mini-bowling-test.sh                          ← unit test suite
./mini-bowling-completion.bash                  ← tab completion
```
