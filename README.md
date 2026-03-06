# mini-bowling

Helper script for **mini-bowling** Arduino + ScoreMore development workflow  
(Raspberry Pi / Linux focused)

This script simplifies common tasks when developing and deploying code for a mini-bowling setup that uses:

- Arduino Mega (`arduino:avr:mega`) for hardware control
- ScoreMore bowling scoring software (Linux AppImage version)

## Features

**Arduino & Deploy**
- Compile + upload selected sketch to Arduino, then restart ScoreMore
- Port verification before upload — errors out before killing ScoreMore if Arduino is not reachable
- Full deploy cycle (`deploy`) — wait for network → kill → pull → upload → restart ScoreMore, with pass/fail status recorded
- Roll back to a previous git commit and re-upload (`rollback`)
- Git operations with dirty-repo warning (`update`)
- Check for remote git commits without pulling (`check-update`)
- Upload timeout — fails cleanly if arduino-cli hangs rather than blocking forever

**ScoreMore**
- Download a specific or latest ScoreMore version with disk space guard and integrity check (`download`)
- Check scoremorebowling.com for newer versions (`check-scoremore-update`)
- Manage downloaded ScoreMore versions — list, switch, and roll back (`scoremore-history`, `rollback-scoremore`)
- Graceful start/stop of ScoreMore (kills by AppImage path, cleans up orphaned Electron processes)
- ScoreMore watchdog — auto-restart if ScoreMore crashes, with cron scheduling (`watchdog`, `setup-watchdog`)
- Configure ScoreMore to auto-start on login (`setup-autostart` / `remove-autostart`)

**Diagnostics & Monitoring**
- Status overview — port, Arduino detection, ScoreMore state, autostart, watchdog, serial log, schedule, last deploy result (`status`)
- Pre-flight check before deploying — 9 checks including ScoreMore and git update availability (`preflight`)
- Dependency checker (`doctor`)
- Arduino serial output logging to file in the background (`serial-log`)
- Arduino serial console — blocked if serial logging is already active (`console`)
- Deploy status tracking — pass/fail recorded after every deploy, visible in `status`

**Raspberry Pi**
- Pi health overview — CPU temp, memory, disk, uptime (`pi-status`)
- OS updates, reboot, and shutdown with safety countdowns (`pi-update`, `pi-reboot`, `pi-shutdown`)
- Wi-Fi diagnostics — interface, IP, SSID, signal, internet reachability (`wifi-status`)

**Maintenance**
- Config, sketch, and script backup with automatic 10-backup retention (`backup`)
- Disk cleanup — old AppImages, build caches, and logs (`disk-cleanup`)
- Logging of all output to daily log files with 30-day automatic retention
- Required directories created automatically on first run
- Guided first-time setup wizard (`install`)
- Script version info (`version`)

## Requirements

- `arduino-cli` installed and configured — the script can install it via `mini-bowling install-cli`
- `git` in the project directory
- `curl`, `realpath`, `pgrep`, `pkill`, `nohup`
- Write access to `~/Desktop` (for the ScoreMore symlink)
- Write access to `~/.config/autostart` (for autostart configuration)
- X11 display available at `:0` (for launching the ScoreMore GUI)

## Installation / Configuration

Clone the project from the mini-bowling Git repo:
```bash
git clone https://github.com/mini-bowling/mini-bowling.git
cd mini-bowling
```

Make the script executable and copy it to `/usr/bin` so it is available system-wide and cron jobs can find it by name:
```bash
chmod +x mini-bowling
sudo cp mini-bowling /usr/bin/mini-bowling
```

Verify the script is accessible:
```bash
$ which mini-bowling
/usr/bin/mini-bowling

$ mini-bowling
Usage: mini-bowling <command> [options]
...
```

Now run the guided setup wizard:
```bash
mini-bowling install
```

The `install` wizard runs through 6 steps: creating directories, installing `arduino-cli`, configuring ScoreMore autostart, running a dependency check, optionally enabling the ScoreMore watchdog, and optionally scheduling a daily deploy. You can also run each step manually:

```bash
mini-bowling create-dir
mini-bowling install-cli
mini-bowling setup-autostart
mini-bowling doctor
mini-bowling setup-watchdog enable
mini-bowling schedule-deploy 02:30
```

**Download ScoreMore** — if you haven't already, download the latest version now:
```bash
mini-bowling download latest
```

**Find and configure your Arduino port** — connect the Arduino and run:
```bash
mini-bowling list
```

