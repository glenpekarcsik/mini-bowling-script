#!/usr/bin/env bash
#
# Helper script for mini-bowling Arduino + ScoreMore development workflow
#
# Usage examples:
#   mini-bowling update
#   mini-bowling upload --Master_Test
#   mini-bowling upload --list-sketches
#   mini-bowling deploy --no-kill
#   mini-bowling download 1.8.0
#

set -euo pipefail
IFS=$'\n\t'

# ------------------------------------------------
#  Configuration
# ------------------------------------------------

readonly DEFAULT_GIT_BRANCH="main"
readonly SCRIPT_VERSION="1.0.0"
readonly PROJECT_DIR="${MINI_BOWLING_DIR:-$HOME/Documents/Bowling/Arduino/mini-bowling}"
readonly DEFAULT_PORT="/dev/ttyACM0"
readonly BOARD="arduino:avr:mega"

readonly SCOREMORE_DIR="$HOME/Documents/Bowling/ScoreMore"
readonly BASE_URL="https://scoremorebowling.b-cdn.net/downloads"
readonly APP_NAME="ScoreMore"
readonly ARCH="arm64"
readonly EXTENSION="AppImage"

readonly SYMLINK_PATH="$HOME/Desktop/ScoreMore.AppImage"

readonly LOG_DIR="$HOME/Documents/Bowling/logs"
readonly DEPLOY_STATUS_FILE="$LOG_DIR/.last-deploy-status"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# ------------------------------------------------
#  Helpers
# ------------------------------------------------

die() {
    echo -e "${RED}Error:${NC} $*" >&2
    exit 1
}

setup_logging() {
    mkdir -p "$LOG_DIR" || { echo "Warning: cannot create log dir $LOG_DIR" >&2; return; }

    local log_file="$LOG_DIR/mini-bowling-$(date '+%Y-%m-%d').log"

    {
        echo "----------------------------------------"
        echo "$(date '+%Y-%m-%d %H:%M:%S')  mini-bowling $*"
        echo "----------------------------------------"
    } >> "$log_file"

    # Store log path for use by log_cmd wrapper — avoid exec redirects
    # which are unreliable with some shells/Pi configurations
    export MINI_BOWLING_LOG="$log_file"
}

# Wrapper: run a command and tee its stdout to the log
# Usage: log_run cmd arg1 arg2 ...
log_run() {
    if [[ -n "${MINI_BOWLING_LOG:-}" ]]; then
        "$@" 2>&1 | tee -a "$MINI_BOWLING_LOG"
        return "${PIPESTATUS[0]}"
    else
        "$@"
    fi
}

prune_logs() {
    [[ -d "$LOG_DIR" ]] || return 0
    local pruned=0
    while IFS= read -r -d '' f; do
        rm -f -- "$f"
        pruned=$((pruned + 1))
    done < <(find "$LOG_DIR" -maxdepth 1 -name "mini-bowling-*.log" \
                  -mtime +30 -print0 2>/dev/null)
    [[ $pruned -gt 0 ]] && echo "→ Pruned $pruned log file(s) older than 30 days" || true
}

show_logs() {
    local subcmd="${1:-list}"
    shift 2>/dev/null || true

    # Resolve today's log path
    local today_log="$LOG_DIR/mini-bowling-$(date '+%Y-%m-%d').log"

    case "$subcmd" in
        list)
            if [[ ! -d "$LOG_DIR" ]]; then
                echo "Log directory not found: $LOG_DIR"
                return 0
            fi

            local files
            mapfile -t files < <(find "$LOG_DIR" -maxdepth 1 -name "mini-bowling-*.log" \
                                      2>/dev/null | sort -r | head -30)

            if [[ ${#files[@]} -eq 0 ]]; then
                echo "No log files found in $LOG_DIR"
                return 0
            fi

            echo "Log files in $LOG_DIR (most recent first):"
            for f in "${files[@]}"; do
                printf "  %-45s  %s\n" "$(basename "$f")" "$(du -h "$f" | cut -f1)"
            done
            echo
            echo "Commands:"
            echo "  mini-bowling logs follow        live follow today's log"
            echo "  mini-bowling logs dump          full output of today's log"
            echo "  mini-bowling logs tail [N]      last N lines of today's log (default: 50)"
            ;;

        follow)
            [[ -f "$today_log" ]] || die "No log file for today: $today_log"
            echo "Following $today_log  (Ctrl+C to exit)"
            echo "----------------------------------------"
            tail -f "$today_log"
            ;;

        dump)
            [[ -f "$today_log" ]] || die "No log file for today: $today_log"
            echo "=== $today_log ==="
            echo
            cat "$today_log"
            ;;

        tail)
            local n="${1:-50}"
            [[ "$n" =~ ^[0-9]+$ ]] || die "Invalid line count: '$n' — must be a number"
            [[ -f "$today_log" ]] || die "No log file for today: $today_log"
            echo "=== Last $n lines of $today_log ==="
            echo
            tail -n "$n" "$today_log"
            ;;

        *)
            die "Unknown logs subcommand: '$subcmd' — use list, follow, dump, or tail [N]"
            ;;
    esac
}

require_project_dir() {
    cd "$PROJECT_DIR" || die "Cannot cd to project directory: $PROJECT_DIR (does it exist?)"
}

# Ensure arduino-cli is available before commands that need it
require_arduino_cli() {
    command -v arduino-cli >/dev/null 2>&1 || \
        die "arduino-cli not found. Run: mini-bowling install-cli"
}

find_arduino_port() {
    local port="${PORT:-$DEFAULT_PORT}"

    if [[ -c "$port" ]]; then
        echo "$port"
        return 0
    fi

    # Simple fallback detection
    for candidate in /dev/ttyACM* /dev/ttyUSB* /dev/cu.usbmodem* /dev/serial/by-id/*; do
        if [[ -c "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    # Return empty and non-zero — callers using $() must check the result
    return 1
}

# Confirm arduino-cli can actually see the board on the given port
verify_arduino_port() {
    local port="$1"

    # Guard against empty port — means find_arduino_port failed inside $()
    [[ -z "$port" ]] && die "No Arduino serial port found — is the Arduino connected?"

    echo "→ Verifying Arduino on $port..."

    # arduino-cli board list exits 0 even when nothing is found, so check output
    local board_output
    board_output=$(arduino-cli board list 2>/dev/null) || \
        die "arduino-cli board list failed — is arduino-cli installed and configured?"

    if ! echo "$board_output" | grep -q "$port"; then
        echo -e "${RED}Error:${NC} Port $port is not recognised by arduino-cli."
        echo
        echo "Current arduino-cli board list output:"
        echo "$board_output"
        echo
        echo "Check that the Arduino is connected and try: mini-bowling list"
        exit 1
    fi

    echo -e "${GREEN}→ Arduino detected on $port${NC}"
}

kill_scoremore_gracefully() {
    # Target the AppImage launcher by full path — killing the parent brings down
    # the entire Electron process tree that spawns under /tmp/.mount_ScoreM*/
    local pid
    pid=$(pgrep -f "ScoreMore.AppImage" 2>/dev/null | head -1) || true
    [[ -z "$pid" ]] && return 0

    echo "Found ScoreMore AppImage (pid $pid) — sending SIGTERM..."
    kill -- "$pid" 2>/dev/null || true

    local timeout=10
    while kill -0 -- "$pid" 2>/dev/null && [[ $timeout -gt 0 ]]; do
        sleep 1
        timeout=$(( timeout - 1 ))
    done

    if kill -0 -- "$pid" 2>/dev/null; then
        echo "→ still running after timeout → sending SIGKILL"
        kill -9 -- "$pid" 2>/dev/null || true
        echo "→ killed (forced)"
    else
        echo "→ stopped gracefully"
    fi

    # Safety net: catch any orphaned scoremore processes that didn't die with the parent
    if pgrep -f "scoremore" >/dev/null 2>&1; then
        echo "→ cleaning up orphaned scoremore processes..."
        pkill -f "scoremore" 2>/dev/null || true
        sleep 1
        pkill -9 -f "scoremore" 2>/dev/null || true
    fi
}

# Pure launcher — callers are responsible for killing ScoreMore first if needed
start_scoremore() {
    export DISPLAY=:0
    # Redirect output to avoid nohup.out clutter; disown so it survives terminal close
    nohup "$HOME/Desktop/ScoreMore.AppImage" > /dev/null 2>&1 &
    disown
    echo -e "${GREEN}→ ScoreMore launched${NC}"
}

