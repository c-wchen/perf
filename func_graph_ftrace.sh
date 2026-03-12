#!/bin/bash

TRACEFS=`cat /proc/mounts | awk '/tracefs/ { print $2 }' | head -1`
fail() {
	text=$1;

	echo "Error: $text"
	exit -1;
}

CPID_FILE=/tmp/.cmd_pidf
TRACE_FILE=/tmp/.trace_`date +"%Y%m%d%H%M%S"`

cleanup() {
	echo "== cleanup environment =="

	if [ -n "$CMD_PID" ]; then
		kill -9 "$CMD_PID" 2>/dev/null
		wait "$CMD_PID" 2>/dev/null
	fi

	cat $TRACEFS/trace > $TRACE_FILE
	
	echo nop > $TRACEFS/current_tracer
	echo > $TRACEFS/set_ftrace_filter
   	echo > $TRACEFS/set_ftrace_pid
	echo > $TRACEFS/set_event_pid
	echo > $TRACEFS/trace
	echo 0 > $TRACEFS/options/func_stack_trace

	echo 0 > $TRACEFS/tracing_on

	echo "== success, cleanup end, trace output:$TRACE_FILE =="
}

trap cleanup INT TERM EXIT


if [ -z "$TRACEFS" ]; then
	mount -t tracefs nodev /sys/kernel/tracing || fail "Failed to mount tracefs"
	tracefs="/sys/kernel/tracing"
fi

cd $TRACEFS || fail "Changing to tracefs directory ($TRACEFS)";

echo function_graph > $TRACEFS/current_tracer
echo 1 > $TRACEFS/options/func_stack_trace # 跟踪函数调用栈
echo $1 > $TRACEFS/set_graph_function
echo 0 > $TRACEFS/options/funcgraph-irqs

FILTER="$1"
shift
CMD_ARGS=("$@")

(
	echo $BASHPID > $CPID_FILE
	echo $BASHPID > $TRACEFS/set_ftrace_pid
	echo 1 > tracing_on
	exec "${CMD_ARGS[@]}"
) &

sleep 1
CMD_PID=$(cat $CPID_FILE)

wait "$CMD_PID"

#cleanup
