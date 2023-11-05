#!/bin/bash

set -ue

for log_dir in $(ls -d LOG-*); do
	echo "log_dir=$log_dir"
	for i in $(seq 1 100); do
		i_8digits=$(printf "%08d" $i)
		st_file=${log_dir}/${i_8digits}.ST
		st=$(head -n 1 $st_file | awk '{print $2}')
		echo $st
	done >${log_dir}/result-st.txt
done
