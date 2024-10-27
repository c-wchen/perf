#!/bin/bash

#DIR_PATH=`date "+%Y%m%d-%k%M"`
DIR_PATH=`date "+%Y%m%d-%H"`

if [ ! -d "${DIR_PATH}" ]
then
	mkdir ${DIR_PATH}
fi

# attach set
#custom_tid=$(pidof xxx)
custom_pid=101
proc_name=$(ps -p $custom_pid | tail -n 1 | awk '{print $4}')

echo "$DIR_PATH/${proc_name}.perf.data"

if [ ! -z "${proc_name}" ]
then
	perf record --call-graph dwarf -o $DIR_PATH/${proc_name}.perf.data -p ${custom_pid} sleep 30
fi
