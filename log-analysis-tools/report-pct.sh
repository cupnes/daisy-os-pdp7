#!/bin/bash

set -ue

{
	for log_dir in $(ls -d LOG-*); do
		sorted_err_file=${log_dir}/sorted-err.txt
		pct50=$(sed -n '50p' $sorted_err_file)
		pct90=$(sed -n '90p' $sorted_err_file)
		pct95=$(sed -n '95p' $sorted_err_file)
		echo "${log_dir},${pct50},${pct90},${pct95}"
	done
} >report-pct.csv