print_status() {
    local port
    port=$(find_arduino_port 2>/dev/null || echo "not found")

    echo "Project dir : $PROJECT_DIR"
    echo "Port        : $port"
    [[ -c "$port" ]] && echo "Arduino     : detected" || echo "Arduino     : NOT detected"

    local sm_pid
    sm_pid=$(pgrep -f "ScoreMore.AppImage" 2>/dev/null | head -1 || true)
    if [[ -n "$sm_pid" ]]; then
        echo "ScoreMore   : running (pid $sm_pid)"
    else
        echo "ScoreMore   : not running"
    fi

    local desktop_file="$HOME/.config/autostart/scoremore.desktop"
    if [[ -f "$desktop_file" ]]; then
        echo "Autostart   : enabled"
    else
        echo "Autostart   : disabled"
    fi

    local cron_marker_sched="# mini-bowling scheduled deploy"
    local cron_entry
    cron_entry=$(crontab -l 2>/dev/null | grep "$cron_marker_sched" || true)
    if [[ -n "$cron_entry" ]]; then
        local cron_min cron_hour
        cron_min=$(echo "$cron_entry" | awk '{print $1}')
        cron_hour=$(echo "$cron_entry" | awk '{print $2}')
        printf "Scheduled   : daily at %02d:%02d\n" "$cron_hour" "$cron_min"
    else
        echo "Scheduled   : not set"
    fi

    local cron_marker_wd="# mini-bowling watchdog"
    local wd_entry
    wd_entry=$(crontab -l 2>/dev/null | grep "$cron_marker_wd" || true)
    if [[ -n "$wd_entry" ]]; then
        echo "Watchdog    : enabled (every 5 min)"
    else
        echo "Watchdog    : disabled"
    fi

    local pid_file="/tmp/mini-bowling-serial.pid"
    if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        echo "Serial log  : running (pid $(cat "$pid_file"))"
    else
        echo "Serial log  : not running"
    fi

    # Item 5: show last deploy result
    if [[ -f "$DEPLOY_STATUS_FILE" ]]; then
        local started finished result
        started=$(sed -n '1p' "$DEPLOY_STATUS_FILE")
        finished=$(sed -n '2p' "$DEPLOY_STATUS_FILE")
        result=$(sed -n '3p' "$DEPLOY_STATUS_FILE")
        if [[ "$result" == "OK" ]]; then
            echo "Last deploy : ${GREEN}OK${NC} at $finished"
        else
            echo -e "Last deploy : ${RED}FAILED${NC} (started $started)"
        fi
    else
        echo "Last deploy : no record"
    fi
}

extract_folder_version() {
    local ver="$1"
    # Pure bash: strip the last .patch segment (works for x.y.z and x.y)
    echo "${ver%.*}"
}

create_or_update_symlink() {
    local target="$1"
    local symlink="$SYMLINK_PATH"

    local real_target
    real_target=$(realpath -- "$target" 2>/dev/null) || die "Cannot resolve realpath of $target"

    if [[ -L "$symlink" ]] && [[ "$(readlink -f -- "$symlink")" = "$real_target" ]]; then
        echo -e "${GREEN}Symlink already correct:${NC} $symlink"
        return 0
    fi

    [[ -e "$symlink" || -L "$symlink" ]] && rm -f -- "$symlink" && echo -e "${YELLOW}Removed old symlink${NC}"

    ln -sf -- "$real_target" "$symlink" && {
        echo -e "${GREEN}✓ Desktop symlink updated:${NC} $symlink → $target"
    } || echo -e "${YELLOW}Warning:${NC} Could not create symlink (permissions?)"
}

download_scoremore_version() {
    local full_ver="$1"

    # Basic semver-like validation
    [[ "$full_ver" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?(-[a-zA-Z0-9.]+)?$ ]] || die "Version format looks invalid: $full_ver"

    local folder_ver
    folder_ver=$(extract_folder_version "$full_ver")

    local filename="${APP_NAME}-${full_ver}-${ARCH}.${EXTENSION}"
    local url="${BASE_URL}/${folder_ver}/${filename}"

    # Ensure directory exists, then cd into it
    mkdir -p "$SCOREMORE_DIR" || die "Cannot create $SCOREMORE_DIR"
    cd "$SCOREMORE_DIR"       || die "Cannot cd to $SCOREMORE_DIR"

    # Item 2: check available disk space (require at least 300MB free)
    local avail_kb
    avail_kb=$(df -k "$SCOREMORE_DIR" | awk 'NR==2 {print $4}')
    local required_kb=$(( 300 * 1024 ))
    if (( avail_kb < required_kb )); then
        local avail_mb=$(( avail_kb / 1024 ))
        die "Insufficient disk space: ${avail_mb}MB free, 300MB required. Free up space and try again."
    fi

    if [[ -e "$filename" ]]; then
        echo "\"$filename\" exists, removing the file"
        rm -- "$filename"
    fi

    echo -e "${YELLOW}Downloading:${NC} $filename"
    echo "  → $url"

    # Capture curl exit code properly
    local curl_exit=0
    curl --fail --location --progress-bar --continue-at - \
         --output "$filename" "$url" || curl_exit=$?

    if (( curl_exit != 0 )); then
        echo -e "${RED}Download failed${NC} (curl code $curl_exit)"
        [[ $curl_exit -eq 22 ]] && echo -e "${YELLOW}→ Likely 404 — check version${NC}" || true
        return 1
    fi

    echo -e "\n${GREEN}✓ Downloaded:${NC} $filename"
    ls -lh -- "$filename" 2>/dev/null
    chmod +x -- "$filename" && echo -e "${GREEN}→ Made executable${NC}"

    # Item 6: verify file is not empty or truncated
    local file_size
    file_size=$(stat -c%s "$filename" 2>/dev/null || stat -f%z "$filename" 2>/dev/null || echo 0)
    if (( file_size < 1048576 )); then
        die "Downloaded file is suspiciously small (${file_size} bytes) — download may be corrupt"
    fi

    # Show hash for manual verification
    echo "SHA256:"
    command -v sha256sum >/dev/null && sha256sum -- "$filename" || \
    command -v shasum    >/dev/null && shasum -a 256 -- "$filename" || \
        echo "  (no sha256 tool available)"

    kill_scoremore_gracefully
    sleep 5
    create_or_update_symlink "$filename"
    start_scoremore
}

list_available_sketches() {
    require_project_dir

    echo "Scanning for Arduino sketches in:"
    echo "  $PROJECT_DIR"
    echo "----------------------------------------------"

    local count=0
    local found=false

    while IFS= read -r -d '' dir; do
        local sketch_name
        sketch_name=$(basename "$dir")

        # Skip junk folders
        [[ $sketch_name == .* ]] && continue
        [[ $sketch_name =~ ^(build|cache|dist|tmp|node_modules|__.*|libraries|.claude)$ ]] && continue

        # Any .ino file in the folder?
        if find "$dir" -maxdepth 1 -type f -iname "*.ino" -print -quit 2>/dev/null | grep -q .; then
            count=$((count + 1))
            found=true
            local ino_file
            ino_file=$(find "$dir" -maxdepth 1 -type f -iname "*.ino" | head -n 1 2>/dev/null)
            local ino_name="<no .ino found>"
            [[ -n "$ino_file" ]] && ino_name=$(basename "$ino_file")

            printf "  %2d)  %-24s   →  %s\n" "$count" "$sketch_name" "$ino_name"
        fi
    done < <(find . -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

    if ! $found; then
        echo "→ No sketch folders containing .ino files were found."
        echo
        echo "Quick diagnostic commands:"
        echo "  cd \"$PROJECT_DIR\""
        echo "  ls -ld */"
        echo "  find . -maxdepth 2 -iname \"*.ino\""
        echo
        echo "Expected structure example:"
        echo "  Master_Test/Master_Test.ino"
        echo "  Everything/Everything.ino"
        exit 1
    fi

    echo "Found $count sketch folder(s)."
    echo
    echo "Usage:"
    echo "  mini-bowling upload --Everything"
    echo "  mini-bowling upload --Master_Test"
    echo "  mini-bowling upload --YourFolderName"
}

cmd_update() {
    require_project_dir

    # Item 3: warn if repo is dirty before pulling
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo -e "${YELLOW}Warning:${NC} You have local uncommitted changes in $PROJECT_DIR"
        echo "  These will be preserved via stash, but consider committing or discarding them first."
        echo "  Run 'git status' in $PROJECT_DIR to review."
        echo
    fi

    echo "Pulling latest changes..."
    git pull
}

# Args: sketch_dir [kill_app]
cmd_compile_and_upload() {
    local sketch_dir="${1:-Everything}"
    local kill_app="${2:-true}"

    require_project_dir
    require_arduino_cli

    # Verify port and board BEFORE killing ScoreMore — no point killing the app
    # if the Arduino isn't reachable
    local port
    port=$(find_arduino_port) || true
    verify_arduino_port "$port"

    local sketch_path="${PROJECT_DIR}/${sketch_dir}"

    if [[ ! -d "$sketch_path" ]]; then
        echo -e "${YELLOW}Folder not found:${NC} $sketch_dir"
        echo "Run:   mini-bowling upload --list-sketches"
        die "Sketch folder missing: $sketch_dir"
    fi

    if ! find "$sketch_path" -maxdepth 1 -type f -iname "*.ino" -print -quit 2>/dev/null | grep -q .; then
        echo -e "${YELLOW}Warning:${NC} No .ino file found in $sketch_dir — upload may fail"
    fi

    # Item 2: note whether serial logging was active before upload — the upload
    # disconnects the serial port, which kills the background monitor
    local pid_file="/tmp/mini-bowling-serial.pid"
    local serial_was_running=false
    if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        serial_was_running=true
        echo "→ Stopping serial logging before upload..."
        serial_log stop
    fi

    if [[ "$kill_app" == "true" ]]; then
        echo "Terminating ScoreMore before upload..."
        kill_scoremore_gracefully
    else
        echo "Skipping ScoreMore kill (--no-kill)"
    fi

    echo "→ Compiling + uploading: $sketch_dir"
    echo "  Path: $sketch_path"
    echo "  Port: $port"

    local timeout_cmd=""
    command -v timeout >/dev/null 2>&1 && timeout_cmd="timeout 120"

    $timeout_cmd arduino-cli compile --upload \
        --port "$port" \
        --fqbn "$BOARD" \
        "$sketch_path" || {
        local exit_code=$?
        [[ $exit_code -eq 124 ]] && die "arduino-cli timed out after 120s — Arduino may be locked up"
        die "arduino-cli failed (exit $exit_code)"
    }

    # Item 2: restart serial logging if it was running before the upload
    if [[ "${serial_was_running:-false}" == "true" ]]; then
        echo "→ Restarting serial logging..."
        serial_log start || echo -e "${YELLOW}Warning: could not restart serial logging${NC}"
    fi
}

cmd_deploy() {
    local kill_app=true
    local branch=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-kill|-k)   kill_app=false; shift ;;
            --branch=*)     branch="${1#--branch=}"; shift ;;
            --branch)       shift; branch="${1?Missing branch name}"; shift ;;
            *)              break ;;
        esac
    done

    if [[ -z "$branch" ]]; then
        branch="$DEFAULT_GIT_BRANCH"
        echo -e "${GREEN}Deploying from default branch:${NC} $branch"
    else
        echo -e "${YELLOW}Deploying from specified branch:${NC} $branch"
    fi

    # Item 5: write status file on exit (success or failure)
    local deploy_start
    deploy_start=$(date '+%Y-%m-%d %H:%M:%S')
    _write_deploy_status() {
        local result="$1"
        mkdir -p "$LOG_DIR" 2>/dev/null || true
        printf "%s\n%s\n%s\n" "$deploy_start" "$(date '+%Y-%m-%d %H:%M:%S')" "$result" \
            > "$DEPLOY_STATUS_FILE"
    }
    trap '_write_deploy_status "FAILED"' ERR

    if [[ "$branch" == "$DEFAULT_GIT_BRANCH" ]]; then
        echo "→ Checking network connectivity..."
        wait_for_network 60
        echo "→ Pulling latest git changes"
        cmd_update
        echo "→ Uploading Everything sketch"
        cmd_compile_and_upload "Everything" "$kill_app"
    else
        # Temporarily switch to the requested branch, then restore
        with_git_branch "$branch" cmd_compile_and_upload "Everything" "$kill_app"
    fi

    start_scoremore
    trap - ERR
    _write_deploy_status "OK"
}

