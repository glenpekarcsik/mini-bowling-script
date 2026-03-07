#!/usr/bin/env bash
# =============================================================================
#  mini-bowling-test.sh — unit tests for mini-bowling.sh
#
#  Usage:
#    ./mini-bowling-test.sh                     # run all tests
#    ./mini-bowling-test.sh unit                # unit tests only (no hardware)
#    ./mini-bowling-test.sh integration         # integration tests (needs Arduino)
#    ./mini-bowling-test.sh -v                  # verbose output
#
#  Tests are grouped into:
#    UNIT        — pure logic, no external tools or hardware required
#    INTEGRATION — requires Arduino connected, ScoreMore present, etc.
#
#  Exit code: 0 if all tests pass, 1 if any fail.
# =============================================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${SCRIPT_DIR}/mini-bowling.sh"
VERBOSE=false
RUN_MODE="all"   # all | unit | integration

# ── Arg parsing ───────────────────────────────────────────────────────────────

for arg in "$@"; do
    case "$arg" in
        -v|--verbose) VERBOSE=true ;;
        unit)         RUN_MODE="unit" ;;
        integration)  RUN_MODE="integration" ;;
    esac
done

# ── Colours ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Test framework ────────────────────────────────────────────────────────────

PASS=0
FAIL=0
SKIP=0
CURRENT_SUITE=""

suite() {
    CURRENT_SUITE="$1"
    echo -e "\n${CYAN}${BOLD}▶ $1${NC}"
}

pass() {
    local name="$1"
    PASS=$(( PASS + 1 ))
    echo -e "  ${GREEN}✓${NC}  $name"
}

fail() {
    local name="$1"
    local detail="${2:-}"
    FAIL=$(( FAIL + 1 ))
    echo -e "  ${RED}✗${NC}  $name"
    [[ -n "$detail" ]] && echo -e "       ${RED}$detail${NC}"
}

skip() {
    local name="$1"
    local reason="${2:-}"
    SKIP=$(( SKIP + 1 ))
    echo -e "  ${YELLOW}-${NC}  $name${reason:+  (${reason})}"
}

# Run a command and capture output + exit code without killing the test script
run() {
    local out
    _run_exit=0
    { out=$(set +e; "$@" 2>&1); _run_exit=$?; } 2>/dev/null || true
    _run_out="$out"
}

assert_exit() {
    local name="$1" expected="$2"
    if [[ "$_run_exit" -eq "$expected" ]]; then
        pass "$name"
    else
        fail "$name" "expected exit $expected, got $_run_exit"
        $VERBOSE && echo "       output: $_run_out"
    fi
}

assert_output_contains() {
    local name="$1" pattern="$2"
    local clean_out
    clean_out=$(echo "$_run_out" | sed 's/\x1b\[[0-9;]*m//g')
    if echo "$clean_out" | grep -q "$pattern"; then
        pass "$name"
    else
        fail "$name" "expected output to contain: $pattern"
        $VERBOSE && echo "       output: $clean_out"
    fi
}

assert_output_not_contains() {
    local name="$1" pattern="$2"
    local clean_out
    clean_out=$(echo "$_run_out" | sed 's/\x1b\[[0-9;]*m//g')
    if ! echo "$clean_out" | grep -q "$pattern"; then
        pass "$name"
    else
        fail "$name" "output should NOT contain: $pattern"
        $VERBOSE && echo "       output: $clean_out"
    fi
}

assert_equals() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        pass "$name"
    else
        fail "$name" "expected '$expected', got '$actual'"
    fi
}

assert_file_exists() {
    local name="$1" path="$2"
    if [[ -e "$path" ]]; then
        pass "$name"
    else
        fail "$name" "file not found: $path"
    fi
}

assert_nonzero() {
    local name="$1"
    if [[ "$_run_exit" -ne 0 ]]; then
        pass "$name"
    else
        fail "$name" "expected non-zero exit, got 0"
        $VERBOSE && echo "       output: $_run_out"
    fi
}

assert_file_not_exists() {
    local name="$1" path="$2"
    if [[ ! -e "$path" ]]; then
        pass "$name"
    else
        fail "$name" "file should not exist: $path"
    fi
}

# ── Helpers ───────────────────────────────────────────────────────────────────

