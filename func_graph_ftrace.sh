#!/bin/bash

tracefs=`cat /proc/mounts | awk '/tracefs/ { print $2 }' | head -1`

fail() {
	text=$1;

	echo "Error: $text"
	exit -1;
}

if [ -z "$tracefs" ]; then
	mount -t tracefs nodev /sys/kernel/tracing || fail "Failed to mount tracefs"
	tracefs="/sys/kernel/tracing"
fi

cd $tracefs || fail "Changing to tracefs directory ($tracefs)";

echo $$ > set_ftrace_pid
echo $$ > set_event_pid


echo function_graph > current_tracer
echo 1 > options/func_stack_trace # 跟踪函数调用栈

# echo 0 > options/funcgraph-irqs

echo $1 > set_ftrace_filter

echo 1 > tracing_on
# exec "$@"
exec "$2"


echo 0 > tracing_on
