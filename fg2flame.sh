#!/usr/bin/env bash
# =============================================================================
# fg2flame.sh — trace-cmd function_graph to FlameGraph all-in-one script
#
# Usage:
#   ./fg2flame.sh record [options]   # record traces and generate flame graph
#   ./fg2flame.sh convert [options]  # convert existing trace.dat to flame graph
#   ./fg2flame.sh report  [options]  # export raw text report only
#
# Examples:
#   ./fg2flame.sh record -d 10 -o out.svg
#   ./fg2flame.sh record -d 5 -p 1234 -f "vfs_read vfs_write" -o out.svg
#   ./fg2flame.sh record -d 5 -- myprogram --args
#   ./fg2flame.sh convert -i trace.dat -o out.svg
#   ./fg2flame.sh report  -i trace.dat > report.txt
# =============================================================================

set -euo pipefail

# -- Colored output helpers ---------------------------------------------------
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# -- Default parameter values -------------------------------------------------
DURATION=10           # recording duration in seconds
TRACE_DAT="trace.dat" # output file for trace-cmd record
OUTPUT_SVG="flamegraph.svg"
FOLDED_FILE=""        # intermediate folded stacks file; empty = use a temp file
FILTER_PID=""         # filter by PID (-p)
FILTER_FUNCS=""       # filter by function names, space-separated (-f)
FILTER_CMDS=""        # filter by process names, space-separated (-c)
WEIGHT_MODE="count"   # count = call frequency | time = elapsed time in us
TITLE="Function Graph Flame Graph"
FLAMEGRAPH_DIR=""     # path to FlameGraph repo; empty = auto-detect or clone
KEEP_TEMP=0           # set to 1 to retain intermediate temporary files
EXTRA_TRACE_ARGS=()   # extra arguments forwarded to trace-cmd record
CMD_TO_RUN=()         # command to execute while recording (-- mode)

# -- Usage / help -------------------------------------------------------------
usage() {
cat <<EOF
${BOLD}fg2flame.sh${NC} — end-to-end pipeline: trace-cmd function_graph -> FlameGraph SVG

${BOLD}Subcommands:${NC}
  record   Record kernel traces, convert, and generate SVG
  convert  Convert an existing trace.dat file to SVG
  report   Export trace-cmd report text to stdout

${BOLD}Common options:${NC}
  -i <file>       Input trace.dat path                  [default: trace.dat]
  -o <file>       Output SVG path                       [default: flamegraph.svg]
  -O <file>       Save intermediate folded stacks file
  -F <dir>        Path to FlameGraph repository         [default: auto-detect or clone]
  -w count|time   Flame graph weight: count=call freq, time=elapsed us  [default: count]
  -T <title>      SVG title string
  -k              Keep all intermediate temporary files
  -h              Show this help message

${BOLD}record-only options:${NC}
  -d <secs>       Recording duration in seconds         [default: 10]
  -p <pid>        Trace only the specified PID
  -f <funcs>      Trace only these functions (space-separated, quoted)
  -c <cmds>       Trace only these process names (space-separated)
  -- <cmd>        Run this command during recording; stop when it exits

${BOLD}Examples:${NC}

  ${BOLD}# record — basic${NC}
  # Record the whole system for 10 seconds and generate flame.svg
  sudo ./fg2flame.sh record -d 10 -o flame.svg

  # Record for 30 seconds with a custom SVG title
  sudo ./fg2flame.sh record -d 30 -T "My App Profile" -o flame.svg

  ${BOLD}# record — filtering${NC}
  # Trace only PID 1234
  sudo ./fg2flame.sh record -d 5 -p 1234 -o flame.svg

  # Trace only vfs_read and vfs_write kernel functions
  sudo ./fg2flame.sh record -d 5 -f "vfs_read vfs_write" -o flame.svg

  # Trace only processes named "nginx" and "worker"
  sudo ./fg2flame.sh record -d 5 -c "nginx worker" -o flame.svg

  # Combine: trace PID 1234 and only within vfs_read subtree
  sudo ./fg2flame.sh record -d 5 -p 1234 -f "vfs_read" -o flame.svg

  ${BOLD}# record — run a command${NC}
  # Record while running a command; stops automatically when the command exits
  sudo ./fg2flame.sh record -- python3 myscript.py

  # Record a short-lived benchmark and save the trace file for later
  sudo ./fg2flame.sh record -i bench.dat -- ./mybench --iterations 1000

  ${BOLD}# record — weight modes${NC}
  # Weight by call count (default): highlights hot code paths
  sudo ./fg2flame.sh record -d 10 -w count -o flame_count.svg

  # Weight by elapsed time (us): highlights where time is actually spent
  sudo ./fg2flame.sh record -d 10 -w time -o flame_time.svg

  ${BOLD}# record — intermediate files${NC}
  # Keep the folded stacks file for manual inspection or re-rendering
  sudo ./fg2flame.sh record -d 10 -O stacks.folded -o flame.svg

  # Keep all intermediate temp files (report text + folded)
  sudo ./fg2flame.sh record -d 10 -k -o flame.svg

  ${BOLD}# convert — from existing trace.dat${NC}
  # Convert a previously recorded trace.dat to a flame graph
  sudo ./fg2flame.sh convert -i trace.dat -o flame.svg

  # Convert using a custom FlameGraph repo path
  sudo ./fg2flame.sh convert -i trace.dat -F ~/tools/FlameGraph -o flame.svg

  # Convert and save the folded file for re-use
  sudo ./fg2flame.sh convert -i trace.dat -O stacks.folded -o flame.svg

  ${BOLD}# report — export raw text${NC}
  # Dump the function_graph text report to stdout
  sudo ./fg2flame.sh report -i trace.dat

  # Save the report to a file for manual inspection
  sudo ./fg2flame.sh report -i trace.dat > report.txt

  ${BOLD}# fg2folded.py — standalone parser${NC}
  # Parse a saved report file and write folded stacks to stdout
  python3 fg2folded.py report.txt

  # Full manual pipeline: report -> folded -> SVG
  trace-cmd report -i trace.dat | python3 fg2folded.py | ./FlameGraph/flamegraph.pl > flame.svg

  # Save folded output to a file
  python3 fg2folded.py report.txt stacks.folded
EOF
exit 0
}

