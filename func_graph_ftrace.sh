#!/bin/bash

tracefs=`cat /proc/mounts | awk '/tracefs/ { print $2 }' | head -1`
fail() {
	text=$1;

	echo "Error: $text"
	exit -1;
}

cleanup() {
	echo "== cleanup environment =="

	if [ -n "$PIPE_PID" ]; then
		kill -9 "$PIPE_PID" 2>/dev/null
        	wait "$PIPE_PID" 2>/dev/null
    	fi
	if [ -n "$CMD_PID" ]; then
        	kill -9 "$CMD_PID" 2>/dev/null
        	wait "$CMD_PID" 2>/dev/null
    	fi
	
	echo nop > "$tracefs/current_tracer"
        echo > "$tracefs/set_ftrace_filter"
   	echo > "$tracefs/set_ftrace_pid"
        echo > "$tracefs/set_event_pid"
        echo 0 > "$tracefs/options/func_stack_trace"
        echo > "$tracefs/trace"
	echo 0 > "$tracefs/tracing_on"
	echo "== success, cleanup end =="
}

trap cleanup INT TERM EXIT


if [ -z "$tracefs" ]; then
	mount -t tracefs nodev /sys/kernel/tracing || fail "Failed to mount tracefs"
	tracefs="/sys/kernel/tracing"
fi

cd $tracefs || fail "Changing to tracefs directory ($tracefs)";

echo function_graph > current_tracer
echo 1 > options/func_stack_trace # 跟踪函数调用栈
echo $1 > set_graph_function
echo > set_ftrace_filter
echo 0 > options/funcgraph-irqs

cat "$tracefs/trace_pipe" &
PIPE_PID=$!

FILTER="$1"
shift
CMD_ARGS=("$@")

(
	echo $BASHPID > /tmp/.cmd_pidf
	echo $BASHPID > set_ftrace_pid
	echo $BASHPID > set_event_pid
	echo 1 > tracing_on
	exec "${CMD_ARGS[@]}"
) &

sleep 1
CMD_PID=$(cat /tmp/.cmd_pidf)

wait "$CMD_PID"

#cleanup