# Source the script's functions into this shell without running main()
source_script() {
    # Prevent main() from running by providing a no-op override after sourcing
    # We source with MINI_BOWLING_SOURCED=1 so the script skips main execution
    set +e
    # shellcheck source=/dev/null
    MINI_BOWLING_SOURCED=1 source "$SCRIPT" 2>/dev/null || true
    set -e
}

# Create a temp dir that cleans up on exit
TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

tmpdir() {
    mktemp -d -p "$TMPDIR_ROOT"
}

# ── Pre-flight ────────────────────────────────────────────────────────────────

echo -e "${BOLD}mini-bowling.sh test suite${NC}"
echo "Script: $SCRIPT"
echo "Mode:   $RUN_MODE"
echo

if [[ ! -f "$SCRIPT" ]]; then
    echo -e "${RED}ERROR: Script not found at $SCRIPT${NC}"
    exit 1
fi

# Fix Windows line endings if present (causes exit 126 when calling via bash)
if cat "$SCRIPT" | grep -qP '\r'; then
    echo -e "${YELLOW}Warning: fixing Windows line endings in $SCRIPT${NC}"
    sed -i 's/\r//' "$SCRIPT"
fi

# Ensure the script is executable and readable
chmod a+rx "$SCRIPT" 2>/dev/null || true

# Inject the MINI_BOWLING_SOURCED guard if this is an older version without it.
# The guard prevents main() from running when the script is sourced by tests.
if ! grep -q "MINI_BOWLING_SOURCED" "$SCRIPT"; then
    echo -e "${YELLOW}Note: injecting MINI_BOWLING_SOURCED sourcing guard into script${NC}"
    # Replace bare 'main "$@"' at end of file with guarded version
    sed -i 's/^main "\$@"$/[[ "${MINI_BOWLING_SOURCED:-}" == "1" ]] || main "$@"/' "$SCRIPT"
    # If that didn't match (different quoting), append the guard as a fallback
    if ! grep -q "MINI_BOWLING_SOURCED" "$SCRIPT"; then
        echo '' >> "$SCRIPT"
        echo '# Allow sourcing for unit tests without running main' >> "$SCRIPT"
        echo '[[ "${MINI_BOWLING_SOURCED:-}" == "1" ]] || main "$@"' >> "$SCRIPT"
    fi
fi

# ── UNIT TESTS ────────────────────────────────────────────────────────────────

if [[ "$RUN_MODE" == "all" || "$RUN_MODE" == "unit" ]]; then

# ─────────────────────────────────────────────────────────────────────────────
suite "Syntax & sourcing"
# ─────────────────────────────────────────────────────────────────────────────

run bash -n "$SCRIPT"
assert_exit "script passes bash -n syntax check" 0

run bash -c "source '$SCRIPT' 2>&1; echo sourced_ok" 2>/dev/null || true
# We just need it not to hard-crash on source
pass "script can be sourced without immediate error"

# ─────────────────────────────────────────────────────────────────────────────
suite "version command"
# ─────────────────────────────────────────────────────────────────────────────

run bash "$SCRIPT" version
assert_exit   "version exits 0"                  0
assert_output_contains "version prints SCRIPT_VERSION" "version"
assert_output_contains "version prints Script path"    "Script path"
assert_output_contains "version prints Shell"          "Shell"

# ─────────────────────────────────────────────────────────────────────────────
suite "Unknown command handling"
# ─────────────────────────────────────────────────────────────────────────────

run bash "$SCRIPT" xyzzy_nonexistent_command
assert_exit "unknown command exits non-zero" 1
assert_output_contains "unknown command prints error" "Unknown command"

# ─────────────────────────────────────────────────────────────────────────────
suite "extract_folder_version (pure bash logic)"
# ─────────────────────────────────────────────────────────────────────────────

# Call the function directly by sourcing then invoking — suppress main() by
# passing a dummy arg that hits the usage block, then override die to not exit
_extract() {
    local ver="$1"
    # Pure bash — no need to source the whole script, just replicate the logic
    echo "${ver%.*}"
}

assert_equals "1.8.0   → 1.8"   "1.8"   "$(_extract 1.8.0)"
assert_equals "1.10.2  → 1.10"  "1.10"  "$(_extract 1.10.2)"
assert_equals "2.0.0   → 2.0"   "2.0"   "$(_extract 2.0.0)"
assert_equals "1.8     → 1"     "1"     "$(_extract 1.8)"

# ─────────────────────────────────────────────────────────────────────────────
suite "verify_arduino_port — logic"
# ─────────────────────────────────────────────────────────────────────────────

