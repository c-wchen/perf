#!/bin/bash

#DIR_PATH=`date "+%Y%m%d-%k%M"`
DIR_PATH=`date "+%Y%m%d-%H"`

if [ ! -d "${DIR_PATH}" ]
then
                mkdir ${DIR_PATH}
fi

# cmd map
declare -A cmd_map;
cmd_map['DD_DIRECT_WR_1MBS_1024CNT']="dd if=/dev/urandom of=/mnt/ext4_disk/$(uuidgen) bs=1024M count=1 oflag=direct"
cmd_map['DD_DIRECT_WR_1MBS_1024CNT_NVMEDISK']="dd if=/dev/urandom of=/dev/nvme0n1 bs=1M count=1024 oflag=direct"
cmd_map['DD_DIRECT_WR_8KBS_40960CNT_NVMEDISK']="dd if=/dev/urandom of=/dev/nvme0n1 bs=8K count=40960 oflag=direct"
cmd_map['DD_DIRECT_WR_16KBS_409600CNT_NVMEDISK']="dd if=/dev/urandom of=/dev/nvme0n1 bs=16K count=409600 oflag=direct"

echo "===================================================================="
echo "cmd choose:"
for key in ${!cmd_map[@]}
do
        echo "  $key"
done
echo "===================================================================="
echo ""

proc_name=$1
cmdline=${cmd_map[$proc_name]}


if [ ! -z "${cmdline}" ]
then
        echo "[INFO] exec cmd ${cmdline}"
        perf record --call-graph dwarf -o $DIR_PATH/${proc_name}.perf.data -- $cmdline
else
        echo "[ERROR] cmd input error." 
fi