show_console() {
    require_arduino_cli

    # Item 3: warn if serial-log is already using the port
    local pid_file="/tmp/mini-bowling-serial.pid"
    if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        die "Serial logging is already running (pid $(cat "$pid_file")) and is using the port. Run 'mini-bowling serial-log stop' first."
    fi

    local port
    port=$(find_arduino_port) || die "No Arduino serial port found — is the Arduino connected?"
    arduino-cli monitor --port "$port" --fqbn "$BOARD" || true
}

board_list() {
    require_arduino_cli
    arduino-cli board list
}

ensure_directories() {
    mkdir -p -- "$PROJECT_DIR"   && echo "Project dir OK:  $PROJECT_DIR"
    mkdir -p -- "$SCOREMORE_DIR" && echo "ScoreMore dir OK: $SCOREMORE_DIR"
    mkdir -p -- "$LOG_DIR"       && echo "Log dir OK:      $LOG_DIR"
}

# Item 4: wait for network connectivity before proceeding (used by cron deploy)
wait_for_network() {
    local timeout="${1:-30}"
    local elapsed=0

    echo -n "Waiting for network"
    while ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; do
        if (( elapsed >= timeout )); then
            echo
            die "Network not available after ${timeout}s — aborting"
        fi
        echo -n "."
        sleep 2
        elapsed=$(( elapsed + 2 ))
    done
    echo
    echo -e "${GREEN}→ Network available${NC}"
}

script_version() {
    local script_path
    script_path=$(command -v mini-bowling 2>/dev/null) || script_path=$(realpath "$0")

    echo "mini-bowling version : $SCRIPT_VERSION"
    echo "Script path          : $script_path"
    echo "Last modified        : $(date -r "$script_path" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || stat -c '%y' "$script_path" 2>/dev/null | cut -c1-19)"
    echo "Shell                : $BASH_VERSION"
}

# Item 5: show which ScoreMore version is currently active via the desktop symlink
scoremore_version() {
    if [[ ! -L "$SYMLINK_PATH" ]]; then
        echo "No ScoreMore symlink found at $SYMLINK_PATH"
        return 0
    fi

    local target
    target=$(readlink -f -- "$SYMLINK_PATH" 2>/dev/null) || die "Cannot resolve symlink"

    local filename
    filename=$(basename "$target")

    # Extract version from filename: ScoreMore-1.8.0-arm64.AppImage
    local version
    version=$(echo "$filename" | sed -n 's/^ScoreMore-\(.*\)-arm64\.AppImage$/\1/p')

    echo "ScoreMore version : ${version:-unknown}"
    echo "AppImage path     : $target"

    if [[ -f "$target" ]]; then
        echo "File size         : $(du -h "$target" | cut -f1)"
        echo "Last modified     : $(date -r "$target" '+%Y-%m-%d %H:%M:%S')"
    else
        echo -e "${RED}Warning:${NC} symlink target does not exist: $target"
    fi
}

