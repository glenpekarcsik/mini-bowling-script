# mini-bowling.sh

Helper script for **mini-bowling.sh** Arduino + ScoreMore development workflow  
(Raspberry Pi / Linux focused)

This script simplifies common tasks when developing and deploying code for a mini-bowling setup that uses:

- Arduino Mega (`arduino:avr:mega`) for hardware control
- ScoreMore bowling scoring software (Linux AppImage version)

## Features

**Arduino & Deploy**
- Compile + upload selected sketch to Arduino, then restart ScoreMore
- Port verification before upload — errors out before killing ScoreMore if Arduino is not reachable
- Sketch existence verified before killing ScoreMore — a typo in `--FolderName` never takes ScoreMore down
- Full deploy cycle (`deploy`) — wait for network → kill → pull → upload → restart ScoreMore, with pass/fail status recorded
- Deploy lock file prevents the watchdog from restarting ScoreMore mid-deploy
- Dry-run mode — preview what a deploy would do without making any changes (`deploy --dry-run`)
- Roll back to a previous git commit and re-upload the last-used sketch (`rollback`)
- Git operations with dirty-repo warning (`update`)
- Check for remote git commits without pulling (`check-update`)
- Upload timeout — fails cleanly if arduino-cli hangs rather than blocking forever
- Keep the script itself up to date from GitHub — syntax-validated before installing (`update-script`)
- Network wait tries multiple DNS hosts (8.8.8.8, 1.1.1.1, 9.9.9.9) — works on networks that block Google

**ScoreMore**
- Download a specific or latest ScoreMore version with disk space guard and integrity check (`download`)
- AppImage verified with a launch test before the symlink is switched — corrupt downloads don't break ScoreMore
- Check scoremorebowling.com for newer versions (`check-scoremore-update`)
- Manage downloaded ScoreMore versions — list, switch, and roll back (`scoremore-history`, `rollback-scoremore`)
- Graceful start/stop of ScoreMore (kills by AppImage path, cleans up orphaned Electron processes)
- ScoreMore launched with auto-detected display — works correctly over VNC and non-`:0` sessions
- ScoreMore watchdog — auto-restart if ScoreMore crashes, skips restart if a deploy is in progress (`watchdog`, `setup-watchdog`)
- Configure ScoreMore to auto-start on login (`setup-autostart` / `remove-autostart`)

**Diagnostics & Monitoring**
- Status overview — port, Arduino detection, last-uploaded sketch + git commit, git branch + remote state, ScoreMore version + state, autostart, watchdog, serial log, schedule, VNC state, last deploy result with commit (`status`)
- Pre-flight check before deploying — 9 checks including ScoreMore and git update availability, `--quick` skips network checks (`preflight`)
- Dependency checker — required tools, optional tools, directories, `dialout` group membership, and re-login detection if group was added in current session (`doctor`)
- Arduino serial output logging to file in the background with 10MB auto-rotation and stale-PID cleanup on stop (`serial-log`)
- Arduino serial console — blocked if serial logging is already active (`console`)
- Deploy status tracking — pass/fail recorded after every deploy, visible in `status`

**Raspberry Pi**
- Pi health overview — CPU temp, memory, disk, uptime (`pi-status`)
- OS updates, reboot, and shutdown — sudo checked upfront before countdown begins (`pi-update`, `pi-reboot`, `pi-shutdown`)
- Wi-Fi diagnostics — interface, IP, SSID, signal, internet reachability (`wifi-status`)
- VNC diagnostics — installation, service state, active displays, autostart, connect address (`vnc-status`)
- VNC control — start/stop the service and enable/disable autostart on boot (`vnc-setup`)

**Maintenance**
- Config, sketch, and script backup with automatic 10-backup retention — AppImage excluded by default (re-downloadable), opt in with `--include-appimage` (`backup`)
- Disk cleanup — old AppImages, build caches, and logs, with a warning that the next compile will be slower after cache removal (`disk-cleanup`)
- Manual log deletion with confirmation prompt, with optional `--keep N` to retain the last N days (`logs clean`)
- `logs follow` hints about yesterday's log if today's file is empty — useful just after midnight
- Logging of all output to daily log files with 30-day automatic retention
- Required directories created automatically on first run
- Guided first-time setup wizard with URL reachability check before git clone (`install`)
- Script version info with remote update check (`version`)

## Requirements

- `arduino-cli` installed and configured — the script can install it via `mini-bowling.sh install-cli`
- `git` in the project directory
- `curl`, `realpath`, `pgrep`, `pkill`, `nohup`
- Write access to `~/Desktop` (for the ScoreMore symlink)
- Write access to `~/.config/autostart` (for autostart configuration)
- An active X11 display session (the script auto-detects `DISPLAY` — works on `:0`, VNC sessions, etc.)

## Installation / Configuration

Clone the mini-bowling.sh script repo:
```bash
git clone https://github.com/glenpekarcsik/mini-bowling-script.git
cd mini-bowling-script
```

Make the script executable and copy it to `/usr/bin` so it is available system-wide and cron jobs can find it by name:
```bash
chmod +x mini-bowling.sh
sudo cp mini-bowling.sh /usr/bin/mini-bowling.sh
```

