#!/bin/bash

set -ue

ENV_CYCLE_DIGITS=8	# 桁数

LOG_DIR=$1
ENV_CYCLE_NUM=$2
cd $LOG_DIR

# 桁拡張
# 説明:
# - 足りない上位桁を0で埋めた値を標準出力へ出力する
# 引数:
# 1. 桁数
# 2. 値
# 備考:
# - 第1引数は10進数で指定する
extend_digit() {
	local num_digits=$1
	local val=$2
	printf "%0${num_digits}d" $val
}

# 8進数計算
# 説明:
# - 指定された計算式を8進数で計算した結果を標準出力へ出力する
# 引数:
# 1..N 計算式
calc_oct() {
	bc <<< "obase=8;ibase=8;$*"
}

ENV_CYCLE_NUM_EX=$(extend_digit $ENV_CYCLE_DIGITS $ENV_CYCLE_NUM)
TAD_OPCODE=340000
CONST_MINUS_1_TWOS_COMP_ADDR=$(grep -E '^CONST_MINUS_1_TWOS_COMP_ADDR=[0-9]+$' daisy-os-pdp7.sh | cut -d'=' -f2)
WHITE_DAISY_INST=$(calc_oct $TAD_OPCODE + $CONST_MINUS_1_TWOS_COMP_ADDR)

### BAVファイルと、その中のバイナリ生物(デイジー)の先頭の行番号を与えると
### そのデイジーの色('white'/'black')を標準出力へ出力する
### 引数:
### - 第1引数: 行番号(1始まり)
### - 第2引数: BAVファイルのパス
check_daisy_color_in_bav() {
	local n=$1
	local bav_file=$2

	local first_inst=$(sed -n "$((n + 5))p" $bav_file)
	if [ "$first_inst" = "$WHITE_DAISY_INST" ]; then
		echo 'white'
	else
		echo 'black'
	fi
}
### 本体
post_shell_commands_by_cycle() {
	# ログを解析
	# バイナリ生物領域を可視化する
	# - 白いデイジーの領域を白色で
	# - 黒いデイジーの領域を黒色で
	# - バイナリ生物が居ない領域を灰色で示す

	# バイナリ生物領域のダンプファイルから値の部分のみを抽出(BAVファイル)
	awk '{print $2}' ${ENV_CYCLE_NUM_EX}.BA >${ENV_CYCLE_NUM_EX}.BAV

	# PGM画像を生成する
	{
		echo 'P2'

		local width=64
		local height=64
		echo "$width $height"

		local max_intensity=2
		echo $max_intensity

		local bav_file="${ENV_CYCLE_NUM_EX}.BAV"
		local state='none'
		local width_count=0
		local i
		for i in $(seq 4096); do
			local v=$(sed -n "${i}p" $bav_file)

			case "$state" in
			'none')
				case "$v" in
				'713130')
					case "$(check_daisy_color_in_bav $i $bav_file)" in
					'white')
						echo -n 2
						state='white'
						;;
					'black')
						echo -n 0
						state='black'
						;;
					esac
					;;
				*)
					echo -n 1
					;;
				esac
				;;
			'white')
				echo -n 2
				if [ "$v" = '713137' ]; then
					state='none'
				fi
				;;
			'black')
				echo -n 0
				if [ "$v" = '713137' ]; then
					state='none'
				fi
				;;
			esac

			width_count=$((width_count + 1))
			if [ $width_count -lt $width ]; then
				echo -n ' '
			else
				echo
				width_count=0
			fi
		done
	} >${ENV_CYCLE_NUM_EX}.pgm
}

post_shell_commands_by_cycle