# Item 7: backup key config files to a timestamped archive
backup_config() {
    local backup_dir="$HOME/Documents/Bowling/backups"
    local timestamp
    timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
    local archive="$backup_dir/mini-bowling-backup-${timestamp}.tar.gz"

    mkdir -p "$backup_dir" || die "Cannot create backup directory: $backup_dir"

    echo "Creating backup: $archive"

    local items=()
    [[ -d "$PROJECT_DIR" ]]            && items+=("$PROJECT_DIR")
    [[ -d "$HOME/.config/ScoreMore" ]] && items+=("$HOME/.config/ScoreMore")
    [[ -f "$SYMLINK_PATH" ]]           && items+=("$(readlink -f "$SYMLINK_PATH")")

    # Item 4: include the script itself so it survives an SD card failure
    local script_path
    script_path=$(command -v mini-bowling 2>/dev/null) || script_path=$(realpath "$0")
    [[ -f "$script_path" ]] && items+=("$script_path")

    if [[ ${#items[@]} -eq 0 ]]; then
        die "Nothing to back up — no project dir or ScoreMore config found"
    fi

    tar -czf "$archive" --ignore-failed-read "${items[@]}" 2>/dev/null || \
        die "Backup failed"

    echo -e "${GREEN}✓ Backup created:${NC} $archive"
    echo "  Size: $(du -h "$archive" | cut -f1)"

    # Keep only the last 10 backups
    local old_backups
    mapfile -t old_backups < <(find "$backup_dir" -name "mini-bowling-backup-*.tar.gz" \
                                    2>/dev/null | sort -r | tail -n +11)
    for f in "${old_backups[@]}"; do
        rm -f -- "$f" && echo "→ Removed old backup: $(basename "$f")"
    done
}

# Item 10: doctor — check all required dependencies are present
doctor() {
    echo "=== Dependency Check ==="
    echo

    local all_ok=true
    local deps=(git curl arduino-cli pgrep pkill nohup realpath tee awk df find)

    for dep in "${deps[@]}"; do
        if command -v "$dep" >/dev/null 2>&1; then
            printf "  ${GREEN}✓${NC}  %-20s %s\n" "$dep" "$(command -v "$dep")"
        else
            printf "  ${RED}✗${NC}  %-20s NOT FOUND\n" "$dep"
            all_ok=false
        fi
    done

    echo
    # Optional but useful
    local optional=(iwconfig iw sha256sum shasum)
    echo "Optional:"
    for dep in "${optional[@]}"; do
        if command -v "$dep" >/dev/null 2>&1; then
            printf "  ${GREEN}✓${NC}  %-20s %s\n" "$dep" "$(command -v "$dep")"
        else
            printf "  ${YELLOW}-${NC}  %-20s not found (non-critical)\n" "$dep"
        fi
    done

    echo
    # Directory checks
    echo "Directories:"
    for dir in "$PROJECT_DIR" "$SCOREMORE_DIR" "$LOG_DIR"; do
        if [[ -d "$dir" ]]; then
            printf "  ${GREEN}✓${NC}  %s\n" "$dir"
        else
            printf "  ${YELLOW}-${NC}  %s  (not created yet — run: mini-bowling create-dir)\n" "$dir"
        fi
    done

    echo
    if $all_ok; then
        echo -e "${GREEN}✓ All required dependencies found${NC}"
    else
        echo -e "${RED}✗ Some required dependencies are missing — install them and re-run doctor${NC}"
        return 1
    fi
}

# Item 1: pre-flight check — verify all conditions before a deploy
preflight() {
    echo "=== Pre-flight Check ==="
    echo

    local all_ok=true

    # 1. arduino-cli installed
    if command -v arduino-cli >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC}  arduino-cli installed"
    else
        echo -e "  ${RED}✗${NC}  arduino-cli not found — run: mini-bowling install-cli"
        all_ok=false
    fi

    # 2. Arduino port reachable
    local port
    port=$(find_arduino_port) || true
    if [[ -n "$port" ]]; then
        echo -e "  ${GREEN}✓${NC}  Arduino port found: $port"
        # Also check arduino-cli recognises it
        if arduino-cli board list 2>/dev/null | grep -q "$port"; then
            echo -e "  ${GREEN}✓${NC}  Arduino recognised by arduino-cli"
        else
            echo -e "  ${YELLOW}!${NC}  Arduino port exists but not recognised by arduino-cli"
            all_ok=false
        fi
    else
        echo -e "  ${RED}✗${NC}  No Arduino serial port found"
        all_ok=false
    fi

    # 3. Internet reachable
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC}  Internet reachable"
    else
        echo -e "  ${RED}✗${NC}  No internet connection"
        all_ok=false
    fi

    # 4. Disk space (require 500MB free)
    local avail_kb
    avail_kb=$(df -k "$HOME" | awk 'NR==2 {print $4}')
    local avail_mb=$(( avail_kb / 1024 ))
    if (( avail_kb >= 512000 )); then
        echo -e "  ${GREEN}✓${NC}  Disk space: ${avail_mb}MB free"
    else
        echo -e "  ${RED}✗${NC}  Low disk space: ${avail_mb}MB free (500MB recommended)"
        all_ok=false
    fi

    # 5. CPU temperature
    if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
        local raw_temp temp_c
        raw_temp=$(cat /sys/class/thermal/thermal_zone0/temp)
        temp_c=$(( raw_temp / 1000 ))
        if (( temp_c >= 80 )); then
            echo -e "  ${RED}✗${NC}  CPU temperature critical: ${temp_c}°C (throttling likely)"
            all_ok=false
        elif (( temp_c >= 70 )); then
            echo -e "  ${YELLOW}!${NC}  CPU temperature warm: ${temp_c}°C"
        else
            echo -e "  ${GREEN}✓${NC}  CPU temperature: ${temp_c}°C"
        fi
    fi

    # 6. Git repo clean
    if [[ -d "$PROJECT_DIR/.git" ]]; then
        if git -C "$PROJECT_DIR" diff --quiet && git -C "$PROJECT_DIR" diff --cached --quiet; then
            echo -e "  ${GREEN}✓${NC}  Git repo clean"
        else
            echo -e "  ${YELLOW}!${NC}  Git repo has uncommitted local changes"
        fi
    else
        echo -e "  ${YELLOW}!${NC}  Project directory is not a git repo: $PROJECT_DIR"
    fi

    # 7. ScoreMore symlink valid
    if [[ -L "$SYMLINK_PATH" ]] && [[ -f "$SYMLINK_PATH" ]]; then
        echo -e "  ${GREEN}✓${NC}  ScoreMore symlink valid: $SYMLINK_PATH"
    elif [[ -L "$SYMLINK_PATH" ]]; then
        echo -e "  ${YELLOW}!${NC}  ScoreMore symlink is broken: $SYMLINK_PATH"
    else
        echo -e "  ${YELLOW}!${NC}  No ScoreMore symlink at $SYMLINK_PATH — run: mini-bowling download <version>"
    fi

    # 8. Remote git update check
    if [[ -d "$PROJECT_DIR/.git" ]] && ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        git -C "$PROJECT_DIR" fetch --quiet origin "$DEFAULT_GIT_BRANCH" 2>/dev/null || true
        local behind
        behind=$(git -C "$PROJECT_DIR" rev-list HEAD..origin/"$DEFAULT_GIT_BRANCH" --count 2>/dev/null || echo 0)
        if [[ "$behind" -gt 0 ]]; then
            echo -e "  ${YELLOW}!${NC}  $behind new commit(s) available on remote — run: mini-bowling deploy"
        else
            echo -e "  ${GREEN}✓${NC}  Git repo up to date with remote"
        fi
    fi

    # 9. ScoreMore update check
    local sm_latest
    sm_latest=$(curl --silent --fail --max-time 5 "https://www.scoremorebowling.com/download" 2>/dev/null | \
        grep -oP "ScoreMore-\K[0-9]+\.[0-9]+(\.[0-9]+)?(?=-${ARCH}\.${EXTENSION})" | head -1 || true)
    if [[ -z "$sm_latest" ]]; then
        sm_latest=$(curl --silent --fail --max-time 5 "https://www.scoremorebowling.com/download" 2>/dev/null | \
            grep -oP "ScoreMore \K[0-9]+\.[0-9]+(\.[0-9]+)?(?=,? Latest)" | head -1 || true)
    fi
    if [[ -n "$sm_latest" ]] && [[ -L "$SYMLINK_PATH" ]]; then
        local sm_installed
        sm_installed=$(basename "$(readlink -f "$SYMLINK_PATH" 2>/dev/null)" | \
            sed -n "s/^ScoreMore-\\(.*\\)-${ARCH}\\.${EXTENSION}$/\\1/p")
        if [[ "$sm_latest" == "$sm_installed" ]]; then
            echo -e "  ${GREEN}✓${NC}  ScoreMore up to date ($sm_installed)"
        else
            echo -e "  ${YELLOW}!${NC}  ScoreMore update available: $sm_installed → $sm_latest — run: mini-bowling download $sm_latest"
        fi
    elif [[ -n "$sm_latest" ]]; then
        echo -e "  ${YELLOW}!${NC}  ScoreMore latest: $sm_latest — run: mini-bowling download $sm_latest"
    fi

    echo
    if $all_ok; then
        echo -e "${GREEN}✓ All checks passed — ready to deploy${NC}"
    else
        echo -e "${RED}✗ Some checks failed — review above before deploying${NC}"
        return 1
    fi
}

# Item 9: guided first-time setup
install_setup() {
    echo "=== mini-bowling First-Time Setup ==="
    echo "This will run through the initial setup steps for a fresh Raspberry Pi."
    echo

    # Step 1: create directories
    echo "Step 1/5: Creating required directories..."
    ensure_directories
    echo

    # Step 2: install arduino-cli
    echo "Step 2/5: Checking arduino-cli..."
    install_cli
    echo

    # Step 3: autostart
    echo "Step 3/5: Configuring ScoreMore autostart..."
    setup_autostart
    echo

    # Step 4: doctor check
    echo "Step 4/6: Checking dependencies..."
    doctor
    echo

    # Step 5: watchdog
    echo "Step 5/6: Enable ScoreMore watchdog? (restarts ScoreMore every 5 min if it crashes)"
    echo -n "  Enable watchdog? [Y/n]: "
    read -r wd_answer
    if [[ "${wd_answer,,}" != "n" ]]; then
        setup_watchdog enable
    else
        echo "  Skipped — run 'mini-bowling setup-watchdog enable' at any time."
    fi
    echo

    # Step 6: schedule
    echo "Step 6/6: Schedule daily deploy (optional)"
    echo -n "  Enter a daily deploy time in HH:MM format, or press Enter to skip: "
    read -r sched_time
    if [[ -n "$sched_time" ]]; then
        schedule_deploy "$sched_time"
    else
        echo "  Skipped — run 'mini-bowling schedule-deploy HH:MM' at any time."
    fi

    echo
    echo -e "${GREEN}✓ Setup complete.${NC}"
    echo
    echo "Next steps:"
    echo "  1. Connect the Arduino and run:  mini-bowling list"
    echo "  2. Update DEFAULT_PORT and BOARD in the script if needed"
    echo "  3. Run a pre-flight check:       mini-bowling preflight"
    echo "  4. Run your first deploy:        mini-bowling deploy"
}

setup_autostart() {
    local autostart_dir="$HOME/.config/autostart"
    local desktop_file="$autostart_dir/scoremore.desktop"

    mkdir -p "$autostart_dir" || die "Cannot create $autostart_dir"

    if [[ -f "$desktop_file" ]]; then
        echo -e "${YELLOW}Autostart file already exists — overwriting:${NC} $desktop_file"
    fi

    cat > "$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=ScoreMore
Exec="$HOME/Desktop/ScoreMore.AppImage"
Terminal=false
EOF

    echo -e "${GREEN}✓ Autostart configured:${NC} $desktop_file"
}

remove_autostart() {
    local desktop_file="$HOME/.config/autostart/scoremore.desktop"

    if [[ ! -f "$desktop_file" ]]; then
        echo "Autostart file not found — nothing to remove: $desktop_file"
        return 0
    fi

    rm -- "$desktop_file" && echo -e "${GREEN}✓ Autostart removed:${NC} $desktop_file" \
        || die "Failed to remove $desktop_file"
}

schedule_deploy() {
    local time="${1?Missing time argument — usage: mini-bowling schedule-deploy HH:MM}"

    # Validate HH:MM format
    [[ "$time" =~ ^([01][0-9]|2[0-3]):([0-5][0-9])$ ]] || \
        die "Invalid time format: '$time' — expected HH:MM (e.g. 02:30, 14:00)"

    local hour="${time%%:*}"
    local minute="${time##*:}"
    local script_path
    script_path=$(command -v mini-bowling 2>/dev/null) || script_path="$0"
    script_path=$(realpath -- "$script_path")

    local cron_marker="# mini-bowling scheduled deploy"
    local cron_job="$minute $hour * * * $script_path deploy $cron_marker"

    # Remove any existing scheduled deploy entry, then add the new one
    local existing
    existing=$(crontab -l 2>/dev/null || true)

    local filtered
    filtered=$(echo "$existing" | grep -v "$cron_marker" || true)

    # Write updated crontab
    {
        [[ -n "$filtered" ]] && echo "$filtered"
        echo "$cron_job"
    } | crontab - || die "Failed to update crontab"

    echo -e "${GREEN}✓ Scheduled deploy set:${NC} every day at ${time}"
    echo "  Cron entry: $cron_job"
    echo
    echo "Run 'mini-bowling unschedule-deploy' to remove."
}

unschedule_deploy() {
    local cron_marker="# mini-bowling scheduled deploy"

    local existing
    existing=$(crontab -l 2>/dev/null || true)

    if ! echo "$existing" | grep -q "$cron_marker"; then
        echo "No scheduled deploy found — nothing to remove."
        return 0
    fi

    echo "$existing" | grep -v "$cron_marker" | crontab - || die "Failed to update crontab"
    echo -e "${GREEN}✓ Scheduled deploy removed.${NC}"
}

# ------------------------------------------------
#  Arduino / Deploy Management
# ------------------------------------------------

# Item 1: rollback to previous git commit and re-upload
cmd_rollback() {
    require_project_dir
    require_arduino_cli

    local steps="${1:-1}"
    [[ "$steps" =~ ^[0-9]+$ ]] || die "Invalid step count: '$steps' — must be a number"

    echo "Current commit:"
    git -C "$PROJECT_DIR" log --oneline -1
    echo

    # Item 4: confirmation prompt — rollback resets git history
    echo -e "${YELLOW}Warning:${NC} This will reset $steps git commit(s) with 'git reset --hard'."
    echo "This cannot be undone unless you have the commit hashes."
    local countdown=5
    echo -n "Press Ctrl+C to cancel, or wait $countdown seconds to continue"
    while [[ $countdown -gt 0 ]]; do
        sleep 1
        countdown=$(( countdown - 1 ))
        echo -n "."
    done
    echo
    echo

    echo -e "${YELLOW}Rolling back $steps commit(s)...${NC}"
    git -C "$PROJECT_DIR" reset --hard "HEAD~${steps}" || die "git reset failed"

    echo "Now at:"
    git -C "$PROJECT_DIR" log --oneline -1
    echo

    # Verify port before killing ScoreMore
    local port
    port=$(find_arduino_port) || true
    verify_arduino_port "$port"

    echo "Terminating ScoreMore before upload..."
    kill_scoremore_gracefully

    echo "→ Compiling + uploading Everything sketch..."
    local timeout_cmd=""
    command -v timeout >/dev/null 2>&1 && timeout_cmd="timeout 120"

    $timeout_cmd arduino-cli compile --upload \
        --port "$port" \
        --fqbn "$BOARD" \
        "${PROJECT_DIR}/Everything" || {
        local exit_code=$?
        [[ $exit_code -eq 124 ]] && die "arduino-cli timed out after 120s — Arduino may be locked up"
        die "arduino-cli failed (exit $exit_code)"
    }

    start_scoremore
}

check_scoremore_update() {
    echo "Checking ScoreMore latest version from scoremorebowling.com..."

    # Fetch the download page and extract the latest version from the
    # download link for the Raspberry Pi AppImage, e.g.:
    # ScoreMore-1.8.2-arm64.AppImage
    local page
    page=$(curl --silent --fail --max-time 10 \
        "https://www.scoremorebowling.com/download") || \
        die "Could not reach scoremorebowling.com — is the network available?"

    local latest
    latest=$(echo "$page" | grep -oP "ScoreMore-\K[0-9]+\.[0-9]+(\.[0-9]+)?(?=-${ARCH}\.${EXTENSION})" | head -1 || true)

    # Fallback: parse the heading "ScoreMore X.Y, Latest Version"
    if [[ -z "$latest" ]]; then
        latest=$(echo "$page" | grep -oP "ScoreMore \K[0-9]+\.[0-9]+(\.[0-9]+)?(?=,? Latest)" | head -1 || true)
    fi

    if [[ -z "$latest" ]]; then
        die "Could not parse latest version from download page — page layout may have changed"
    fi

    echo "Latest available : $latest"

    # Get currently installed version from symlink filename
    local installed=""
    if [[ -L "$SYMLINK_PATH" ]]; then
        local target
        target=$(readlink -f "$SYMLINK_PATH" 2>/dev/null || true)
        installed=$(basename "$target" | sed -n "s/^ScoreMore-\\(.*\\)-${ARCH}\\.${EXTENSION}$/\\1/p")
    fi

    if [[ -z "$installed" ]]; then
        echo "Installed        : none"
        echo
        echo "Run: mini-bowling download $latest"
        return 0
    fi

    echo "Installed        : $installed"

    if [[ "$latest" == "$installed" ]]; then
        echo -e "${GREEN}✓ ScoreMore is up to date${NC}"
    else
        echo -e "${YELLOW}→ Update available:${NC} $installed → $latest"
        echo
        echo "Run: mini-bowling download $latest"
    fi
}

# Item 3: check if remote has new commits without pulling
check_update() {
    require_project_dir

    echo "Checking for updates on ${DEFAULT_GIT_BRANCH}..."
    git -C "$PROJECT_DIR" fetch --quiet origin "$DEFAULT_GIT_BRANCH" 2>/dev/null || \
        die "git fetch failed — is the network available?"

    local local_ref remote_ref
    local_ref=$(git -C "$PROJECT_DIR" rev-parse HEAD)
    remote_ref=$(git -C "$PROJECT_DIR" rev-parse "origin/${DEFAULT_GIT_BRANCH}")

    echo "Local  : $(git -C "$PROJECT_DIR" log --oneline -1 HEAD)"

    if [[ "$local_ref" == "$remote_ref" ]]; then
        echo -e "${GREEN}✓ Already up to date${NC}"
        return 0
    fi

    local count
    count=$(git -C "$PROJECT_DIR" rev-list HEAD..origin/"$DEFAULT_GIT_BRANCH" --count)
    echo "Remote : $count new commit(s) available:"
    git -C "$PROJECT_DIR" log --oneline HEAD..origin/"$DEFAULT_GIT_BRANCH"
    echo
    echo "Run 'mini-bowling deploy' to apply."
}

# Item 5: list available ScoreMore versions and manage old ones
scoremore_history() {
    local subcmd="${1:-list}"
    shift 2>/dev/null || true

    case "$subcmd" in
        list)
            if [[ ! -d "$SCOREMORE_DIR" ]]; then
                echo "ScoreMore directory not found: $SCOREMORE_DIR"
                return 0
            fi

            local files
            mapfile -t files < <(find "$SCOREMORE_DIR" -maxdepth 1 \
                -name "ScoreMore-*.AppImage" 2>/dev/null | sort -V -r)

            if [[ ${#files[@]} -eq 0 ]]; then
                echo "No ScoreMore AppImages found in $SCOREMORE_DIR"
                return 0
            fi

            local active
            active=$(readlink -f "$SYMLINK_PATH" 2>/dev/null || true)

            echo "ScoreMore AppImages (newest first):"
            for f in "${files[@]}"; do
                local size date_str active_marker
                size=$(du -h "$f" | cut -f1)
                date_str=$(date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null || stat -c '%y' "$f" 2>/dev/null | cut -c1-16)
                active_marker=""
                if [[ "$f" == "$active" ]]; then
                    active_marker=" ${GREEN}← active${NC}"
                fi
                printf "  %-50s %6s  %s" "$(basename "$f")" "$size" "$date_str"
                echo -e "$active_marker"
            done
            echo
            echo "Run 'mini-bowling scoremore-history use <version>' to switch versions."
            echo "Run 'mini-bowling scoremore-history clean' to remove all but the active version."
            ;;

        use)
            local ver="${1?Missing version — e.g. mini-bowling scoremore-history use 1.8.0}"
            local filename="${APP_NAME}-${ver}-${ARCH}.${EXTENSION}"
            local target="$SCOREMORE_DIR/$filename"

            [[ -f "$target" ]] || die "Version not found: $target"

            kill_scoremore_gracefully
            sleep 2
            create_or_update_symlink "$target"
            start_scoremore
            ;;

        clean)
            local active
            active=$(readlink -f "$SYMLINK_PATH" 2>/dev/null || true)
            [[ -z "$active" ]] && die "No active symlink found — cannot determine which version to keep"

            local removed=0
            while IFS= read -r -d '' f; do
                if [[ "$f" != "$active" ]]; then
                    rm -f -- "$f"
                    echo "→ Removed: $(basename "$f")"
                    removed=$((removed + 1))
                fi
            done < <(find "$SCOREMORE_DIR" -maxdepth 1 -name "ScoreMore-*.AppImage" -print0 2>/dev/null)

            if [[ $removed -eq 0 ]]; then
                echo "Nothing to remove — only the active version is present."
            else
                echo -e "${GREEN}✓ Removed $removed old version(s)${NC}"
            fi
            ;;

        *)
            die "Unknown subcommand: '$subcmd' — use list, use <version>, or clean"
            ;;
    esac
}