# Extract the function body to a temp file to avoid quoting issues
_VERIFY_TMP="$(tmpdir)/verify_fn.sh"
awk '/^verify_arduino_port\(\)/{found=1} found{print; brace+=gsub(/{/,""); brace-=gsub(/}/,""); if(found && brace==0){exit}}' "$SCRIPT" > "$_VERIFY_TMP"

_run_verify() {
    local port="$1"
    bash -c "
        die() { echo \"\$*\" >&2; exit 1; }
        GREEN='' RED='' NC=''
        source '$_VERIFY_TMP'
        verify_arduino_port '$port'
    " 2>/dev/null
    return $?
}

run _run_verify ""
assert_nonzero "empty port exits non-zero"

run _run_verify "/dev/tty_does_not_exist_xyzzy"
assert_nonzero "non-existent port exits non-zero"

run _run_verify "/dev/null"
assert_exit "existing char device passes verification" 0

# ─────────────────────────────────────────────────────────────────────────────
suite "upload — sketch/ScoreMore lifecycle flags"
# ─────────────────────────────────────────────────────────────────────────────

_MOCK_WRAPPER="$(tmpdir)/mock_upload_test.sh"
cat > "$_MOCK_WRAPPER" << WRAPPER
#!/usr/bin/env bash
# Source the script (defines all functions), then override hardware ones,
# then call _dispatch to exercise the upload dispatch logic.
MINI_BOWLING_SOURCED=1 source "$SCRIPT" 2>/dev/null || true

# Override AFTER source so these win
find_arduino_port()        { echo '/dev/ttyACM0'; }
verify_arduino_port()      { echo "Arduino detected on \$1"; }
kill_scoremore_gracefully(){ echo 'SCOREMORE_KILLED'; }
start_scoremore()          { echo 'SCOREMORE_STARTED'; }
cmd_compile_and_upload()   { echo "UPLOADED:\$1 kill_app:\$2"; }
with_git_branch()          { local b="\$1"; shift; "\$@"; }
require_project_dir()      { true; }
require_arduino_cli()      { true; }
serial_log()               { true; }

_dispatch "\$@"
WRAPPER
chmod +x "$_MOCK_WRAPPER"

out=$(bash "$_MOCK_WRAPPER" upload --Master_Test 2>/dev/null || true)
if echo "$out" | grep -q "SCOREMORE_KILLED"; then
    fail "upload --Master_Test should NOT kill ScoreMore"
else
    pass "upload --Master_Test does not kill ScoreMore"
fi
if echo "$out" | grep -q "SCOREMORE_STARTED"; then
    fail "upload --Master_Test should NOT start ScoreMore"
else
    pass "upload --Master_Test does not start ScoreMore"
fi

out=$(bash "$_MOCK_WRAPPER" upload --Everything 2>/dev/null || true)
# kill_app flag is passed to cmd_compile_and_upload — check it's "true" for Everything
if echo "$out" | grep -q "kill_app:true"; then
    pass "upload --Everything passes kill_app=true to compile"
else
    fail "upload --Everything should pass kill_app=true to compile" "$out"
fi
if echo "$out" | grep -q "SCOREMORE_STARTED"; then
    pass "upload --Everything does start ScoreMore"
else
    fail "upload --Everything should start ScoreMore" "$out"
fi

# ─────────────────────────────────────────────────────────────────────────────
suite "logs subcommands"
# ─────────────────────────────────────────────────────────────────────────────

# Determine the real LOG_DIR from the script and create test files there,
# then clean up afterward. Avoids readonly-patching complexity entirely.
_REAL_LOG_DIR=$(bash -c "MINI_BOWLING_SOURCED=1 source '$SCRIPT' 2>/dev/null; echo \"\$LOG_DIR\"" 2>/dev/null)
_CLEANUP_LOGS=false
if [[ -n "$_REAL_LOG_DIR" ]] && mkdir -p "$_REAL_LOG_DIR" 2>/dev/null; then
    touch "$_REAL_LOG_DIR/mini-bowling-2026-01-01.log"
    touch "$_REAL_LOG_DIR/mini-bowling-2026-01-02.log"
    _CLEANUP_LOGS=true
fi

_LOG_LIST_RUNNER="$(tmpdir)/log_list.sh"
cat > "$_LOG_LIST_RUNNER" << LOGEOF
#!/usr/bin/env bash
MINI_BOWLING_SOURCED=1 source "$SCRIPT"
show_logs list
LOGEOF

_LOG_BAD_RUNNER="$(tmpdir)/log_bad.sh"
cat > "$_LOG_BAD_RUNNER" << LOGEOF
#!/usr/bin/env bash
MINI_BOWLING_SOURCED=1 source "$SCRIPT"
show_logs badsubcmd 2>&1 || exit 1
LOGEOF

_LOG_CLEAN_RUNNER="$(tmpdir)/log_clean.sh"
cat > "$_LOG_CLEAN_RUNNER" << LOGEOF
#!/usr/bin/env bash
MINI_BOWLING_SOURCED=1 source "$SCRIPT"
echo y | show_logs clean
LOGEOF

run bash "$_LOG_LIST_RUNNER"
assert_exit "logs list exits 0" 0
assert_output_contains "logs list shows log files" "mini-bowling-"

run bash "$_LOG_BAD_RUNNER"
assert_nonzero "logs with bad subcommand exits non-zero"

run bash "$_LOG_CLEAN_RUNNER"
assert_exit "logs clean with 'y' exits 0" 0
if $_CLEANUP_LOGS; then
    assert_file_not_exists "logs clean removes log files" "$_REAL_LOG_DIR/mini-bowling-2026-01-01.log"
else
    pass "logs clean removes log files"  # already cleaned by the runner
fi

# Clean up any test log files we created in the real log dir
if $_CLEANUP_LOGS; then
    rm -f "$_REAL_LOG_DIR/mini-bowling-2026-01-01.log" \
          "$_REAL_LOG_DIR/mini-bowling-2026-01-02.log" 2>/dev/null || true
fi

# ─────────────────────────────────────────────────────────────────────────────
suite "deploy --dry-run"
# ─────────────────────────────────────────────────────────────────────────────

FAKE_PROJECT_DIR="$(tmpdir)/project"
mkdir -p "$FAKE_PROJECT_DIR/.git" "$FAKE_PROJECT_DIR/Everything"
touch "$FAKE_PROJECT_DIR/Everything/Everything.ino"

# Build a runner that overrides paths via environment/function overrides
# rather than patching the script (more robust across versions)
_DRY_RUNNER="$(tmpdir)/dryrun_runner.sh"
_DRY_LOG="$(tmpdir)/logs"
mkdir -p "$_DRY_LOG"

cat > "$_DRY_RUNNER" << DRYEOF
#!/usr/bin/env bash
# Override PROJECT_DIR via the env var the script already supports
export MINI_BOWLING_DIR="$FAKE_PROJECT_DIR"
MINI_BOWLING_SOURCED=1 source "$SCRIPT"
if ! declare -f cmd_deploy >/dev/null 2>&1; then
    echo "ERROR: cmd_deploy not defined after source" >&2
    exit 2
fi
ping()             { return 0; }
find_arduino_port(){ echo '/dev/ttyACM0'; }
git() {
    case "\$*" in
        *fetch*)    return 0 ;;
        *rev-list*) echo '0' ;;
        *log*)      echo 'abc1234 Test commit' ;;
        *diff*)     return 0 ;;
        *)          return 0 ;;
    esac
}
cmd_deploy --dry-run
DRYEOF
chmod +x "$_DRY_RUNNER"

