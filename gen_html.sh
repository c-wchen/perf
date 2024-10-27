#!/bin/bash

gen_dir=$1
fgraph_dir=$PWD/FlameGraph
perf_suffix=".perf.data"

flame_graph() {
	perf_name=$gen_dir/$(basename $1 ${perf_suffix})
	perf script -i $1 > ${perf_name}.unfold
	$fgraph_dir/stackcollapse-perf.pl ${perf_name}.unfold > ${perf_name}.folded
	$fgraph_dir/flamegraph.pl ${perf_name}.folded > ${perf_name}.html
	rm -rf ${perf_name}.unfold
	rm -rf ${perf_name}.folded
}


for i in $(find ${gen_dir} -type f -name "*${perf_suffix}")
do
	echo "[INFO] Start processing perf $i"
	flame_graph $i
done
