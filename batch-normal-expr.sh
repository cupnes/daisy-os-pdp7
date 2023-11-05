#!/bin/bash

set -ue

# 実験回数
NUM_EXPR=$1

for i in $(seq $NUM_EXPR); do
	printf "i=%03d " $i
	echo -n "[$(date '+%Y-%m-%d %H:%M:%S')] "
	./daisy-os-pdp7.sh 1>expr.log 2>expr.err
	log_dir="$(ls -1d LOG-* | tail -n 1)"
	echo -n $log_dir
	mv expr.log expr.err $log_dir
	echo " [$(date '+%Y-%m-%d %H:%M:%S')]"
done
