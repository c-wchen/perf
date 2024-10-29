#!/bin/bash

#DIR_PATH=`date "+%Y%m%d-%k%M"`
DIR_PATH=`date "+%Y%m%d-%H"`

if [ ! -d "${DIR_PATH}" ]
then
                mkdir ${DIR_PATH}
fi

# attach set
custom_pid=$1
proc_name=""
thread=true
attach_time=30

if [ -f  /proc/$custom_pid/comm ]
then
        proc_name=$(basename $(cat /proc/$custom_pid/comm))
fi


if [ ! -z "${proc_name}" ]
then
                echo "[INFO] $DIR_PATH/${proc_name}.perf.data is_thread: $thread"
                if [ "$thread" = true ]
                then
                        perf record --call-graph dwarf -o $DIR_PATH/${proc_name}.perf.data -t ${custom_pid} sleep $attach_time
                else
                        perf record --call-graph dwarf -o $DIR_PATH/${proc_name}.perf.data -p ${custom_pid} sleep $attach_time
                fi
fi