# Item 5: rollback ScoreMore to a previously downloaded version
rollback_scoremore() {
    if [[ ! -d "$SCOREMORE_DIR" ]]; then
        die "ScoreMore directory not found: $SCOREMORE_DIR"
    fi

    local active
    active=$(readlink -f "$SYMLINK_PATH" 2>/dev/null || true)

    # List versions sorted newest-first, excluding the active one
    local files
    mapfile -t files < <(find "$SCOREMORE_DIR" -maxdepth 1 \
        -name "ScoreMore-*.AppImage" 2>/dev/null | sort -V -r)

    local previous=""
    for f in "${files[@]}"; do
        if [[ "$f" != "$active" ]]; then
            previous="$f"
            break
        fi
    done

    if [[ -z "$previous" ]]; then
        echo "No previous ScoreMore version available to roll back to."
        echo "Run 'mini-bowling scoremore-history list' to see available versions."
        return 1
    fi

    echo "Current  : $(basename "$active")"
    echo "Roll back to: $(basename "$previous")"
    echo
    kill_scoremore_gracefully
    sleep 2
    create_or_update_symlink "$previous"
    start_scoremore
    echo -e "${GREEN}✓ Rolled back to $(basename "$previous")${NC}"
}

# Item 6: capture Arduino serial output to a log file in the background
serial_log() {
    local subcmd="${1:-start}"
    shift 2>/dev/null || true

    local serial_log_file="$LOG_DIR/arduino-serial-$(date '+%Y-%m-%d').log"
    local pid_file="/tmp/mini-bowling-serial.pid"

    case "$subcmd" in
        start)
            require_arduino_cli

            if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
                echo "Serial logging already running (pid $(cat "$pid_file"))"
                echo "Log file: $serial_log_file"
                return 0
            fi

            local port
            port=$(find_arduino_port) || die "No Arduino port found"

            echo "Starting serial logging on $port..."
            echo "Log file: $serial_log_file"

            arduino-cli monitor --port "$port" --fqbn "$BOARD" \
                >> "$serial_log_file" 2>&1 &
            local bg_pid=$!
            disown
            echo $bg_pid > "$pid_file"

            sleep 1
            if kill -0 "$bg_pid" 2>/dev/null; then
                echo -e "${GREEN}✓ Serial logging started (pid $bg_pid)${NC}"
            else
                rm -f "$pid_file"
                die "Serial monitor failed to start — is the Arduino connected?"
            fi
            ;;

        stop)
            if [[ ! -f "$pid_file" ]]; then
                echo "Serial logging is not running."
                return 0
            fi

            local pid
            pid=$(cat "$pid_file")
            kill "$pid" 2>/dev/null || true
            rm -f "$pid_file"
            echo -e "${GREEN}✓ Serial logging stopped${NC}"
            ;;

        status)
            if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
                echo -e "Serial logging : ${GREEN}running${NC} (pid $(cat "$pid_file"))"
                echo "Log file       : $serial_log_file"
            else
                echo "Serial logging : not running"
                rm -f "$pid_file" 2>/dev/null || true
            fi
            ;;

        tail)
            [[ -f "$serial_log_file" ]] || die "No serial log for today: $serial_log_file"
            tail -f "$serial_log_file"
            ;;

        *)
            die "Unknown subcommand: '$subcmd' — use start, stop, status, or tail"
            ;;
    esac
}