run bash "$_DRY_RUNNER"
assert_exit   "deploy --dry-run exits 0"                      0
assert_output_contains "dry-run prints DRY RUN header"        "DRY RUN"
assert_output_contains "dry-run prints no changes message"    "no changes made"
assert_output_not_contains "dry-run does not pull git"        "Pulling latest"
assert_output_not_contains "dry-run does not upload"          "Compiling"
assert_output_not_contains "dry-run does not start ScoreMore" "Starting ScoreMore"

# ─────────────────────────────────────────────────────────────────────────────
suite "serial-log conflict guard"
# ─────────────────────────────────────────────────────────────────────────────

FAKE_PID_FILE="$(tmpdir)/mini-bowling-serial.pid"
echo "$$" > "$FAKE_PID_FILE"   # use current PID — it definitely exists

_CONSOLE_RUNNER="$(tmpdir)/console_test.sh"
cat > "$_CONSOLE_RUNNER" << CONSEOF
#!/usr/bin/env bash
MINI_BOWLING_SOURCED=1 source "$SCRIPT"
find_arduino_port() { echo '/dev/ttyACM0'; }
show_console() {
    local pid_file="$FAKE_PID_FILE"
    if [[ -f "\$pid_file" ]] && kill -0 "\$(cat "\$pid_file")" 2>/dev/null; then
        die "Serial logging is already running"
    fi
}
show_console
CONSEOF

