#!/bin/bash

set -ue

OUTPUT_FILE_NAME='report2.csv'

if [ $# -eq 1 ]; then
	LOG_DIR=$1
else
	LOG_DIR=$(ls -1d LOG-* | tail -n 1)
fi
cd $LOG_DIR

# 8進数計算
# 説明:
# - 指定された計算式を8進数で計算した結果を標準出力へ出力する
# 引数:
# 1..N 計算式
calc_oct() {
	bc <<< "obase=8;ibase=8;$*"
}

TAD_OPCODE=340000
CONST_MINUS_1_TWOS_COMP_ADDR=$(grep -E '^CONST_MINUS_1_TWOS_COMP_ADDR=[0-9]+$' daisy-os-pdp7.sh | cut -d'=' -f2)
WHITE_DAISY_INST=$(calc_oct $TAD_OPCODE + $CONST_MINUS_1_TWOS_COMP_ADDR)
OFFSET_TO_INST_LIST=$(grep -E 'echo .*OFFSET_TO_INST_LIST' daisy-os-pdp7.sh | tr -d '"' | rev | cut -d' ' -f1 | rev)

# 指定されたBAファイルの指定された行番号から始まるバイナリ生物が
# 何色のデイジーかを標準出力へ出力する
check_daisy_color() {
	local ba_file=$1
	local line_num=$2
	local inst=$(sed -n "$((line_num + OFFSET_TO_INST_LIST))p" $ba_file | awk '{print $2}')
	if [ "$inst" = "$WHITE_DAISY_INST" ]; then
		echo 'white'
	else
		echo 'black'
	fi
}

echo '環境周期,地表温度,個体数,白デイジー個体数,黒デイジー個体数' >${OUTPUT_FILE_NAME}

for f in $(ls *.ST); do
	i=$(echo $f | cut -d'.' -f1)

	st=$(sed -n 1p $f | awk '{print $2}')
	if [ $st -ge 131072 ]; then
		st=-$((262144 - $st))
	fi

	num_bbs=$(grep -w '713130' ${i}.BA | wc -l)

	num_white=0
	num_black=0
	for bbs_idx in $(grep -nw '713130' ${i}.BA | cut -d':' -f1); do
		daisy_color=$(check_daisy_color ${i}.BA $bbs_idx)
		if [ "$daisy_color" = 'white' ]; then
			num_white=$((num_white + 1))
		else
			num_black=$((num_black + 1))
		fi
	done

	echo "$i,$st,${num_bbs},${num_white},${num_black}"
done >>${OUTPUT_FILE_NAME}