# Item 2 / 7: check if ScoreMore is running and restart if not
watchdog() {
    local sm_pid
    sm_pid=$(pgrep -f "ScoreMore.AppImage" 2>/dev/null | head -1 || true)

    if [[ -n "$sm_pid" ]]; then
        echo -e "${GREEN}✓ ScoreMore is running (pid $sm_pid)${NC}"
    else
        echo -e "${YELLOW}ScoreMore is not running — restarting...${NC}"
        start_scoremore
        sleep 3

        sm_pid=$(pgrep -f "ScoreMore.AppImage" 2>/dev/null | head -1 || true)
        if [[ -n "$sm_pid" ]]; then
            echo -e "${GREEN}✓ ScoreMore restarted (pid $sm_pid)${NC}"
        else
            die "ScoreMore failed to start"
        fi
    fi

    # Item 1: restart serial logging if it was supposed to be running but died
    local pid_file="/tmp/mini-bowling-serial.pid"
    if [[ -f "$pid_file" ]]; then
        local serial_pid
        serial_pid=$(cat "$pid_file")
        if ! kill -0 "$serial_pid" 2>/dev/null; then
            echo -e "${YELLOW}Serial logging was running but has stopped — restarting...${NC}"
            rm -f "$pid_file"
            serial_log start || echo -e "${YELLOW}Warning: could not restart serial logging${NC}"
        fi
    fi
}

# Item 7: add/remove cron job for automatic watchdog
setup_watchdog() {
    local subcmd="${1:-enable}"
    local cron_marker="# mini-bowling watchdog"
    local script_path
    script_path=$(command -v mini-bowling 2>/dev/null) || script_path=$(realpath "$0")

    case "$subcmd" in
        enable)
            local existing
            existing=$(crontab -l 2>/dev/null || true)

            if echo "$existing" | grep -q "$cron_marker"; then
                echo "Watchdog cron job already enabled."
                return 0
            fi

            local cron_job="*/5 * * * * $script_path watchdog $cron_marker"
            {
                [[ -n "$existing" ]] && echo "$existing"
                echo "$cron_job"
            } | crontab - || die "Failed to update crontab"
            echo -e "${GREEN}✓ Watchdog enabled:${NC} checks ScoreMore every 5 minutes"
            ;;

        disable)
            local existing
            existing=$(crontab -l 2>/dev/null || true)

            if ! echo "$existing" | grep -q "$cron_marker"; then
                echo "Watchdog cron job not found — nothing to remove."
                return 0
            fi

            echo "$existing" | grep -v "$cron_marker" | crontab - || die "Failed to update crontab"
            echo -e "${GREEN}✓ Watchdog disabled${NC}"
            ;;

        status)
            local entry
            entry=$(crontab -l 2>/dev/null | grep "$cron_marker" || true)
            if [[ -n "$entry" ]]; then
                echo -e "Watchdog : ${GREEN}enabled${NC} (every 5 minutes)"
            else
                echo "Watchdog : disabled"
            fi
            ;;

        *)
            die "Unknown subcommand: '$subcmd' — use enable, disable, or status"
            ;;
    esac
}

# Item 10: clean up old ScoreMore AppImages and Arduino build cache
disk_cleanup() {
    echo "=== Disk Cleanup ==="
    echo

    local freed=0

    # Remove all but the active ScoreMore AppImage
    if [[ -d "$SCOREMORE_DIR" ]]; then
        local active
        active=$(readlink -f "$SYMLINK_PATH" 2>/dev/null || true)
        local sm_removed=0

        while IFS= read -r -d '' f; do
            if [[ "$f" != "$active" ]]; then
                local size_kb
                size_kb=$(du -k "$f" | cut -f1)
                rm -f -- "$f"
                echo "→ Removed old AppImage: $(basename "$f") ($(( size_kb / 1024 ))MB)"
                freed=$(( freed + size_kb ))
                sm_removed=$(( sm_removed + 1 ))
            fi
        done < <(find "$SCOREMORE_DIR" -maxdepth 1 -name "ScoreMore-*.AppImage" -print0 2>/dev/null)

        if [[ $sm_removed -eq 0 ]]; then
            echo "  ScoreMore: nothing to remove (only active version present)"
        fi
    fi

    # Remove Arduino build cache
    local build_dirs=("$PROJECT_DIR/build" "$HOME/.cache/arduino" "$HOME/.arduino15/cache")
    for dir in "${build_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local size_kb
            size_kb=$(du -sk "$dir" 2>/dev/null | cut -f1)
            rm -rf -- "$dir"
            echo "→ Removed build cache: $dir ($(( size_kb / 1024 ))MB)"
            freed=$(( freed + size_kb ))
        fi
    done

    # Remove old log files beyond 30 days (in case prune_logs missed any)
    local log_removed=0
    while IFS= read -r -d '' f; do
        local size_kb
        size_kb=$(du -k "$f" | cut -f1)
        rm -f -- "$f"
        freed=$(( freed + size_kb ))
        log_removed=$(( log_removed + 1 ))
    done < <(find "$LOG_DIR" -maxdepth 1 -name "mini-bowling-*.log" -mtime +30 -print0 2>/dev/null)
    [[ $log_removed -gt 0 ]] && echo "→ Removed $log_removed old log file(s)" || true

    # Report backup directory size — backups are not auto-removed here,
    # only the 10-backup limit enforced by `backup` applies
    local backup_dir="$HOME/Documents/Bowling/backups"
    if [[ -d "$backup_dir" ]]; then
        local backup_count backup_size_kb
        backup_count=$(find "$backup_dir" -maxdepth 1 -name "mini-bowling-backup-*.tar.gz" 2>/dev/null | wc -l)
        backup_size_kb=$(du -sk "$backup_dir" 2>/dev/null | cut -f1)
        echo "  Backups: $backup_count file(s), $(( backup_size_kb / 1024 ))MB total"
        echo "  (run 'mini-bowling backup' to apply the 10-backup retention limit)"
    fi

    echo
    if [[ $freed -gt 0 ]]; then
        echo -e "${GREEN}✓ Freed approximately $(( freed / 1024 ))MB${NC}"
    else
        echo -e "${GREEN}✓ Nothing to clean up${NC}"
    fi

    echo
    echo "Current disk usage:"
    df -h / "$HOME" 2>/dev/null | awk 'NR==1 || NR>1 {printf "  %s\n", $0}'
}

