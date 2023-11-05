#!/bin/bash

set -ue

for log_dir in $(ls -d LOG-*); do
	echo "log_dir=$log_dir"
	result_st_file=${log_dir}/result-st.txt
	for st in $(cat $result_st_file); do
		sub=$(bc <<< "$st - 20")
		echo $sub | tr -d '-'
	done >${log_dir}/result-err.txt
done