Verify the script is accessible:
```bash
$ which mini-bowling.sh
/usr/bin/mini-bowling.sh

$ mini-bowling.sh
Usage: mini-bowling.sh <command> [options]
...
```

Now run the guided setup wizard:
```bash
mini-bowling.sh install
```

The `install` wizard runs through 8 steps: creating directories, installing `arduino-cli`, cloning or pulling the Arduino project, downloading the latest ScoreMore, configuring ScoreMore autostart, running a dependency check, optionally enabling the ScoreMore watchdog, and optionally scheduling a daily deploy. You can also run each step manually:

```bash
mini-bowling.sh create-dir
mini-bowling.sh install-cli
git clone <repo-url> ~/Documents/Bowling/Arduino/mini-bowling
mini-bowling.sh download latest
mini-bowling.sh setup-autostart
mini-bowling.sh doctor
mini-bowling.sh setup-watchdog enable
mini-bowling.sh schedule-deploy 02:30
```

**Find and configure your Arduino port** — connect the Arduino and run:
```bash
mini-bowling.sh list
```

Look for the port showing `Arduino Mega or Mega 2560` in the Board Name column (typically `/dev/ttyACM0`). Open the script and update these two variables near the top to match:
```bash
readonly DEFAULT_PORT="/dev/ttyACM0"
readonly BOARD="arduino:avr:mega"
```

Then re-copy the updated script to `/usr/bin`:
```bash
sudo cp mini-bowling.sh /usr/bin/mini-bowling.sh
```