# ------------------------------------------------
#  Raspberry Pi Management
# ------------------------------------------------

pi_status() {
    echo "=== Raspberry Pi Status ==="
    echo

    # Uptime
    echo "Uptime      : $(uptime -p 2>/dev/null || uptime)"

    # CPU temperature
    if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
        local raw_temp
        raw_temp=$(cat /sys/class/thermal/thermal_zone0/temp)
        local temp_c=$(( raw_temp / 1000 ))
        local temp_f=$(( temp_c * 9 / 5 + 32 ))
        if (( temp_c >= 80 )); then
            echo -e "CPU Temp    : ${RED}${temp_c}°C / ${temp_f}°F (CRITICAL — throttling likely)${NC}"
        elif (( temp_c >= 70 )); then
            echo -e "CPU Temp    : ${YELLOW}${temp_c}°C / ${temp_f}°F (warm)${NC}"
        else
            echo -e "CPU Temp    : ${GREEN}${temp_c}°C / ${temp_f}°F${NC}"
        fi
    else
        echo "CPU Temp    : unavailable"
    fi

    # Memory
    local mem_total mem_used mem_free mem_pct
    mem_total=$(awk '/MemTotal/  {print $2}' /proc/meminfo)
    mem_free=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
    mem_used=$(( mem_total - mem_free ))
    mem_pct=$(( mem_used * 100 / mem_total ))
    printf "Memory      : %s MB used / %s MB total (%s%%)\n" \
        "$(( mem_used / 1024 ))" "$(( mem_total / 1024 ))" "$mem_pct"

    # Disk space
    echo
    echo "Disk Usage:"
    df -h / "$HOME" 2>/dev/null | awk 'NR==1 || NR>1 {printf "  %-20s %s\n", $6, $0}' | \
        grep -v "^  Mounted" || df -h /
}

pi_update() {
    echo -e "${YELLOW}Updating Raspberry Pi OS packages...${NC}"
    sudo apt-get update || die "apt update failed"
    sudo apt-get upgrade -y || die "apt upgrade failed"
    echo -e "${GREEN}✓ System packages up to date${NC}"

    if [[ -f /var/run/reboot-required ]]; then
        echo -e "${YELLOW}→ A reboot is required to apply updates.${NC}"
        echo "  Run: mini-bowling pi-reboot"
    fi
}

pi_reboot() {
    echo -e "${YELLOW}Rebooting Raspberry Pi in 5 seconds... (Ctrl+C to cancel)${NC}"
    sleep 5
    sudo reboot
}

pi_shutdown() {
    echo -e "${YELLOW}Shutting down Raspberry Pi in 5 seconds... (Ctrl+C to cancel)${NC}"
    sleep 5
    sudo shutdown -h now
}

wifi_status() {
    echo "=== Wi-Fi Status ==="
    echo

    # Interface detection
    local iface
    iface=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}') || iface=""

    if [[ -z "$iface" ]]; then
        echo -e "Network     : ${RED}No route to internet${NC}"
        return 0
    fi

    echo "Interface   : $iface"

    # IP address
    local ip
    ip=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet / {print $2}' | head -1)
    echo "IP Address  : ${ip:-unknown}"

    # SSID and signal (requires iwconfig or iw)
    if command -v iwconfig >/dev/null 2>&1; then
        local ssid signal
        ssid=$(iwconfig "$iface" 2>/dev/null | awk -F'"' '/ESSID/ {print $2}')
        signal=$(iwconfig "$iface" 2>/dev/null | grep -oP 'Signal level=\K[^ ]+' 2>/dev/null || \
                 iwconfig "$iface" 2>/dev/null | sed -n 's/.*Signal level=\([^ ]*\).*/\1/p')
        [[ -n "$ssid"   ]] && echo "SSID        : $ssid"
        [[ -n "$signal" ]] && echo "Signal      : $signal dBm"
    elif command -v iw >/dev/null 2>&1; then
        local ssid
        ssid=$(iw dev "$iface" link 2>/dev/null | awk '/SSID/ {print $2}')
        [[ -n "$ssid" ]] && echo "SSID        : $ssid"
    fi

    # Internet reachability
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        echo -e "Internet    : ${GREEN}reachable${NC}"
    else
        echo -e "Internet    : ${RED}unreachable${NC}"
    fi
}

install_cli() {
    if command -v arduino-cli >/dev/null 2>&1; then
        echo -e "${GREEN}arduino-cli is already installed:${NC} $(arduino-cli version --log-format short)"
        return 0
    fi

    echo -e "${YELLOW}arduino-cli not found. Installing...${NC}"

    local install_dir="${HOME}/.local/bin"
    mkdir -p "$install_dir"

    echo "→ Installing arduino-cli to: $install_dir"

    local install_exit=0
    curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh \
        | BINDIR="$install_dir" sh -s -- --no-interaction || install_exit=$?

    if (( install_exit != 0 )); then
        echo -e "${RED}Installation failed.${NC}"
        echo "You can try manually with:"
        echo "  curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | sh"
        return 1
    fi

    # Add to PATH if not already present
    if [[ ":$PATH:" != *":$install_dir:"* ]]; then
        echo
        echo -e "${YELLOW}Important:${NC} Add this line to your ~/.bashrc or ~/.zshrc:"
        echo "  export PATH=\"$install_dir:\$PATH\""
        echo
        echo "Then run: source ~/.bashrc   (or restart your terminal)"
    fi

    # Verify
    if "$install_dir/arduino-cli" version >/dev/null 2>&1; then
        echo -e "${GREEN}✓ arduino-cli successfully installed${NC}"
        "$install_dir/arduino-cli" version
    else
        echo -e "${RED}Verification failed${NC} – please check the install output above"
        return 1
    fi
}

# Helper: execute a function in the context of a temporary git branch, then restore
with_git_branch() {
    local branch="$1"
    shift

    require_project_dir

    # Remember current state
    local original_ref
    original_ref=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || die "Not a git repository"

    local was_dirty=false
    if ! git diff --quiet || ! git diff --cached --quiet; then
        was_dirty=true
        echo -e "${YELLOW}Stashing local changes...${NC}"
        git stash push -m "mini-bowling temporary stash" || die "Stash failed"
    fi

    # Fetch latest to make sure remote branches are up-to-date
    git fetch --quiet || echo -e "${YELLOW}Warning: git fetch failed${NC}"

    # Checkout the requested branch / ref
    echo -e "${YELLOW}Temporarily checking out:${NC} $branch"
    git checkout --quiet "$branch" || die "Cannot checkout '$branch' (does it exist? Try 'origin/$branch' or a tag/commit)"

    # Run the requested command with remaining args
    local exit_code=0
    "$@" || exit_code=$?

    # Restore original branch
    echo -e "${YELLOW}Returning to original branch:${NC} $original_ref"
    git checkout --quiet "$original_ref" || echo -e "${RED}Warning: failed to return to $original_ref${NC}"

    if $was_dirty; then
        echo -e "${YELLOW}Restoring stashed changes...${NC}"
        git stash pop --quiet || echo -e "${RED}Warning: stash pop failed – check manually${NC}"
    fi

    return $exit_code
}

# ------------------------------------------------
#  Main
# ------------------------------------------------