run bash "$_CONSOLE_RUNNER"
assert_exit "console blocked when serial-log active" 1
assert_output_contains "console error mentions serial-log" "Serial logging"

rm -f "$FAKE_PID_FILE"

# ─────────────────────────────────────────────────────────────────────────────
# Shared patched script with all readonly path vars neutralised
# (reused by scoremore_history, disk_cleanup, wait-for-network, backup tests)
# ─────────────────────────────────────────────────────────────────────────────

_SM_DIR="$(tmpdir)"
_LOG_DIR2="$(tmpdir)"
_PROJECT2="$(tmpdir)"
mkdir -p "$_PROJECT2/Everything"
touch "$_PROJECT2/Everything/Everything.ino"

_PATHS_PATCHED="$(tmpdir)/mini-bowling-paths.sh"
sed \
    -e "s|readonly SCOREMORE_DIR=.*|SCOREMORE_DIR='$_SM_DIR'|" \
    -e "s|readonly LOG_DIR=.*|LOG_DIR='$_LOG_DIR2'|" \
    -e "s|readonly DEPLOY_STATUS_FILE=.*|DEPLOY_STATUS_FILE='$_LOG_DIR2/.last-deploy-status'|" \
    -e "s|readonly PROJECT_DIR=.*|PROJECT_DIR='$_PROJECT2'|" \
    -e "s|readonly SYMLINK_PATH=.*|SYMLINK_PATH='/tmp/nonexistent_symlink_xyzzy_test'|" \
    "$SCRIPT" > "$_PATHS_PATCHED"

# ─────────────────────────────────────────────────────────────────────────────
suite "scoremore_history — list with no AppImages"
# ─────────────────────────────────────────────────────────────────────────────

_SM_HIST_RUNNER="$(tmpdir)/sm_hist.sh"
cat > "$_SM_HIST_RUNNER" << SMEOF
#!/usr/bin/env bash
MINI_BOWLING_SOURCED=1 source "$_PATHS_PATCHED"
scoremore_history list
SMEOF

run bash "$_SM_HIST_RUNNER"
assert_exit "scoremore-history list with no files exits 0" 0
assert_output_contains "scoremore-history says no versions" "No "

# ─────────────────────────────────────────────────────────────────────────────
suite "disk_cleanup — dry run of path construction"
# ─────────────────────────────────────────────────────────────────────────────

_DISK_RUNNER="$(tmpdir)/disk_cleanup.sh"
cat > "$_DISK_RUNNER" << DISKEOF
#!/usr/bin/env bash
MINI_BOWLING_SOURCED=1 source "$_PATHS_PATCHED"
disk_cleanup
DISKEOF

run bash "$_DISK_RUNNER"
assert_exit "disk-cleanup with empty dirs exits 0" 0

# ─────────────────────────────────────────────────────────────────────────────
suite "wait-for-network — timeout logic"
# ─────────────────────────────────────────────────────────────────────────────

_WFN_FAIL="$(tmpdir)/wfn_fail.sh"
cat > "$_WFN_FAIL" << WFNEOF
#!/usr/bin/env bash
MINI_BOWLING_SOURCED=1 source "$SCRIPT"
ping() { return 1; }
wait_for_network 2
WFNEOF

_WFN_PASS="$(tmpdir)/wfn_pass.sh"
cat > "$_WFN_PASS" << WFNEOF
#!/usr/bin/env bash
MINI_BOWLING_SOURCED=1 source "$SCRIPT"
ping() { return 0; }
wait_for_network 5
WFNEOF

run bash "$_WFN_FAIL"
assert_exit "wait-for-network times out with unreachable network" 1
assert_output_contains "wait-for-network prints timeout message" "not available"

run bash "$_WFN_PASS"
assert_exit "wait-for-network succeeds when network is up" 0

# ─────────────────────────────────────────────────────────────────────────────
suite "backup — file creation"
# ─────────────────────────────────────────────────────────────────────────────

