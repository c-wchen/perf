#!/bin/bash

#DIR_PATH=`date "+%Y%m%d-%k%M"`
DIR_PATH=`date "+%Y%m%d-%H"`

if [ ! -d "${DIR_PATH}" ]
then
                mkdir ${DIR_PATH}
fi

# attach set
#custom_tid=$(pidof xxx)
custom_pid=$1
proc_name=""
if [ -f  /proc/$custom_pid/comm ]
then
        proc_name=$(basename $(cat /proc/$custom_pid/comm))
fi


if [ ! -z "${proc_name}" ]
then
                echo "[INFO] $DIR_PATH/${proc_name}.perf.data"
                perf record --call-graph dwarf -o $DIR_PATH/${proc_name}.perf.data -t ${custom_pid} sleep 30
fi
