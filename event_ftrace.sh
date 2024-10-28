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

echo 1 > events/enable
echo function > current_tracer

set_option() {
	file=$1
	if [ -f options/$file ]; then
		echo 1 > options/$file
	fi
}

set_option "event-fork"
set_option "function-fork"

exec "$@"