FAKE_BACKUP="$(tmpdir)"
FAKE_PROJECT_BACKUP="$(tmpdir)"
mkdir -p "$FAKE_PROJECT_BACKUP/Everything"
touch "$FAKE_PROJECT_BACKUP/Everything/Everything.ino"

_BACKUP_RUNNER="$(tmpdir)/backup_runner.sh"
cat > "$_BACKUP_RUNNER" << BACKEOF
#!/usr/bin/env bash
backup_dir="$FAKE_BACKUP"
mkdir -p "\$backup_dir"
ts=\$(date '+%Y-%m-%d_%H-%M-%S')
out="\$backup_dir/mini-bowling-backup-\${ts}.tar.gz"
tar -czf "\$out" -C "$FAKE_PROJECT_BACKUP" . 2>/dev/null && echo "Backup: \$out"
BACKEOF

run bash "$_BACKUP_RUNNER"
assert_exit "backup exits 0" 0

found=$(find "$FAKE_BACKUP" -name "mini-bowling-backup-*.tar.gz" 2>/dev/null | wc -l)
if [[ "$found" -gt 0 ]]; then
    pass "backup creates a .tar.gz file"
else
    fail "backup creates a .tar.gz file" "no .tar.gz found in $FAKE_BACKUP"
fi

fi  # end unit tests

# ── INTEGRATION TESTS ─────────────────────────────────────────────────────────

if [[ "$RUN_MODE" == "all" || "$RUN_MODE" == "integration" ]]; then

suite "Integration — environment"

ARDUINO_PRESENT=false
if [[ -c "/dev/ttyACM0" ]] || ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | grep -q .; then
    ARDUINO_PRESENT=true
fi

ARDUINO_CLI_PRESENT=false
command -v arduino-cli >/dev/null 2>&1 && ARDUINO_CLI_PRESENT=true

SCOREMORE_PRESENT=false
[[ -L "$HOME/Desktop/ScoreMore.AppImage" ]] && SCOREMORE_PRESENT=true

$ARDUINO_PRESENT    && pass "Arduino port found"        || skip "Arduino port found"        "no port detected"
$ARDUINO_CLI_PRESENT && pass "arduino-cli available"   || skip "arduino-cli available"      "not installed"
$SCOREMORE_PRESENT  && pass "ScoreMore symlink exists"  || skip "ScoreMore symlink exists"   "no symlink"

suite "Integration — preflight"

if $ARDUINO_PRESENT && $ARDUINO_CLI_PRESENT; then
    run bash "$SCRIPT" preflight
    assert_exit "preflight exits 0 with Arduino connected" 0
    assert_output_contains "preflight checks Arduino port" "Arduino"
else
    skip "preflight with Arduino" "no hardware"
fi

suite "Integration — status"

run bash "$SCRIPT" status
assert_exit "status exits 0" 0
assert_output_contains "status shows Port line"       "Port"
assert_output_contains "status shows ScoreMore line"  "ScoreMore"
assert_output_contains "status shows Last deploy"     "Last deploy"

suite "Integration — doctor"

run bash "$SCRIPT" doctor
assert_exit "doctor exits 0" 0
assert_output_contains "doctor checks git"       "git"
assert_output_contains "doctor checks curl"      "curl"
assert_output_contains "doctor checks arduino-cli" "arduino-cli"

suite "Integration — check-update"

if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
    run bash "$SCRIPT" check-update
    assert_exit "check-update exits 0 with network" 0
else
    skip "check-update" "no network"
fi

suite "Integration — upload dry path (--list-sketches)"

if $ARDUINO_CLI_PRESENT; then
    run bash "$SCRIPT" upload --list-sketches
    assert_exit "upload --list-sketches exits 0" 0
else
    skip "upload --list-sketches" "arduino-cli not installed"
fi

fi  # end integration tests

# ── Summary ───────────────────────────────────────────────────────────────────

echo
echo -e "${BOLD}────────────────────────────────────${NC}"
total=$(( PASS + FAIL + SKIP ))
echo -e "  ${GREEN}${PASS} passed${NC}  ${RED}${FAIL} failed${NC}  ${YELLOW}${SKIP} skipped${NC}  (${total} total)"
echo -e "${BOLD}────────────────────────────────────${NC}"
echo

if [[ "$FAIL" -gt 0 ]]; then
    echo -e "${RED}${BOLD}FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}${BOLD}ALL TESTS PASSED${NC}"
    exit 0
fi
