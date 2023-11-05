#!/bin/bash

set -ue

for log_dir in $(ls -d LOG-*); do
	echo "log_dir=$log_dir"
	result_err_file=${log_dir}/result-err.txt
	sort -n $result_err_file >${log_dir}/sorted-err.txt
done
