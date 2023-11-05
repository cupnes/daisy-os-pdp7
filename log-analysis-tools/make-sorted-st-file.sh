#!/bin/bash

set -ue

for log_dir in $(ls -d LOG-*); do
	echo "log_dir=$log_dir"
	result_st_file=${log_dir}/result-st.txt
	sort -n $result_st_file >${log_dir}/sorted-st.txt
done
