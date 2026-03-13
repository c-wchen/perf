#!/usr/bin/env python3
"""
fg2folded.py — Parse 'trace-cmd report' function_graph output into
               flamegraph-compatible folded stack format.

Usage:
    trace-cmd report -i trace.dat | python3 fg2folded.py > out.folded
    python3 fg2folded.py < report.txt > out.folded
    python3 fg2folded.py report.txt out.folded        # explicit file args

Output is written to stdout when called with no file arguments, or to the
second positional argument when two file arguments are supplied.  This makes
the script composable both as a filter in a pipeline and as a standalone tool.

Algorithm:
  - Maintain a per-thread call stack keyed by (comm, pid).
  - On function entry (opening brace):  push func onto the stack.
  - On inline leaf (semicolon line, entry+exit collapsed):  emit the full
    current stack + func as one folded sample without modifying the stack.
  - On function exit (closing brace):  pop the top func, then emit the full
    stack (including the popped func) as one folded sample.

Emitting on every exit (including non-leaf frames) is intentional: it allows
flamegraph.pl to correctly aggregate widths for all ancestor frames.

Supported trace-cmd report formats:
  Old (no flags field):
    bash-1234  [001]  1.001: funcgraph_entry:                   | sys_read() {
    bash-1234  [001]  1.002: funcgraph_exit:    2.000 us    |   }

  New (flags field between [cpu] and timestamp):
    bash-1234  [001] d..1  1.001: funcgraph_entry:              | sys_read() {
    bash-1234  [001] ....  1.002: funcgraph_exit:    2.000 us | }

  Inline leaf (entry+exit on one line, ends with semicolon):
    bash-1234  [001]  1.003: funcgraph_entry:   0.321 us    |  __fdget_pos();

  Timeout annotation before the pipe:
    bash-1234  [001] d..1  1.004: funcgraph_entry: #### > 1000 us #### | fn() {
"""

import sys
import re
from collections import defaultdict


# ---------------------------------------------------------------------------
# Regular expressions
# ---------------------------------------------------------------------------

# Inline leaf call (entry+exit collapsed on one line): duration us | func();
# Must be tested BEFORE entry_re because both match funcgraph_entry lines.
leaf_re = re.compile(
    r'^\s*(\S+)-(\d+)\s+\[(\d+)\].*funcgraph_entry:.*?([\d.]+) us\s+\|\s+(.+?)\(\)\s*;'
)

# Function entry that opens a new stack frame: | func() {
# .* absorbs optional duration or #### timeout text before the pipe.
entry_re = re.compile(
    r'^\s*(\S+)-(\d+)\s+\[(\d+)\].*funcgraph_entry:.*\|\s+(.+?)\(\)\s*\{'
)

# Function exit that closes the current frame: duration us | }
exit_re = re.compile(
    r'^\s*(\S+)-(\d+)\s+\[(\d+)\].*funcgraph_exit:.*\|\s+\}'
)


# ---------------------------------------------------------------------------
# Parse
# ---------------------------------------------------------------------------

def parse(lines, out):
    """Read function_graph lines and write folded stacks to out."""
    counts = defaultdict(int)
    stacks = {}   # (comm, pid) -> [func, ...]

    total_lines = matched = 0

    for line in lines:
        total_lines += 1

        # Inline leaf: emit current stack + func, do not push/pop
        m = leaf_re.match(line)
        if m:
            comm, pid, func = m.group(1), m.group(2), m.group(5)
            key = (comm, pid)
            stack = stacks.get(key, [])
            counts[';'.join(stack + [func]) if stack else func] += 1
            matched += 1
            continue

        # Function entry: push onto the per-thread call stack
        m = entry_re.match(line)
        if m:
            comm, pid, func = m.group(1), m.group(2), m.group(4)
            stacks.setdefault((comm, pid), []).append(func)
            matched += 1
            continue

        # Function exit: pop and emit the full stack including the popped func
        m = exit_re.match(line)
        if m:
            comm, pid = m.group(1), m.group(2)
            key = (comm, pid)
            if key in stacks and stacks[key]:
                func = stacks[key].pop()
                stack = stacks[key]
                counts[';'.join(stack + [func]) if stack else func] += 1
            matched += 1
            continue

    print(f"[parse] total lines: {total_lines}, matched: {matched}, "
          f"unique stacks: {len(counts)}", file=sys.stderr)

    if len(counts) == 0:
        print("[parse] WARNING: 0 stacks collected. "
              "Check that the input is a valid trace-cmd report.", file=sys.stderr)
        sys.exit(1)

    for stack, cnt in sorted(counts.items(), key=lambda x: -x[1]):
        out.write(f"{stack} {cnt}\n")

    print(f"[parse] done, {len(counts)} unique stacks written.", file=sys.stderr)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    args = sys.argv[1:]

    if len(args) == 0:
        # Pipeline mode: stdin -> stdout
        parse(sys.stdin, sys.stdout)

    elif len(args) == 1:
        # Single file arg: file -> stdout
        with open(args[0], 'r', errors='replace') as f:
            parse(f, sys.stdout)

    elif len(args) == 2:
        # Two file args: infile -> outfile
        with open(args[0], 'r', errors='replace') as fin, \
             open(args[1], 'w') as fout:
            parse(fin, fout)
        print(f"[parse] folded file written: {args[1]}", file=sys.stderr)

    else:
        print("Usage: fg2folded.py [infile [outfile]]", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