Look for the port showing `Arduino Mega or Mega 2560` in the Board Name column (typically `/dev/ttyACM0`). Open the script and update these two variables near the top to match:
```bash
readonly DEFAULT_PORT="/dev/ttyACM0"
readonly BOARD="arduino:avr:mega"
```

Then re-copy the updated script to `/usr/bin`:
```bash
sudo cp mini-bowling /usr/bin/mini-bowling
```

See the [Finding the Arduino Port](#finding-the-arduino-port) section for full details and troubleshooting.

Run `preflight` to confirm everything is ready:
```bash
mini-bowling preflight
```

Then `status` to confirm the full setup:
```bash
$ mini-bowling status
Project dir : /home/gpekarcsik/Documents/Bowling/Arduino/mini-bowling
Port        : /dev/ttyACM0
Arduino     : detected
ScoreMore   : running (pid 82131)
Autostart   : enabled
Watchdog    : enabled (every 5 min)
Serial log  : not running
Scheduled   : daily at 02:30
Last deploy : no record
Done.
```

You're ready to run your first deploy — see the [Deploy Cycle](#deploy-cycle) section for a full breakdown of what happens when you run it:
```bash
mini-bowling deploy
```

## Finding the Arduino Port

Connect the Arduino and run:
```bash
mini-bowling list
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
sudo cp mini-bowling /usr/bin/mini-bowling
```

## Available Commands

| Command | Description | Options / Arguments | Example Usage |
|---|---|---|---|
| `version` | Show script version, install path, last-modified date, and shell version | — | `mini-bowling version` |
| `status` | Show port, Arduino detection, ScoreMore state, watchdog, serial log, schedule, and last deploy result | — | `mini-bowling status` |
| `install` | Guided first-time setup wizard (directories, arduino-cli, autostart, doctor, watchdog, schedule) | — | `mini-bowling install` |
| `preflight` | Run 9 pre-deploy checks — Arduino, network, disk, CPU temp, git state, symlink, remote updates, ScoreMore version | — | `mini-bowling preflight` |
| `doctor` | Check all required and optional dependencies are installed | — | `mini-bowling doctor` |
| `deploy` | Wait for network → pull latest → kill ScoreMore → upload `Everything` → restart ScoreMore | `--no-kill` \| `-k` \| `--branch <n>` | `mini-bowling deploy` |
| `upload` | Compile + upload sketch → restart ScoreMore (default: `Everything`) | `--FolderName` \| `--list-sketches` \| `--branch <n>` \| `--no-kill` | `mini-bowling upload --Master_Test` |
| `upload --list-sketches` | List all subfolders containing at least one `*.ino` file | — | `mini-bowling upload --list-sketches` |
| `update` | `git pull` latest changes (warns if repo is dirty) | — | `mini-bowling update` |
| `check-update` | Fetch remote and show new commits without pulling | — | `mini-bowling check-update` |
| `rollback` | Reset N git commits and re-upload `Everything` sketch | `[N]` (default: 1) | `mini-bowling rollback` |
| `download` | Download ScoreMore AppImage → update symlink → restart app | `<version>` or `latest` | `mini-bowling download latest` |
| `check-scoremore-update` | Fetch scoremorebowling.com and compare latest version to installed | — | `mini-bowling check-scoremore-update` |
| `scoremore-version` | Show the currently active ScoreMore version and AppImage details | — | `mini-bowling scoremore-version` |
| `scoremore-history` | List downloaded AppImage versions, switch to a version, or remove old ones | `list` \| `use <ver>` \| `clean` | `mini-bowling scoremore-history list` |
| `rollback-scoremore` | Switch to the previously downloaded ScoreMore version | — | `mini-bowling rollback-scoremore` |
| `start-scoremore` | Launch `ScoreMore.AppImage` in the background (`DISPLAY=:0`) | — | `mini-bowling start-scoremore` |
| `setup-autostart` | Create `scoremore.desktop` in `~/.config/autostart` | — | `mini-bowling setup-autostart` |
| `remove-autostart` | Remove `scoremore.desktop` to disable autostart | — | `mini-bowling remove-autostart` |
| `watchdog` | Check if ScoreMore is running and restart it if not | — | `mini-bowling watchdog` |
| `setup-watchdog` | Manage cron job that runs `watchdog` every 5 minutes | `enable` \| `disable` \| `status` | `mini-bowling setup-watchdog enable` |
| `schedule-deploy` | Add a daily cron job to run `deploy` at the specified time | `HH:MM` (e.g. `02:30`) | `mini-bowling schedule-deploy 02:30` |
| `unschedule-deploy` | Remove the scheduled daily deploy cron job | — | `mini-bowling unschedule-deploy` |
| `serial-log` | Capture Arduino serial output to a background log file | `start` \| `stop` \| `status` \| `tail` | `mini-bowling serial-log start` |
| `console` | Open serial monitor — blocked if `serial-log` is active | — | `mini-bowling console` |
| `list` | List connected Arduino boards (`arduino-cli board list`) | — | `mini-bowling list` |
| `logs` | List recent log files | — | `mini-bowling logs` |
| `logs follow` | Live tail of today's log (Ctrl+C to exit) | — | `mini-bowling logs follow` |
| `logs dump` | Print full contents of today's log | — | `mini-bowling logs dump` |
| `logs tail` | Print last N lines of today's log | `[N]` (default: 50) | `mini-bowling logs tail 100` |
| `backup` | Archive sketches, ScoreMore config, and script to a timestamped file (keeps last 10) | — | `mini-bowling backup` |
| `disk-cleanup` | Remove old AppImages, Arduino build caches, and logs older than 30 days | — | `mini-bowling disk-cleanup` |
| `pi-status` | Show CPU temperature, memory usage, disk space, and uptime | — | `mini-bowling pi-status` |
| `pi-update` | Run `apt update && apt upgrade` | — | `mini-bowling pi-update` |
| `pi-reboot` | Reboot with a 5-second countdown | — | `mini-bowling pi-reboot` |
| `pi-shutdown` | Shut down with a 5-second countdown | — | `mini-bowling pi-shutdown` |
| `wifi-status` | Show interface, IP, SSID, signal, and internet reachability | — | `mini-bowling wifi-status` |
| `wait-for-network` | Wait up to N seconds for internet connectivity | `[N]` (default: 30) | `mini-bowling wait-for-network 60` |
| `create-dir` | Create project, ScoreMore, and log directories if missing | — | `mini-bowling create-dir` |
| `install-cli` | Install `arduino-cli` to `~/.local/bin` if missing | — | `mini-bowling install-cli` |

## Usage Examples

```bash
# ── Daily workflow ────────────────────────────────────────────────────────────

# Check everything is ready before deploying
mini-bowling preflight

# Full deploy — pull latest code, upload Everything, restart ScoreMore
mini-bowling deploy

# Deploy from a specific branch
mini-bowling deploy --branch testing

# Upload a specific sketch without pulling git
mini-bowling upload --Master_Test

# Upload without restarting ScoreMore
mini-bowling upload --Everything --no-kill

# ── ScoreMore updates ─────────────────────────────────────────────────────────

# Check if a new version is available
mini-bowling check-scoremore-update

# Download and install the latest version
mini-bowling download latest

# Download a specific version
mini-bowling download 1.8.0

# Roll back to the previous version if something breaks
mini-bowling rollback-scoremore

# List all downloaded versions
mini-bowling scoremore-history

# ── Git / code management ─────────────────────────────────────────────────────

# Check for new commits without pulling
mini-bowling check-update

# Roll back one commit and re-upload if a deploy caused problems
mini-bowling rollback

# Roll back two commits
mini-bowling rollback 2

# ── Pi health ─────────────────────────────────────────────────────────────────

mini-bowling pi-status
mini-bowling wifi-status
mini-bowling pi-update
mini-bowling pi-reboot
mini-bowling pi-shutdown

# ── Logging & diagnostics ─────────────────────────────────────────────────────

# Live follow today's log
mini-bowling logs follow

# Print last 100 lines
mini-bowling logs tail 100

# Start capturing Arduino serial output to a log
mini-bowling serial-log start
mini-bowling serial-log tail
mini-bowling serial-log stop

# Open interactive serial console (only if serial-log is not running)
mini-bowling console

# ── Maintenance ───────────────────────────────────────────────────────────────

# Back up Arduino sketches, ScoreMore config, and the script
mini-bowling backup

# Free up SD card space
mini-bowling disk-cleanup

# ── Setup & configuration ─────────────────────────────────────────────────────

# First-time setup wizard
mini-bowling install

# Check all dependencies
mini-bowling doctor

# Enable/disable ScoreMore autostart on login
mini-bowling setup-autostart
mini-bowling remove-autostart

# Enable automatic watchdog (restarts ScoreMore every 5 min if it crashes)
mini-bowling setup-watchdog enable
mini-bowling setup-watchdog disable

# Schedule a daily deploy at 2:30am
mini-bowling schedule-deploy 02:30
mini-bowling unschedule-deploy

# Show script version
mini-bowling version

# Show current status
mini-bowling status
```

## Deploy Cycle

Running `mini-bowling deploy` executes this sequence:

1. Wait for network (up to 60 seconds — handles slow boot on Pi)
2. Warn if local git repo has uncommitted changes
3. `git pull` from `main`
4. Verify Arduino port is connected and recognised
5. Stop serial logging if running (port needed for upload)
6. Kill ScoreMore gracefully
7. Compile + upload `Everything` sketch (120 second timeout)
8. Restart serial logging if it was running
9. Start ScoreMore
10. Write pass/fail result to deploy status file

The port is always verified before ScoreMore is killed — if the Arduino isn't connected the command exits immediately and ScoreMore is left running.

## Deploy Status Tracking

Every time `mini-bowling deploy` runs it records its outcome to `~/Documents/Bowling/logs/.last-deploy-status`. The result is shown in `mini-bowling status`:

```
Last deploy : OK at 2026-03-06 02:30:14
Last deploy : FAILED (started 2026-03-06 02:30:01)
```

If the deploy fails partway through, `FAILED` is written immediately via a shell error trap — so you always know if something went wrong overnight without having to dig through logs.

## Rollback

If a deploy breaks something, `mini-bowling rollback [N]` resets the git repo N commits back (default 1) and immediately re-uploads the `Everything` sketch:

```bash
mini-bowling rollback      # undo last commit and re-upload
mini-bowling rollback 2    # undo last 2 commits and re-upload
```

A 5-second countdown prompt appears before the reset runs, giving you time to Ctrl+C. Once confirmed, the port is verified before ScoreMore is killed — consistent with the standard deploy flow.

## ScoreMore Management

**Downloading:**
```bash
mini-bowling download latest      # fetch and install newest version
mini-bowling download 1.8.0       # install a specific version
```

**Checking for updates:**
```bash
mini-bowling check-scoremore-update
```
Also runs automatically as check #9 in `preflight`.

**Managing versions:**
```bash
mini-bowling scoremore-history            # list all downloaded versions
mini-bowling scoremore-history use 1.7.0  # switch to a specific version
mini-bowling scoremore-history clean      # remove all except active version
mini-bowling rollback-scoremore           # switch to previous version
```

**Version info:**
```bash
mini-bowling scoremore-version    # show active version, path, size, date
```

## ScoreMore Process Management

ScoreMore runs as an Electron AppImage and spawns multiple child processes under `/tmp/.mount_ScoreM*/`. The script kills ScoreMore by targeting the AppImage launcher process by its full path, which brings down the entire process tree. A safety-net `pkill` pass then cleans up any orphaned `scoremore` child processes.

`start-scoremore` is a pure launcher — it does not kill first. All callers (`upload`, `deploy`, `download`) are responsible for calling kill before launching.

The `DISPLAY=:0` environment variable is set before launching so the GUI appears on the connected screen even when the script is run over SSH.

## ScoreMore Watchdog

The watchdog ensures ScoreMore stays running even if it crashes:

```bash
mini-bowling watchdog                 # check once and restart if needed
mini-bowling setup-watchdog enable    # check every 5 minutes via cron
mini-bowling setup-watchdog disable
mini-bowling setup-watchdog status
```

The watchdog also checks if serial logging was supposed to be running — if the Arduino was unplugged and the serial monitor process died, it restarts logging automatically.

## ScoreMore Autostart

`setup-autostart` creates `~/.config/autostart/scoremore.desktop` using the standard XDG autostart mechanism — any X11 desktop environment (LXDE, XFCE, GNOME, etc.) will automatically launch ScoreMore when the user logs in.

```bash
mini-bowling setup-autostart
mini-bowling remove-autostart
```

## Scheduled Deploy

```bash
mini-bowling schedule-deploy 02:30   # every day at 2:30am
mini-bowling schedule-deploy 14:00   # every day at 2:00pm
mini-bowling unschedule-deploy
```

Re-running `schedule-deploy` with a different time replaces the existing schedule rather than creating a duplicate. The deploy waits up to 60 seconds for the network before running, so it works reliably even if the Pi is still connecting to Wi-Fi at the scheduled time. Deploy status is always recorded so you can check the outcome in `mini-bowling status` the next morning.

## Arduino Port Verification

Before every `upload` and `deploy`, the script performs two checks before killing ScoreMore:

1. **Device file check** — confirms a character device exists at the expected port (`/dev/ttyACM0`) or scans common patterns (`/dev/ttyACM*`, `/dev/ttyUSB*`)
2. **arduino-cli board list check** — confirms the port appears in `arduino-cli board list`

If either check fails, the script exits immediately with a clear error and ScoreMore is left running.

## Arduino Serial Logging

`serial-log` runs `arduino-cli monitor` in the background and appends serial output to a daily log file at `~/Documents/Bowling/logs/arduino-serial-YYYY-MM-DD.log`. Useful for diagnosing hardware issues without being physically present.

```bash
mini-bowling serial-log start    # start background logging
mini-bowling serial-log status   # check if running
mini-bowling serial-log tail     # live follow (Ctrl+C to exit)
mini-bowling serial-log stop     # stop
```

`console` cannot run while `serial-log` is active — both use the same serial port. Running `console` while logging is active exits with a message to run `serial-log stop` first.

After every `upload` or `deploy`, serial logging is automatically stopped before the upload (to free the port) and restarted afterward.

## Pre-flight Check

`mini-bowling preflight` runs 9 checks before a deploy without making any changes:

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
  !  ScoreMore update available: 1.8.0 → 1.8.2 — run: mini-bowling download 1.8.2
```

Warnings (`!`) are non-blocking. Failures (`✗`) should be resolved before deploying.

## Logging

All commands that do real work log their output to a daily file in `~/Documents/Bowling/logs/`:

```
~/Documents/Bowling/logs/mini-bowling-2026-03-06.log
```

Each run is separated by a timestamped header. Log files older than 30 days are pruned automatically.

```bash
mini-bowling logs           # list log files
mini-bowling logs follow    # live tail
mini-bowling logs dump      # full output
mini-bowling logs tail 100  # last 100 lines
```

Read-only commands are not logged: `status`, `list`, `logs`, `version`, `pi-status`, `wifi-status`, `doctor`, `preflight`, `scoremore-version`, `scoremore-history`, `check-update`, `check-scoremore-update`, `serial-log`, `setup-watchdog`, `watchdog`, and `wait-for-network`.

## Raspberry Pi Management

```bash
mini-bowling pi-status      # CPU temp (colour-coded), memory, disk, uptime
mini-bowling pi-update      # apt update + upgrade, prompts to reboot if needed
mini-bowling pi-reboot      # reboot with 5-second countdown (Ctrl+C to cancel)
mini-bowling pi-shutdown    # shutdown with 5-second countdown
mini-bowling wifi-status    # interface, IP, SSID, signal, internet reachability
```

`pi-update`, `pi-reboot`, and `pi-shutdown` require `sudo`. `pi-status` and `wifi-status` are read-only.

## Dependency Check

`mini-bowling doctor` checks all required tools (`git`, `curl`, `arduino-cli`, `pgrep`, `pkill`, `nohup`, `realpath`, `tee`, `awk`, `df`, `find`) and optional ones (`iwconfig`, `iw`, `sha256sum`), and verifies all directories exist.

## Backup

`mini-bowling backup` creates a timestamped `.tar.gz` archive of the Arduino project directory, the ScoreMore config folder (`~/.config/ScoreMore`), and the `mini-bowling` script itself, saved to `~/Documents/Bowling/backups/`. The last 10 backups are kept automatically.

```bash
mini-bowling backup
# → ~/Documents/Bowling/backups/mini-bowling-backup-2026-03-06_14-30-00.tar.gz
```

SD cards on Raspberry Pis can fail without warning — run `backup` before major changes.

## Disk Cleanup

`mini-bowling disk-cleanup` removes all non-active ScoreMore AppImages, Arduino build caches (`build/`, `~/.cache/arduino`, `~/.arduino15/cache`), and log files older than 30 days. It also reports the total size of the backups directory.

## Script Version

`mini-bowling version` shows version, install path, last-modified date, and shell version. The version number is `SCRIPT_VERSION` at the top of the script — bump it when deploying updates.

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
| `ARCH` | `arm64` | AppImage architecture suffix |

The `PORT` variable can be overridden at runtime without editing the script:
```bash
PORT=/dev/ttyUSB0 mini-bowling upload --Everything
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