See the [Finding the Arduino Port](#finding-the-arduino-port) section for full details and troubleshooting.

Run `preflight` to confirm everything is ready:
```bash
mini-bowling.sh preflight
```

Then `status` to confirm the full setup:
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

You're ready to run your first deploy — see the [Deploy Cycle](#deploy-cycle) section for a full breakdown of what happens when you run it:
```bash
mini-bowling.sh deploy
```

## Finding the Arduino Port

Connect the Arduino and run:
```bash
mini-bowling.sh list
```

Expected output when the Arduino is connected:
```
Port          Protocol Type              Board Name                FQBN             Core
/dev/ttyACM0  serial   Serial Port (USB) Arduino Mega or Mega 2560 arduino:avr:mega arduino:avr
/dev/ttyAMA0  serial   Serial Port       Unknown
/dev/ttyAMA10 serial   Serial Port       Unknown
```

If you only see unknown serial ports, the Raspberry Pi is not detecting the Arduino — reconnect the board and try again:
```
Port          Protocol Type        Board Name FQBN Core
/dev/ttyAMA0  serial   Serial Port Unknown
/dev/ttyAMA10 serial   Serial Port Unknown
```

Update `DEFAULT_PORT` and `BOARD` in the script to match, then re-copy it to `/usr/bin`:
```bash
sudo cp mini-bowling.sh /usr/bin/mini-bowling.sh
```

## Available Commands

| Command | Description | Options / Arguments | Example Usage |
|---|---|---|---|
| `version` | Show script version, install path, last-modified date, shell version, and whether a newer version is available on GitHub | — | `mini-bowling.sh version` |
| `status` | Show port, Arduino detection, ScoreMore version + state, watchdog, serial log, schedule, and last deploy result | — | `mini-bowling.sh status` |
| `install` | Guided 8-step setup wizard (directories, arduino-cli, git clone, ScoreMore download, autostart, doctor, watchdog, schedule) | — | `mini-bowling.sh install` |
| `preflight` | Run 9 pre-deploy checks — Arduino, network, disk, CPU temp, git state, symlink, remote updates, ScoreMore version. Use `--quick` to skip the 3 network-dependent checks (3, 8, 9) for a fast local-only check | `--quick` \| `-q` | `mini-bowling.sh preflight --quick` |
| `doctor` | Check all required and optional dependencies, directories, and `dialout` group membership for serial port access | — | `mini-bowling.sh doctor` |
| `deploy` | Wait for network → pull latest → kill ScoreMore → upload `Everything` → restart ScoreMore | `--no-kill` \| `-k` \| `--branch <n>` \| `--dry-run` | `mini-bowling.sh deploy` |
| `upload` | Compile + upload sketch → restart ScoreMore (default: `Everything`) | `--FolderName` \| `--list-sketches` \| `--branch <n>` \| `--no-kill` | `mini-bowling.sh upload --Master_Test` |
| `upload --list-sketches` | List all subfolders containing at least one `*.ino` file | — | `mini-bowling.sh upload --list-sketches` |
| `update` | `git pull` latest changes (warns if repo is dirty) | — | `mini-bowling.sh update` |
| `check-update` | Fetch remote and show new commits without pulling | — | `mini-bowling.sh check-update` |
| `rollback` | Reset N git commits and re-upload the last-used sketch (reads from upload history, falls back to `Everything`) | `[N]` (default: 1) | `mini-bowling.sh rollback` |
| `download` | Download ScoreMore AppImage → update symlink → restart app | `<version>` or `latest` | `mini-bowling.sh download latest` |
| `check-scoremore-update` | Fetch scoremorebowling.com and compare latest version to installed | — | `mini-bowling.sh check-scoremore-update` |
| `scoremore-version` | Show the currently active ScoreMore version and AppImage details | — | `mini-bowling.sh scoremore-version` |
| `scoremore-history` | List downloaded AppImage versions, switch to a version, or remove old ones | `list` \| `use <ver>` \| `clean` | `mini-bowling.sh scoremore-history list` |
| `rollback-scoremore` | Switch to the previously downloaded ScoreMore version | — | `mini-bowling.sh rollback-scoremore` |
| `start-scoremore` | Launch `ScoreMore.AppImage` in the background (auto-detects active display, falls back to `:0`) | — | `mini-bowling.sh start-scoremore` |
| `setup-autostart` | Create `scoremore.desktop` in `~/.config/autostart` | — | `mini-bowling.sh setup-autostart` |
| `remove-autostart` | Remove `scoremore.desktop` to disable autostart | — | `mini-bowling.sh remove-autostart` |
| `watchdog` | Check if ScoreMore is running and restart it if not | — | `mini-bowling.sh watchdog` |
| `setup-watchdog` | Manage cron job that runs `watchdog` every 5 minutes | `enable` \| `disable` \| `status` | `mini-bowling.sh setup-watchdog enable` |
| `schedule-deploy` | Add a daily cron job to run `deploy` at the specified time | `HH:MM` (e.g. `02:30`) | `mini-bowling.sh schedule-deploy 02:30` |
| `unschedule-deploy` | Remove the scheduled daily deploy cron job | — | `mini-bowling.sh unschedule-deploy` |
| `serial-log` | Capture Arduino serial output to a background log file | `start` \| `stop` \| `status` \| `tail` | `mini-bowling.sh serial-log start` |
| `console` | Open serial monitor — blocked if `serial-log` is active | — | `mini-bowling.sh console` |
| `list` | List connected Arduino boards (`arduino-cli board list`) | — | `mini-bowling.sh list` |
| `logs` | List recent log files | — | `mini-bowling.sh logs` |
| `logs follow` | Live tail of today's log (Ctrl+C to exit) | — | `mini-bowling.sh logs follow` |
| `logs dump` | Print full contents of today's log, or a specific date with `--date` | `--date YYYY-MM-DD` | `mini-bowling.sh logs dump --date 2026-03-06` |
| `logs tail` | Print last N lines of today's log, or a specific date with `--date` | `[N]` (default: 50) \| `--date YYYY-MM-DD` | `mini-bowling.sh logs tail 100 --date 2026-03-06` |
| `logs clean` | Delete log files (asks for confirmation). Use `--keep N` to retain the last N days | `--keep N` | `mini-bowling.sh logs clean --keep 7` |
| `update-script` | Pull latest version of `mini-bowling.sh` from GitHub, validate syntax, and reinstall | — | `mini-bowling.sh update-script` |
| `backup` | Archive sketches, ScoreMore config, and script (AppImage excluded by default — use `--include-appimage` to include it, keeps last 10) | `--include-appimage` | `mini-bowling.sh backup` |
| `disk-cleanup` | Remove old AppImages, Arduino build caches, and logs older than 30 days | — | `mini-bowling.sh disk-cleanup` |
| `pi-status` | Show CPU temperature, memory usage, disk space, and uptime | — | `mini-bowling.sh pi-status` |
| `pi-update` | Run `apt update && apt upgrade` | — | `mini-bowling.sh pi-update` |
| `pi-reboot` | Reboot with a 5-second countdown — checks sudo access before countdown begins | — | `mini-bowling.sh pi-reboot` |
| `pi-shutdown` | Shut down with a 5-second countdown — checks sudo access before countdown begins | — | `mini-bowling.sh pi-shutdown` |
| `wifi-status` | Show interface, IP, SSID, signal, and internet reachability | — | `mini-bowling.sh wifi-status` |
| `vnc-status` | Check VNC server installation, service state, active displays, autostart, and connect address | — | `mini-bowling.sh vnc-status` |
| `vnc-setup` | Start/stop VNC and enable/disable autostart on boot | `start`, `stop`, `enable-autostart`, `disable-autostart` | `mini-bowling.sh vnc-setup start` |
| `wait-for-network` | Wait up to N seconds for internet connectivity | `[N]` (default: 30) | `mini-bowling.sh wait-for-network 60` |
| `create-dir` | Create project, ScoreMore, and log directories if missing | — | `mini-bowling.sh create-dir` |
| `install-cli` | Install `arduino-cli` to `~/.local/bin` if missing | — | `mini-bowling.sh install-cli` |

## Usage Examples

```bash
# ── Daily workflow ────────────────────────────────────────────────────────────

# Check everything is ready before deploying
mini-bowling.sh preflight

# Preview what deploy would do without making any changes
mini-bowling.sh deploy --dry-run

# Full deploy — pull latest code, upload Everything, restart ScoreMore
mini-bowling.sh deploy

# Deploy from a specific branch
mini-bowling.sh deploy --branch testing

# Upload a specific sketch without pulling git
mini-bowling.sh upload --Master_Test

# Upload without restarting ScoreMore
mini-bowling.sh upload --Everything --no-kill

# ── ScoreMore updates ─────────────────────────────────────────────────────────

# Check if a new version is available
mini-bowling.sh check-scoremore-update

# Download and install the latest version
mini-bowling.sh download latest

# Download a specific version
mini-bowling.sh download 1.8.0

# Roll back to the previous version if something breaks
mini-bowling.sh rollback-scoremore

# List all downloaded versions
mini-bowling.sh scoremore-history

# ── Git / code management ─────────────────────────────────────────────────────

# Check for new commits without pulling
mini-bowling.sh check-update

# Roll back one commit and re-upload if a deploy caused problems
mini-bowling.sh rollback

# Roll back two commits
mini-bowling.sh rollback 2

# ── Pi health ─────────────────────────────────────────────────────────────────

mini-bowling.sh pi-status
mini-bowling.sh wifi-status
mini-bowling.sh vnc-status
mini-bowling.sh vnc-setup start
mini-bowling.sh vnc-setup enable-autostart
mini-bowling.sh pi-update
mini-bowling.sh pi-reboot
mini-bowling.sh pi-shutdown

# ── Logging & diagnostics ─────────────────────────────────────────────────────

# Live follow today's log
mini-bowling.sh logs follow

# Print last 100 lines
mini-bowling.sh logs tail 100

# Start capturing Arduino serial output to a log
mini-bowling.sh serial-log start
mini-bowling.sh serial-log tail
mini-bowling.sh serial-log stop

# Open interactive serial console (only if serial-log is not running)
mini-bowling.sh console

# ── Maintenance ───────────────────────────────────────────────────────────────

# Back up Arduino sketches, ScoreMore config, and the script (AppImage excluded)
mini-bowling.sh backup

# Back up everything including the active ScoreMore AppImage
mini-bowling.sh backup --include-appimage

# Free up SD card space
mini-bowling.sh disk-cleanup

# Delete all log files
mini-bowling.sh logs clean

# Delete all but the last 7 days of logs
mini-bowling.sh logs clean --keep 7

# Check version and whether an update is available
mini-bowling.sh version

# Update the script itself from GitHub
mini-bowling.sh update-script

# ── Testing ───────────────────────────────────────────────────────────────────

# Run unit tests after any change (no hardware needed)
./mini-bowling-test.sh unit

# ── Setup & configuration ─────────────────────────────────────────────────────

# First-time setup wizard
mini-bowling.sh install

# Check all dependencies
mini-bowling.sh doctor

# Enable/disable ScoreMore autostart on login
mini-bowling.sh setup-autostart
mini-bowling.sh remove-autostart

# Enable automatic watchdog (restarts ScoreMore every 5 min if it crashes)
mini-bowling.sh setup-watchdog enable
mini-bowling.sh setup-watchdog disable

# Schedule a daily deploy at 2:30am
mini-bowling.sh schedule-deploy 02:30
mini-bowling.sh unschedule-deploy

# Show script version
mini-bowling.sh version

# Show current status
mini-bowling.sh status
```

## Deploy Cycle

Run `mini-bowling.sh deploy --dry-run` first to preview what will happen without making any changes. Then run `mini-bowling.sh deploy` to execute the full sequence:

1. Verify project directory is a git repository — exits immediately with a clear message if not, before touching anything
2. Write deploy lock file — prevents watchdog from restarting ScoreMore mid-deploy
3. Wait for network (up to 60 seconds, tries 8.8.8.8 / 1.1.1.1 / 9.9.9.9 — handles slow boot and restricted networks)
4. Warn if local git repo has uncommitted changes
5. `git pull` from `main`
6. Verify Arduino port is connected and recognised
7. Verify sketch directory exists — exits before killing ScoreMore if sketch is missing
8. Stop serial logging if running (port needed for upload)
9. Kill ScoreMore gracefully
10. Compile + upload `Everything` sketch (120 second timeout)
11. Restart serial logging if it was running
12. Start ScoreMore
13. Remove deploy lock file
14. Write pass/fail result to deploy status file

The port is always verified before ScoreMore is killed — if the Arduino isn't connected the command exits immediately and ScoreMore is left running. Similarly, if the project directory isn't a git repo, the command exits before killing ScoreMore.

## Deploy Status Tracking

Every time `mini-bowling.sh deploy` runs it records its outcome to `~/Documents/Bowling/logs/.last-deploy-status`. The result is shown in `mini-bowling.sh status`:

```
Last deploy : OK at 2026-03-06 02:30:14 — a1b2c3d: Fix pin debounce timing
Last deploy : FAILED (started 2026-03-06 02:30:01) — a1b2c3d: Fix pin debounce timing
```

If `notify-send` is available (installed by default on Raspberry Pi OS desktop), a desktop notification is also sent when the deploy finishes — useful for unattended 2:30am deploys:

```
✓ mini-bowling: Deploy OK
  a1b2c3d: Fix pin debounce timing

✗ mini-bowling: Deploy FAILED  (critical — red banner)
  a1b2c3d: Fix pin debounce timing
```

If the deploy fails partway through, `FAILED` is written immediately via a shell error trap — so you always know if something went wrong overnight without having to dig through logs.

## Deploy Dry Run

`mini-bowling.sh deploy --dry-run` shows exactly what a deploy would do without making any changes — no git pull, no upload, no ScoreMore restart:

```
--- DRY RUN — no changes will be made ---

  ✓  Network reachable
  ✎  Local commit : abc1234 Fix pin assignment for lane 3
  ✎  Remote ahead : 2 commit(s)
  ✎  Repo state   : clean
  ✓  Arduino port: /dev/ttyACM0 (recognised)
  ✎  ScoreMore is running (pid 82131) — will be killed before upload
  ✓  Sketch found: Everything
  ✓  Disk space: 4823MB free

Dry run complete — no changes made. Run without --dry-run to deploy.
```

Useful before a scheduled deploy window or when troubleshooting a machine you can't be physically present at.

## Updating the Script

To update `mini-bowling.sh` itself to the latest version from GitHub:

```bash
mini-bowling.sh update-script
```

This clones the script repo to `~/.local/share/mini-bowling-script` on first run, then `git pull`s on subsequent runs. Before installing, the downloaded script is validated with `bash -n` — if it fails the syntax check, the update is aborted and the currently installed version is left untouched. If the installed script is in `/usr/bin` or `/usr/local/bin`, `sudo cp` is used automatically. After updating, run `mini-bowling.sh version` to confirm the new version is installed.

If the script is already up to date it reports so without making any changes.

## Rollback

If a deploy breaks something, `mini-bowling.sh rollback [N]` resets the git repo N commits back (default 1) and immediately re-uploads the sketch. It reads the last-uploaded sketch name from the upload history file — so if you last uploaded `Master_Test`, rollback re-uploads `Master_Test`, not `Everything`. Falls back to `Everything` if no history is recorded.

```bash
mini-bowling.sh rollback      # undo last commit and re-upload
mini-bowling.sh rollback 2    # undo last 2 commits and re-upload
```

A 5-second countdown prompt appears before the reset runs, giving you time to Ctrl+C. Once confirmed, the port is verified before ScoreMore is killed — consistent with the standard deploy flow.

## ScoreMore Management

**Downloading:**
```bash
mini-bowling.sh download latest      # fetch and install newest version
mini-bowling.sh download 1.8.0       # install a specific version
```

**Checking for updates:**
```bash
mini-bowling.sh check-scoremore-update
```
Also runs automatically as check #9 in `preflight`.

**Managing versions:**
```bash
mini-bowling.sh scoremore-history            # list all downloaded versions
mini-bowling.sh scoremore-history use 1.7.0  # switch to a specific version
mini-bowling.sh scoremore-history clean      # remove all except active version
mini-bowling.sh rollback-scoremore           # switch to previous version
```

**Version info:**
```bash
mini-bowling.sh scoremore-version    # show active version, path, size, date
```

## ScoreMore Process Management

ScoreMore runs as an Electron AppImage and spawns multiple child processes under `/tmp/.mount_ScoreM*/`. The script kills ScoreMore by targeting the AppImage launcher process by its full path, which brings down the entire process tree. A safety-net `pkill` pass then cleans up any orphaned `scoremore` child processes.

`start-scoremore` is a pure launcher — it does not kill first. All callers (`upload`, `deploy`, `download`) are responsible for calling kill before launching.

The active X display is auto-detected at launch time: `$DISPLAY` from the environment is used if set, otherwise the script scans `who` for a logged-in X session, and falls back to `:0` with a warning. This means ScoreMore appears on the correct screen whether you're sitting at the Pi, connected over VNC (`:1`), or running a scheduled cron deploy.

## ScoreMore Watchdog

The watchdog ensures ScoreMore stays running even if it crashes:

```bash
mini-bowling.sh watchdog                 # check once and restart if needed
mini-bowling.sh setup-watchdog enable    # check every 5 minutes via cron
mini-bowling.sh setup-watchdog disable
mini-bowling.sh setup-watchdog status
```

The watchdog checks for a deploy lock before restarting ScoreMore — if a deploy is actively running (which intentionally kills ScoreMore before uploading), the watchdog skips its restart and exits cleanly. The lock is automatically cleaned up at the end of every deploy.

The watchdog also checks if serial logging was supposed to be running — if the Arduino was unplugged and the serial monitor process died, it restarts logging automatically.

## ScoreMore Autostart

`setup-autostart` creates `~/.config/autostart/scoremore.desktop` using the standard XDG autostart mechanism — any X11 desktop environment (LXDE, XFCE, GNOME, etc.) will automatically launch ScoreMore when the user logs in.

```bash
mini-bowling.sh setup-autostart
mini-bowling.sh remove-autostart
```

## Scheduled Deploy

```bash
mini-bowling.sh schedule-deploy 02:30   # every day at 2:30am
mini-bowling.sh schedule-deploy 14:00   # every day at 2:00pm
mini-bowling.sh unschedule-deploy
```

Re-running `schedule-deploy` with a different time replaces the existing schedule rather than creating a duplicate. The deploy waits up to 60 seconds for the network before running, so it works reliably even if the Pi is still connecting to Wi-Fi at the scheduled time. Deploy status is always recorded so you can check the outcome in `mini-bowling.sh status` the next morning.

If the script is not installed in `/usr/bin` or `/usr/local/bin`, `schedule-deploy` warns you — cron uses a minimal PATH and won't find scripts in non-standard locations. The recommended install path is `/usr/bin/mini-bowling.sh`.

## Arduino Port Verification

Before every `upload` and `deploy`, the script performs two checks before killing ScoreMore:

1. **Device file check** — confirms a character device exists at the expected port (`/dev/ttyACM0`) or scans common patterns (`/dev/ttyACM*`, `/dev/ttyUSB*`)
2. **arduino-cli board list check** — confirms the port appears in `arduino-cli board list`

If either check fails, the script exits immediately with a clear error and ScoreMore is left running.

## Arduino Serial Logging

`serial-log` captures Arduino serial output to a daily log file at `~/Documents/Bowling/logs/arduino-serial-YYYY-MM-DD.log`. Useful for diagnosing hardware issues without being physically present.

```bash
mini-bowling.sh serial-log start    # start background logging
mini-bowling.sh serial-log status   # check if running
mini-bowling.sh serial-log tail     # live follow (Ctrl+C to exit)
mini-bowling.sh serial-log stop     # stop
```

`console` opens an interactive serial monitor in the foreground using `stty` + `cat` directly on the port — no extra tools required. The baud rate is controlled by `BAUD_RATE` in the configuration section (default: `9600`) — change it to match your sketch's `Serial.begin()` call.

`console` cannot run while `serial-log` is active — both use the same serial port. Running `console` while logging is active exits with a message to run `serial-log stop` first.

After every `upload` or `deploy`, serial logging is automatically stopped before the upload (to free the port) and restarted afterward.

## Pre-flight Check

`mini-bowling.sh preflight` runs 9 checks before a deploy without making any changes:

```
  ✓  arduino-cli installed
  ✓  Arduino port found: /dev/ttyACM0
  ✓  Arduino recognised by arduino-cli
  ✓  Internet reachable
  ✓  Disk space: 4823MB free
  ✓  CPU temperature: 48°C
  ✓  Git repo clean
  ✓  ScoreMore symlink valid
  ✓  Git repo up to date with remote
  !  ScoreMore update available: 1.8.0 → 1.8.2 — run: mini-bowling.sh download 1.8.2
```

Warnings (`!`) are non-blocking. Failures (`✗`) should be resolved before deploying.

`mini-bowling.sh preflight --quick` (or `-q`) skips the three network-dependent checks (3 — internet ping, 8 — git fetch, 9 — ScoreMore version check) for a fast local-only result. Useful when you just want to confirm the Arduino is connected and the repo is clean without waiting on network calls:

```
  ✓  arduino-cli installed
  ✓  Arduino port found: /dev/ttyACM0
  -  Internet check skipped (--quick)
  ✓  Disk space: 4823MB free
  ✓  CPU temperature: 48°C
  ✓  Git repo clean
  ✓  ScoreMore symlink valid
  -  Remote git check skipped (--quick)
  -  ScoreMore update check skipped (--quick)

    (3 network checks skipped — run without --quick for full check)

✓ All checks passed — ready to deploy
```

## Logging

All commands that do real work log their output to a daily file in `~/Documents/Bowling/logs/`:

```
~/Documents/Bowling/logs/mini-bowling-2026-03-06.log
```

Each run is separated by a timestamped header. Log files older than 30 days are pruned automatically.

```bash
mini-bowling.sh logs           # list log files
mini-bowling.sh logs follow    # live tail
mini-bowling.sh logs dump      # full output of today
mini-bowling.sh logs dump --date 2026-03-06   # full output of a specific day
mini-bowling.sh logs tail 100  # last 100 lines of today
mini-bowling.sh logs tail 100 --date 2026-03-06  # last 100 lines of a specific day
mini-bowling.sh logs clean     # delete all log files (asks for confirmation)
```

The `--date` flag is particularly useful the morning after a scheduled deploy — the 2:30am deploy ran and completed in yesterday's log file, not today's.

Read-only commands are not logged: `status`, `list`, `logs`, `version`, `pi-status`, `wifi-status`, `vnc-status`, `doctor`, `preflight`, `scoremore-version`, `scoremore-history`, `check-update`, `check-scoremore-update`, `serial-log`, `setup-watchdog`, `watchdog`, and `wait-for-network`.

## Raspberry Pi Management

```bash
mini-bowling.sh pi-status      # CPU temp (colour-coded), memory, disk, uptime
mini-bowling.sh pi-update      # apt update + upgrade, prompts to reboot if needed
mini-bowling.sh pi-reboot      # reboot with 5-second countdown (Ctrl+C to cancel)
mini-bowling.sh pi-shutdown    # shutdown with 5-second countdown
mini-bowling.sh wifi-status    # interface, IP, SSID, signal, internet reachability
mini-bowling.sh vnc-status     # VNC installation, service state, displays, autostart
mini-bowling.sh vnc-setup start             # start VNC now
mini-bowling.sh vnc-setup stop              # stop VNC
mini-bowling.sh vnc-setup enable-autostart  # start VNC automatically on boot
mini-bowling.sh vnc-setup disable-autostart # disable VNC autostart
```

`vnc-status` checks five things: whether a VNC server is installed (RealVNC, TigerVNC, TightVNC, or x11vnc), whether the service is running (via systemd or process scan), which displays and ports are active, whether autostart is configured, and the LAN IP/port to connect from a VNC viewer. If anything is misconfigured it prints the suggested fix command inline.

`vnc-setup` uses `systemctl` to start/stop/enable/disable the VNC service. If no systemd service is found it falls back to `vncserver :1` for start, and `raspi-config` for autostart. The `start` and `stop` subcommands are logged; `vnc-status` is read-only and is not logged.

`pi-update`, `pi-reboot`, and `pi-shutdown` require `sudo`. `pi-status`, `wifi-status`, and `vnc-status` are read-only.

## Dependency Check

`mini-bowling.sh doctor` checks all required tools (`git`, `curl`, `arduino-cli`, `pgrep`, `pkill`, `nohup`, `realpath`, `tee`, `awk`, `df`, `find`) and optional ones (`iwconfig`, `iw`, `sha256sum`), verifies all directories exist, and checks serial port access in two stages: whether the user is in the `dialout` group at all, and whether the current session has that group active (it won't if the group was added after login). Each failure prints the exact fix:

```
Serial port access:
  ✗  gpekarcsik is NOT in the dialout group
     Fix: sudo usermod -aG dialout gpekarcsik
     Then log out and back in (or reboot) for it to take effect.

  !  gpekarcsik is in dialout but needs to log out and back in
     The group was added but this session predates it.
     Fix: log out and back in, or run: newgrp dialout
```

## Backup

`mini-bowling.sh backup` creates a timestamped `.tar.gz` archive of the Arduino project directory, the ScoreMore config folder (`~/.config/ScoreMore`), and the `mini-bowling.sh` script itself, saved to `~/Documents/Bowling/backups/`. The last 10 backups are kept automatically.

The ScoreMore AppImage (~100MB) is excluded by default since it can be re-downloaded. Use `--include-appimage` if you want a fully self-contained backup:

```bash
mini-bowling.sh backup                    # fast — excludes AppImage
mini-bowling.sh backup --include-appimage # complete — includes AppImage
# → ~/Documents/Bowling/backups/mini-bowling-backup-2026-03-06_14-30-00.tar.gz
```

SD cards on Raspberry Pis can fail without warning — run `backup` before major changes.

## Disk Cleanup

`mini-bowling.sh disk-cleanup` removes all non-active ScoreMore AppImages, Arduino build caches (`build/`, `~/.cache/arduino`, `~/.arduino15/cache`), and log files older than 30 days. It also reports the total size of the backups directory. When build caches are removed, a note is printed that the next compile will be slower while arduino-cli rebuilds them.

## Testing

`mini-bowling-test.sh` is a unit test suite that verifies script behaviour after changes — no Arduino or ScoreMore installation required for the unit tests.

```bash
# Unit tests only — no hardware needed, runs in ~15 seconds
./mini-bowling-test.sh unit

# Integration tests — requires Arduino connected and arduino-cli installed
./mini-bowling-test.sh integration

# Run everything
./mini-bowling-test.sh

# Verbose output — shows full command output on failures
./mini-bowling-test.sh unit -v
```

The unit tests cover: syntax validation, `version` output, unknown command handling, version string parsing, port verification logic, `upload` ScoreMore lifecycle flags (non-`Everything` sketches don't touch ScoreMore), `logs` subcommands, `deploy --dry-run`, serial-log conflict guard, `scoremore-history`, `disk-cleanup`, `wait-for-network`, backup file creation, rollback sketch selection, deploy status file format, watchdog deploy lock, update-script syntax check, backup AppImage flag, logs `--date` flag, deploy notify-send, and more — 113 tests in total.

The test script works by sourcing `mini-bowling.sh` with `MINI_BOWLING_SOURCED=1`, which suppresses `main()` execution and allows individual functions to be called and tested in isolation. Hardware-touching functions (`arduino-cli`, `kill_scoremore_gracefully`, etc.) are replaced with lightweight mocks for unit tests.

The test script is self-healing — it automatically fixes Windows line endings and injects the `MINI_BOWLING_SOURCED` sourcing guard if running against an older copy of the script that doesn't have it yet.

**Important:** the test runs against `mini-bowling.sh` in the same directory as `mini-bowling-test.sh`, not the copy installed at `/usr/bin/mini-bowling.sh`. The recommended deploy workflow is:

```bash
# Test first, then install only if all tests pass
./mini-bowling-test.sh unit && sudo cp mini-bowling.sh /usr/bin/mini-bowling.sh
```

## Tab Completion

`mini-bowling-completion.bash` provides tab completion for all commands, subcommands, and flags. Install it once and tab-complete everything:

```bash
# Tab-complete commands
mini-bowling.sh <TAB>
→  backup  check-scoremore-update  check-update  console  deploy ...

# Tab-complete subcommands
mini-bowling.sh logs <TAB>
→  clean  dump  follow  list  tail

mini-bowling.sh serial-log <TAB>
→  start  status  stop  tail

mini-bowling.sh vnc-setup <TAB>
→  disable-autostart  enable-autostart  start  stop

# Tab-complete flags
mini-bowling.sh deploy <TAB>
→  --branch  --dry-run  --no-kill

mini-bowling.sh logs tail <TAB>
→  50  100  200  --date

mini-bowling.sh logs dump <TAB>
→  --date

mini-bowling.sh backup <TAB>
→  --include-appimage

mini-bowling.sh preflight <TAB>
→  --quick  -q

# Tab-complete sketch names from the project directory
mini-bowling.sh upload <TAB>
→  --Everything  --Master_Test  --Homing  --list-sketches ...

# Tab-complete ScoreMore versions from downloaded AppImages
mini-bowling.sh scoremore-history use <TAB>
→  1.8.2  1.8.0  1.7.1 ...
```

**Install system-wide** (recommended — works for all users and cron):
```bash
sudo cp mini-bowling-completion.bash /etc/bash_completion.d/mini-bowling.sh
source /etc/bash_completion.d/mini-bowling.sh
```

**Install for current user only:**
```bash
mkdir -p ~/.local/share/bash-completion/completions
cp mini-bowling-completion.bash ~/.local/share/bash-completion/completions/mini-bowling.sh
source ~/.local/share/bash-completion/completions/mini-bowling.sh
```

The completion is active immediately after sourcing. It will load automatically in new shells once installed in either location.

## Script Version

`mini-bowling.sh version` shows version, install path, last-modified date, shell version, and checks GitHub for a newer version — printing a prompt to run `update-script` if one is available. The version number is `SCRIPT_VERSION` at the top of the script — bump it when deploying updates.

## Configuration Reference

All configuration variables are at the top of the script:

| Variable | Default | Description |
|---|---|---|
| `SCRIPT_VERSION` | `1.0.0` | Script version — bump when deploying updates |
| `DEFAULT_GIT_BRANCH` | `main` | Branch used by `update` and `deploy` |
| `PROJECT_DIR` | `~/Documents/Bowling/Arduino/mini-bowling` | Arduino sketch root (override with `$MINI_BOWLING_DIR`) |
| `DEFAULT_PORT` | `/dev/ttyACM0` | Arduino serial port (override with `$PORT` at runtime) |
| `BOARD` | `arduino:avr:mega` | arduino-cli FQBN |
| `SCOREMORE_DIR` | `~/Documents/Bowling/ScoreMore` | Where downloaded AppImages are saved |
| `LOG_DIR` | `~/Documents/Bowling/logs` | Where daily log files are written |
| `SYMLINK_PATH` | `~/Desktop/ScoreMore.AppImage` | Desktop symlink maintained by `download` |
| `BAUD_RATE` | `9600` | Serial baud rate used by `console` and `serial-log` — must match `Serial.begin()` in your sketch |
| `ARCH` | `arm64` | AppImage architecture suffix |

The `PORT` variable can be overridden at runtime without editing the script:
```bash
PORT=/dev/ttyUSB0 mini-bowling.sh upload --Everything
```

## Project Structure Expectations

### Arduino sketches

All sketches should live in subfolders directly under the project directory:

```
~/Documents/Bowling/Arduino/mini-bowling/
├── Everything/
│   └── Everything.ino
├── Master_Test/
│   └── Master_Test.ino
├── Homing/
│   └── Homing.ino
├── Calibration/
│   └── calib_main.ino      ← .ino name doesn't have to match folder name
└── ...
```

Folder names are used as the sketch identifier (`--FolderName`). Only direct subfolders are scanned. Folders named `build`, `cache`, `dist`, `tmp`, `node_modules`, `libraries`, or starting with `.` are skipped.

### File locations

| Path | Purpose |
|---|---|
| `~/Documents/Bowling/Arduino/mini-bowling/` | Arduino sketches (git repo) |
| `~/Documents/Bowling/ScoreMore/ScoreMore-<ver>-arm64.AppImage` | Downloaded AppImages |
| `~/Desktop/ScoreMore.AppImage` | Symlink to active AppImage |
| `~/.config/autostart/scoremore.desktop` | XDG autostart entry (when enabled) |
| `~/Documents/Bowling/logs/mini-bowling-YYYY-MM-DD.log` | Daily command logs |
| `~/Documents/Bowling/logs/arduino-serial-YYYY-MM-DD.log` | Arduino serial log |
| `~/Documents/Bowling/logs/.last-deploy-status` | Last deploy pass/fail record |
| `~/Documents/Bowling/backups/mini-bowling-backup-*.tar.gz` | Backups |
| `./mini-bowling-test.sh` | Unit test suite (lives alongside the script) |