main() {
    [[ $# -eq 0 ]] && {
        cat <<'EOF'
Usage: mini-bowling <command> [options]

Available commands:
  status                Show project / port / app status
  update                git pull latest main branch
  upload [--FolderName | --list-sketches] [--branch <n>] [--no-kill]
                        Compile + upload sketch → restart ScoreMore (default: Everything)
  deploy [--no-kill] [--branch <n>]
                        Pull → upload Everything → restart ScoreMore (default branch: main)
  download <version>    Download + restart ScoreMore (e.g. 1.8.0 or 'latest')
  start-scoremore       Start ScoreMore AppImage
  setup-autostart       Create scoremore.desktop in ~/.config/autostart
  remove-autostart      Remove scoremore.desktop from ~/.config/autostart
  schedule-deploy HH:MM Schedule deploy to run daily at the specified time
  unschedule-deploy     Remove the scheduled daily deploy
  console               Arduino serial monitor (Ctrl+C to exit)
  list                  arduino-cli board list
  logs [list|follow|dump|tail [N]]
                        List log files, or view today's log (default: list)
  create-dir            Create required directories
  install-cli           Install arduino-cli if missing
  install               Guided first-time setup wizard
  preflight             Check all conditions before deploying
  doctor                Check all required dependencies are installed
  version               Show script version, path, and shell info
  backup                Backup Arduino sketches and ScoreMore config
  wait-for-network [N]  Wait up to N seconds for network (default: 30)
  rollback [N]          Roll back N git commits and re-upload (default: 1)
  check-update          Check if remote has new commits without pulling
  scoremore-history [list|use <ver>|clean]
                        Manage downloaded ScoreMore versions
  rollback-scoremore    Switch to the previous downloaded ScoreMore version
  check-scoremore-update
                        Check scoremorebowling.com for a newer ScoreMore version
  serial-log [start|stop|status|tail]
                        Capture Arduino serial output to a log file
  watchdog              Check if ScoreMore is running and restart if not
  setup-watchdog [enable|disable|status]
                        Manage the ScoreMore watchdog cron job (every 5 min)
  disk-cleanup          Remove old AppImages, build caches, and old logs
  pi-update             Run apt update + upgrade
  pi-reboot             Reboot the Raspberry Pi (5 second countdown)
  pi-shutdown           Shut down the Raspberry Pi (5 second countdown)
  wifi-status           Show network interface, IP, SSID, and internet reachability

Examples:
  mini-bowling status
  mini-bowling create-dir
  mini-bowling install-cli
  mini-bowling update
  mini-bowling upload --list-sketches
  mini-bowling upload --Everything
  mini-bowling upload --Master_Test --branch feature/new-sensor
  mini-bowling deploy
  mini-bowling deploy --no-kill
  mini-bowling deploy --branch testing
  mini-bowling download 1.8.0
  mini-bowling download latest
  mini-bowling setup-autostart
  mini-bowling remove-autostart
  mini-bowling schedule-deploy 02:30
  mini-bowling unschedule-deploy
  mini-bowling logs
  mini-bowling logs follow
  mini-bowling logs dump
  mini-bowling logs tail
  mini-bowling logs tail 100
  mini-bowling install
  mini-bowling preflight
  mini-bowling doctor
  mini-bowling version
  mini-bowling scoremore-version
  mini-bowling check-scoremore-update
  mini-bowling backup
  mini-bowling wait-for-network
  mini-bowling rollback
  mini-bowling rollback 2
  mini-bowling check-update
  mini-bowling scoremore-history
  mini-bowling scoremore-history use 1.7.0
  mini-bowling scoremore-history clean
  mini-bowling rollback-scoremore
  mini-bowling serial-log start
  mini-bowling serial-log stop
  mini-bowling serial-log tail
  mini-bowling watchdog
  mini-bowling setup-watchdog enable
  mini-bowling setup-watchdog disable
  mini-bowling disk-cleanup
  mini-bowling pi-status
  mini-bowling pi-update
  mini-bowling pi-reboot
  mini-bowling pi-shutdown
  mini-bowling wifi-status

EOF
        exit 0
    }

    local cmd="$1"

    # Item 8: silently create required directories on first run if missing
    mkdir -p "$PROJECT_DIR" "$SCOREMORE_DIR" "$LOG_DIR" 2>/dev/null || true

    # Skip logging for informational commands that don't do anything
    if [[ "$cmd" != "logs" && "$cmd" != "status" && "$cmd" != "list" \
       && "$cmd" != "pi-status" && "$cmd" != "wifi-status" \
       && "$cmd" != "doctor" && "$cmd" != "preflight" \
       && "$cmd" != "scoremore-version" && "$cmd" != "wait-for-network" \
       && "$cmd" != "check-update" && "$cmd" != "scoremore-history" \
       && "$cmd" != "check-scoremore-update" \
       && "$cmd" != "serial-log" && "$cmd" != "setup-watchdog" \
       && "$cmd" != "watchdog" && "$cmd" != "version" ]]; then
        setup_logging "$cmd" "$@"
        prune_logs
    fi

    shift

    # Commands using sudo need a real TTY — run them directly, log header only
    local bypass_tee=false
    if [[ "$cmd" == "pi-update" || "$cmd" == "pi-reboot" || "$cmd" == "pi-shutdown" ]]; then
        bypass_tee=true
    fi

    # Dispatch — if logging is active, pipe stdout to tee without exec redirects
    if [[ -n "${MINI_BOWLING_LOG:-}" ]] && ! $bypass_tee; then
        _dispatch "$cmd" "$@" | tee -a "$MINI_BOWLING_LOG"
        local dispatch_exit="${PIPESTATUS[0]}"
    else
        _dispatch "$cmd" "$@"
        local dispatch_exit=$?
    fi

    [[ $dispatch_exit -eq 0 ]] && echo -e "${GREEN}Done.${NC}" || exit $dispatch_exit
}

_dispatch() {
    local cmd="$1"
    shift

    case "$cmd" in
        download)
            local dl_ver="${1?Missing version number — use a version like 1.8.0 or 'latest'}"
            if [[ "$dl_ver" == "latest" ]]; then
                echo "Resolving latest ScoreMore version..."
                local page
                page=$(curl --silent --fail --max-time 10 \
                    "https://www.scoremorebowling.com/download") || \
                    die "Could not reach scoremorebowling.com — is the network available?"
                dl_ver=$(echo "$page" | grep -oP "ScoreMore-\K[0-9]+\.[0-9]+(\.[0-9]+)?(?=-${ARCH}\.${EXTENSION})" | head -1 || true)
                if [[ -z "$dl_ver" ]]; then
                    dl_ver=$(echo "$page" | grep -oP "ScoreMore \K[0-9]+\.[0-9]+(\.[0-9]+)?(?=,? Latest)" | head -1 || true)
                fi
                [[ -n "$dl_ver" ]] || die "Could not determine latest version from scoremorebowling.com"
                echo "Latest version: $dl_ver"
            fi
            download_scoremore_version "$dl_ver"
            ;;
        start-scoremore)
            start_scoremore
            ;;
        setup-autostart)
            setup_autostart
            ;;
        remove-autostart)
            remove_autostart
            ;;
        schedule-deploy)
            schedule_deploy "${1:-}"
            ;;
        unschedule-deploy)
            unschedule_deploy
            ;;
        update)
            cmd_update
            ;;
        upload)
            local branch=""
            local sketch="Everything"
            local kill_app="true"

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --list-sketches)
                        list_available_sketches
                        exit 0
                        ;;
                    --no-kill|-k)
                        kill_app="false"
                        shift
                        ;;
                    --branch=*)
                        branch="${1#--branch=}"
                        shift
                        ;;
                    --branch)
                        shift
                        branch="${1?Missing branch name after --branch}"
                        shift
                        ;;
                    --*)
                        sketch="${1#--}"
                        shift
                        ;;
                    *)
                        die "Unexpected argument for upload: $1"
                        ;;
                esac
            done

            if [[ -z "$branch" ]]; then
                branch="$DEFAULT_GIT_BRANCH"
                echo -e "${GREEN}Using default branch:${NC} $branch"
            else
                echo -e "${YELLOW}Using specified branch:${NC} $branch"
            fi

            with_git_branch "$branch" cmd_compile_and_upload "$sketch" "$kill_app"
            start_scoremore
            ;;
        deploy)
            cmd_deploy "$@"
            ;;
        console)
            show_console
            ;;
        status)
            print_status
            ;;
        list)
            board_list
            ;;
        rollback)
            cmd_rollback "${1:-1}"
            ;;
        check-update)
            check_update
            ;;
        scoremore-history)
            scoremore_history "$@"
            ;;
        rollback-scoremore)
            rollback_scoremore
            ;;
        serial-log)
            serial_log "${1:-start}" "${@:2}"
            ;;
        watchdog)
            watchdog
            ;;
        setup-watchdog)
            setup_watchdog "${1:-enable}"
            ;;
        disk-cleanup)
            disk_cleanup
            ;;
        create-dir|createdir)
            ensure_directories
            ;;
        install-cli)
            install_cli
            ;;
        install)
            install_setup
            ;;
        preflight)
            preflight
            ;;
        doctor)
            doctor
            ;;
        version)
            script_version
            ;;
        check-scoremore-update)
            check_scoremore_update
            ;;
        scoremore-version)
            scoremore_version
            ;;
        backup)
            backup_config
            ;;
        wait-for-network)
            wait_for_network "${1:-30}"
            ;;
        pi-status)
            pi_status
            ;;
        pi-update)
            pi_update
            ;;
        pi-reboot)
            pi_reboot
            ;;
        pi-shutdown)
            pi_shutdown
            ;;
        wifi-status)
            wifi_status
            ;;
        logs)
            show_logs "$@"
            ;;
        *)
            echo "Unknown command: $cmd" >&2
            exit 1
            ;;
    esac
}

main "$@"