# -- Argument parsing ---------------------------------------------------------
parse_args() {
    SUBCMD="${1:-}"; shift || true
    [[ "$SUBCMD" == "-h" || "$SUBCMD" == "--help" || -z "$SUBCMD" ]] && usage

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i) TRACE_DAT="$2";      shift 2 ;;
            -o) OUTPUT_SVG="$2";     shift 2 ;;
            -O) FOLDED_FILE="$2";    shift 2 ;;
            -F) FLAMEGRAPH_DIR="$2"; shift 2 ;;
            -w) WEIGHT_MODE="$2";    shift 2 ;;
            -T) TITLE="$2";          shift 2 ;;
            -d) DURATION="$2";       shift 2 ;;
            -p) FILTER_PID="$2";     shift 2 ;;
            -f) FILTER_FUNCS="$2";   shift 2 ;;
            -c) FILTER_CMDS="$2";    shift 2 ;;
            -k) KEEP_TEMP=1;         shift   ;;
            -h|--help) usage ;;
            --) shift; CMD_TO_RUN=("$@"); break ;;
            *)  die "Unknown argument: $1" ;;
        esac
    done
}

# -- Dependency checks --------------------------------------------------------
check_deps() {
    local missing=()
    command -v trace-cmd &>/dev/null || missing+=("trace-cmd")
    command -v python3   &>/dev/null || missing+=("python3")
    [[ ${#missing[@]} -gt 0 ]] && \
        die "Missing dependencies: ${missing[*]}\n  Install on Ubuntu: sudo apt install trace-cmd python3"

    # Search for the FlameGraph repo in common locations
    if [[ -z "$FLAMEGRAPH_DIR" ]]; then
        for d in "$HOME/FlameGraph" "/opt/FlameGraph" "$(pwd)/FlameGraph"; do
            [[ -f "$d/flamegraph.pl" ]] && { FLAMEGRAPH_DIR="$d"; break; }
        done
    fi

    # If still not found, attempt to clone it
    if [[ -z "$FLAMEGRAPH_DIR" || ! -f "$FLAMEGRAPH_DIR/flamegraph.pl" ]]; then
        warn "FlameGraph repo not found; attempting to clone..."
        if command -v git &>/dev/null; then
            git clone --depth=1 https://github.com/brendangregg/FlameGraph.git "$HOME/FlameGraph" \
                && FLAMEGRAPH_DIR="$HOME/FlameGraph" \
                || die "git clone failed. Please clone manually: git clone https://github.com/brendangregg/FlameGraph.git"
        else
            die "git not found. Clone FlameGraph manually: git clone https://github.com/brendangregg/FlameGraph.git"
        fi
    fi
    ok "FlameGraph repo: $FLAMEGRAPH_DIR"
}

check_root() {
    [[ $EUID -eq 0 ]] || die "trace-cmd record requires root privileges. Run with sudo."
}

# -- Step 1: Record traces ----------------------------------------------------
do_record() {
    check_root
    local args=(-p function_graph -o "$TRACE_DAT")

    # Append optional filter arguments
    [[ -n "$FILTER_PID" ]] && args+=(-P "$FILTER_PID")
    for func in $FILTER_FUNCS; do args+=(-g "$func"); done
    for cmd  in $FILTER_CMDS;  do args+=(-c "$cmd");  done

    if [[ ${#CMD_TO_RUN[@]} -gt 0 ]]; then
        # Run the specified command and stop recording when it exits
        info "Recording command: trace-cmd record ${args[*]} -- ${CMD_TO_RUN[*]}"
        trace-cmd record "${args[@]}" -- "${CMD_TO_RUN[@]}"
    else
        # Record for a fixed duration, then send SIGINT to stop
        info "Recording for ${DURATION}s: trace-cmd record ${args[*]}"
        trace-cmd record "${args[@]}" &
        local tpid=$!
        sleep "$DURATION"
        kill -INT "$tpid" 2>/dev/null || true
        wait "$tpid" 2>/dev/null || true
    fi
    ok "Recording done -> $TRACE_DAT ($(du -sh "$TRACE_DAT" | cut -f1))"
}

# -- Step 2: Export text report -----------------------------------------------
do_report() {
    [[ -f "$TRACE_DAT" ]] || die "Trace file not found: $TRACE_DAT"
    info "Exporting function_graph report..."
    trace-cmd report -i "$TRACE_DAT"
}

# -- Step 3: Parse function_graph text -> folded stack format -----------------
parse_to_folded() {
    local infile="$1" outfile="$2"
    info "Parsing function_graph -> folded format..."

    # Locate fg2folded.py: same directory as this script, then PATH
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local parser=""
    if [[ -f "$script_dir/fg2folded.py" ]]; then
        parser="$script_dir/fg2folded.py"
    elif command -v fg2folded.py &>/dev/null; then
        parser="$(command -v fg2folded.py)"
    else
        die "fg2folded.py not found. Place it in the same directory as fg2flame.sh."
    fi

    python3 "$parser" "$infile" "$outfile"
}

# -- Step 4: Render SVG flame graph via flamegraph.pl -------------------------
gen_flamegraph() {
    local folded="$1" svg="$2"
    info "Rendering flame graph SVG..."

    local pl="$FLAMEGRAPH_DIR/flamegraph.pl"
    # Use a cooler color palette when visualizing time; hot palette for call counts
    local color="hot"
    [[ "$WEIGHT_MODE" == "time" ]] && color="aqua"

    perl "$pl" \
        --title "$TITLE" \
        --color "$color" \
        --countname "$([[ $WEIGHT_MODE == time ]] && echo 'microseconds' || echo 'calls')" \
        "$folded" > "$svg"

    local size
    size=$(du -sh "$svg" | cut -f1)
    ok "Flame graph written: $svg ($size)"
    info "Open in browser: firefox $svg   or   chromium $svg"
}

# -- Temporary file management ------------------------------------------------
TMPFILES=()
cleanup() {
    if [[ $KEEP_TEMP -eq 0 ]]; then
        for f in "${TMPFILES[@]}"; do
            [[ -f "$f" ]] && rm -f "$f" && info "Removed temp file: $f"
        done
    else
        [[ ${#TMPFILES[@]} -gt 0 ]] && info "Kept intermediate files: ${TMPFILES[*]}"
    fi
}
trap cleanup EXIT

make_tmpfile() {
    local tmp
    tmp=$(mktemp /tmp/fg2flame.XXXXXX)
    TMPFILES+=("$tmp")
    echo "$tmp"
}

# -- Main entry point ---------------------------------------------------------
main() {
    parse_args "$@"
    check_deps

    local tmp_report tmp_folded

    case "$SUBCMD" in
        record)
            check_root
            do_record

            # Export the binary trace to human-readable text
            tmp_report=$(make_tmpfile)
            info "Exporting function_graph report..."
            trace-cmd report -i "$TRACE_DAT" > "$tmp_report"
            local lines
            lines=$(wc -l < "$tmp_report")
            ok "Report exported: ${lines} lines"

            # Determine folded output path (user-specified or temp)
            if [[ -n "$FOLDED_FILE" ]]; then
                tmp_folded="$FOLDED_FILE"
            else
                tmp_folded=$(make_tmpfile)
            fi

            parse_to_folded "$tmp_report" "$tmp_folded"
            gen_flamegraph "$tmp_folded" "$OUTPUT_SVG"
            ;;

        convert)
            [[ -f "$TRACE_DAT" ]] || die "Trace file not found: $TRACE_DAT"

            tmp_report=$(make_tmpfile)
            info "Exporting function_graph report..."
            trace-cmd report -i "$TRACE_DAT" > "$tmp_report"
            local lines
            lines=$(wc -l < "$tmp_report")
            ok "Report exported: ${lines} lines"

            if [[ -n "$FOLDED_FILE" ]]; then
                tmp_folded="$FOLDED_FILE"
            else
                tmp_folded=$(make_tmpfile)
            fi

            parse_to_folded "$tmp_report" "$tmp_folded"
            gen_flamegraph "$tmp_folded" "$OUTPUT_SVG"
            ;;

        report)
            do_report
            ;;

        *)
            die "Unknown subcommand: $SUBCMD\n  Use -h for help."
            ;;
    esac
}

main "$@"
