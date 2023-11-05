#!/bin/bash

# 出てくる値は基本的に全て8進数

# PDP7_CMD=pdp7-debug ./daisy-os-pdp7.sh
# のように実行すると実行時にPDP7_CMD変数を上書きできる
if [ -z "$PDP7_CMD" ]; then
	PDP7_CMD=pdp7
fi

set -ue
# set -uex

#
# 定数・関数定義
#

# 生成するファイル名
SIMH_FILE=daisy-os-pdp7.simh
MAP_FILE=daisy-os-pdp7.map

# 一時ファイル名
TMP_FILE=${SIMH_FILE}.tmp
PRESED_FILE=${SIMH_FILE}.pre.sed

# 周期処理を停止させるファイル名
STOP_FILE='stop'

# ログディレクトリ名を決め、作成する
# ※ examineコマンドでファイル出力する際にディレクトリ名やファイル名が大文字でないとダメ
LOG_DIR="LOG-$(date '+%Y%m%d%H%M%S')"
mkdir $LOG_DIR

# ログディレクトリへ自身とconfig.shをバックアップ
cp $0 config.sh $LOG_DIR

# 環境周期が今何周期目か
ENV_CYCLE_NUM=0
ENV_CYCLE_DIGITS=8	# 桁数

# 基数変換
# 説明:
# - 基数変換を行い、その結果を標準出力へ出力する
# 引数:
# 1. 変換元の基数
# 2. 変換先の基数
# 3. 変換する値
# 備考:
# - 第1・第2引数で指定する基数自体は10進数で指定する
conv_radix() {
	local src_radix=$1
	local dst_radix=$2
	local src_val=$3
	bc <<< "obase=${dst_radix};ibase=${src_radix};$src_val"
}

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

# メモリマップ
# ※ 動的にアドレスが決まるものはここでは仮の値として'dummy'を設定している
# ※ JMP I命令のオペランドの値域が0o000000〜0o017777である都合上、
# 　 0o020000以降に関数を作ることはできない
## システム: プログラム領域(0o000020〜0o001074)
SYS_AREA_BEGIN=000020	# 開始アドレス
GEN_RAND_FUNC_ADDR='dummy'
EVAL_FUNC_ADDR='dummy'
IS_MUTATE_FUNC_ADDR='dummy'
SELECT_MUTATION_TYPE_FUNC_ADDR='dummy'
DIVISION_FUNC_ADDR='dummy'
CYCLE_FUNC_ADDR='dummy'
SETUP_FUNC_ADDR='dummy'
ENV_CYCLE_FUNC_ADDR='dummy'
SETUP_AND_HLT_CODE_ADDR='dummy'
ENV_CYCLE_AND_HLT_CODE_ADDR='dummy'
SETUP_AND_INF_ENV_CYCLE_CODE_ADDR='dummy'
SYS_AREA_NEXT=$SYS_AREA_BEGIN	# 次に配置可能なアドレス(何か配置する毎に進める)
## システム: 定数領域(0o001075〜0o001131)
CONST_MINUS_100_DEC_TWOS_COMP_ADDR=001075
CONST_MINUS_50_DEC_TWOS_COMP_ADDR=001076
CONST_MINUS_10_DEC_TWOS_COMP_ADDR=001077
CONST_MINUS_1_TWOS_COMP_ADDR=001100
CONST_1_ADDR=001101
CONST_2_ADDR=001102
CONST_3_ADDR=001103
CONST_6_ADDR=001104
CONST_10_DEC_ADDR=001105
CONST_50_DEC_ADDR=001106
CONST_100_DEC_ADDR=001107
JMP_I_OPCODE_ADDR=001110
JMP_I_OPCODE_MASK_ADDR=001111
JMS_OPCODE_ADDR=001112
MASK_FOR_LAW_ADDR=001113
BINBIO_ATTR_SIZE_ADDR=001114
OFFSET_TO_ENERGY_ADDR=001115
OFFSET_TO_FITNESS_ADDR=001116
OFFSET_TO_NUM_INST_ADDR=001117
OFFSET_TO_RET_ADDR_ADDR=001120
OFFSET_TO_INST_LIST_ADDR=001121
BINBIO_BEGIN_SIG_ADDR=001122
BINBIO_INITIAL_ENERGY_ADDR=001123
CONSTANT_ENERGY_CONSUMPTION_ADDR=001124
DIVISION_COST_ADDR=001125
BINBIO_END_SIG_ADDR=001126
INST_CAND_TBL_BEGIN_ADDR=001127
INST_CAND_TBL_MASK_ADDR=001130
BINBIO_AREA_BEGIN_ADDR=001131
## システム: 変数領域(0o001132〜)
RAND_VAL_ADDR=001132
CUR_BINBIO_ADDR=001133
DIVIDED_TO_NEXT_ADDR=001134
## システム: tmp領域(〜0o005777)
SYS_TMP_10=005766
SYS_TMP_9=005767
SYS_TMP_8=005770
SYS_TMP_7=005771
SYS_TMP_6=005772
SYS_TMP_5=005773
SYS_TMP_4=005774
SYS_TMP_3=005775
SYS_TMP_2=005776
SYS_TMP_1=005777
## 実験固有: 実験固有領域(0o006000〜0o007677)
## システム: 命令候補テーブル(0o007700〜0o007777)
## 領域としてこれだけ確保しているが、
## 実際に使用するサイズはシェル変数INST_CAND_TBL_MASKによる
INST_CAND_TBL_BEGIN=007700	# 命令候補テーブル(開始)
INST_CAND_TBL_END=007777	# 命令候補テーブル(終了)
## システム: バイナリ生物領域(0o010000〜0o017777)
BINBIO_AREA_BEGIN=010000	# 開始アドレス
BINBIO_AREA_END=017777	# 終了アドレス

# バイナリ生物のデータ構造について
## ヘッダサイズ
BINBIO_HEADER_SIZE=4
## 属性サイズ
BINBIO_ATTR_SIZE=6
## シグネチャ
BINBIO_BEGIN_SIG=713130
BINBIO_END_SIG=713137

# JMP I命令
## オペコード
JMP_I_OPCODE=620000
## オペコード部分を抽出するマスク
JMP_I_OPCODE_MASK=760000

# 指定されたバイナリ生物のリターン命令を生成
# 説明:
# - 先頭アドレスで指定されたバイナリ生物からリターンするJMP I命令を生成し
#   6桁の8進数で標準出力へ出力する
# 引数:
# - 第1引数: バイナリ生物のアドレス
gen_return_inst() {
	local binbio_addr=$1
	local func_addr=$(calc_oct $binbio_addr + $BINBIO_HEADER_SIZE)
	local opcode_bin=$(bc <<< "obase=2;ibase=8;$JMP_I_OPCODE" | cut -c-5)
	local oprand_bin=$(extend_digit 13 $(conv_radix 8 2 $func_addr))
	conv_radix 2 8 "${opcode_bin}${oprand_bin}"
}

# JMS命令
## オペコード
JMS_OPCODE=100000

# バイナリ生物共通の初期値
## エネルギー(10進指定)
BINBIO_INITIAL_ENERGY_DEC=1000

#
# simhスクリプト生成
#

# ラベルを設定する
# 具体的には、指定されたラベル文字列を、
# このシェル関数を置いた場所の直後の命令のアドレスで置換するsedの式を
# プリプロセス用に出力する
# 引数:
# - 第1引数: ラベル文字列
set_label() {
	local label=$1
	echo "# PRESED: s/$label/$SYS_AREA_NEXT/"
}


# $SYS_AREA_NEXTへ機械語を配置するdepositコマンドを出力しアドレスを進める
dm() {
	echo "d -m $SYS_AREA_NEXT $*"
	SYS_AREA_NEXT=$(calc_oct $SYS_AREA_NEXT + 1)
}

# 実験に依存する設定や関数をロード
. config.sh

# 一旦ファイルを空にする
echo -n >$TMP_FILE

# 初期バイナリ生物を配置する
{
	setup_initial_binbio
} >>$TMP_FILE

# 汎用関数
## 乱数を生成する
## 引数&戻り値:
## - RAND_VAL_ADDR
##   - リターン時、ACレジスタにも生成した乱数が設定されている
## 内容:
## - 線形合同法で乱数を生成する
##   (RAND_VAL_ADDRの値) = 定数5 * (RAND_VAL_ADDRの値) + 定数3
{
	# 関数アドレスを変数へ設定
	GEN_RAND_FUNC_ADDR=$SYS_AREA_NEXT

	# 戻り先アドレスが書かれる領域
	SYS_AREA_NEXT=$(calc_oct $SYS_AREA_NEXT + 1)

	# 変数RAND_VALをACレジスタへロード
	dm lac $RAND_VAL_ADDR

	# AC * 5を計算し、上位18ビットをACレジスタへ下位18ビットをMQレジスタへ設定
	dm mul
	echo "d $SYS_AREA_NEXT 5"
	SYS_AREA_NEXT=$(calc_oct $SYS_AREA_NEXT + 1)

	# ACレジスタへMQレジスタの値を上書き
	dm lacq

	# ACレジスタ += 3
	dm add $CONST_3_ADDR

	# ACレジスタの値を変数RAND_VALへ設定
	dm dac $RAND_VAL_ADDR

	# リターン
	dm jmp i $GEN_RAND_FUNC_ADDR
} >>$TMP_FILE

# 評価関数
# 戻り値:
# - ACレジスタ: 適応度(0〜100)
{
	# 関数アドレスを変数へ設定
	EVAL_FUNC_ADDR=$SYS_AREA_NEXT

	# 戻り先アドレスが書かれる領域
	SYS_AREA_NEXT=$(calc_oct $SYS_AREA_NEXT + 1)

	# 実験に応じた処理を使用する
	eval_func

	# リターン
	dm jmp i $EVAL_FUNC_ADDR
} >>$TMP_FILE

# 突然変異するか否かを判定する関数
# 戻り値:
# - ACレジスタ:
#   - 1: 突然変異する
#   - 0: 突然変異しない
# 実装上の注意:
# - tmp領域1,2は書き換えないこと
## 「100 - 適応度」を突然変異確率とする
{
	# 関数アドレスを変数へ設定
	IS_MUTATE_FUNC_ADDR=$SYS_AREA_NEXT

	# 戻り先アドレスが書かれる領域
	SYS_AREA_NEXT=$(calc_oct $SYS_AREA_NEXT + 1)

	# 突然変異確率(100 - 適応度)を算出しACレジスタへ設定
	## 自身のアドレスをACレジスタへ取得
	dm lac $CUR_BINBIO_ADDR
	## ACレジスタへ適応度までのオフセットを加算
	dm add $OFFSET_TO_FITNESS_ADDR
	## tmp領域3へACレジスタの値(自身の適応度のアドレス)を設定
	dm dac $SYS_TMP_3
	## ACレジスタへtmp領域3に書かれているアドレスが指す先の値(自身の適応度)を取得
	dm lac i $SYS_TMP_3
	## ACレジスタの値(自身の適応度)を2の補数表現の負の値へ変換
	dm cma
	dm tad $CONST_1_ADDR
	## ACレジスタの値へ100(10進数)を加算
	dm tad $CONST_100_DEC_ADDR

	# ACレジスタ(突然変異確率) == 0?
	dm sza
	## (ACレジスタ != 0の場合)「0(突然変異しない)を返す」処理を飛ばす
	dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
	## (ACレジスタ == 0の場合)
	{
		# 0(突然変異しない)を返す
		## ACレジスタは既に0なのでこのままリターンする
		dm jmp i $IS_MUTATE_FUNC_ADDR
	}

	# tmp領域3へACレジスタの値(突然変異確率)を設定
	dm dac $SYS_TMP_3

	# 1〜100の間で乱数を算出しACレジスタへ設定
	## ACレジスタへ乱数を取得
	dm jms $GEN_RAND_FUNC_ADDR
	## MQレジスタへACレジスタの値を設定
	dm lmq
	## Lレジスタをクリア
	dm cll
	## ACレジスタをクリア
	dm cla
	## ((AC << 18) + MQ) / 100(10進数)の商をMQレジスタへ、余りをACレジスタへ設定
	dm div
	echo "d -d $SYS_AREA_NEXT 100"
	SYS_AREA_NEXT=$(calc_oct $SYS_AREA_NEXT + 1)
	## ACレジスタへ1を加算
	dm add $CONST_1_ADDR

	# ACレジスタ(1〜100の間の乱数) <= tmp領域3(突然変異確率)?
	# (これが成立する場合、突然変異する)
	## ACレジスタ = tmp領域3 - ACレジスタ
	### ACレジスタの値を2の補数表現の負の値へ変換
	dm cma
	dm tad $CONST_1_ADDR
	### ACレジスタ += tmp領域3
	dm tad $SYS_TMP_3
	## ACレジスタ < 0?
	dm sma
	## (ACレジスタ >= 0の場合)「1(突然変異する)を返す」へジャンプ
	dm jmp $(calc_oct $SYS_AREA_NEXT + 3)
	## (ACレジスタ < 0の場合)
	{
		# 0(突然変異しない)を返す(2ワード)
		## ACレジスタをクリア
		dm cla
		## リターン
		dm jmp i $IS_MUTATE_FUNC_ADDR
	}

	# 1(突然変異する)を返す
	## ACレジスタへ1を設定
	dm lac $CONST_1_ADDR
	## リターン
	dm jmp i $IS_MUTATE_FUNC_ADDR
} >>$TMP_FILE

# 突然変異タイプを決め、それを示す値として元サイズとの差を返す関数
# 戻り値:
# - ACレジスタ: 元サイズとの差
#   -  1: 追加
#   -  0: 変更
#   - -1: 削除
# - tmp領域5: 自身の命令数のアドレス
# 実装上の注意:
# - 元サイズとの差は、負の数を1の補数で表す
# - tmp領域1〜3は書き換えないこと
{
	# 関数アドレスを変数へ設定
	SELECT_MUTATION_TYPE_FUNC_ADDR=$SYS_AREA_NEXT

	# 戻り先アドレスが書かれる領域
	SYS_AREA_NEXT=$(calc_oct $SYS_AREA_NEXT + 1)

	# tmp領域5へ自身の命令数のアドレスを設定
	## 自身のアドレスをACレジスタへ取得
	dm lac $CUR_BINBIO_ADDR
	## ACレジスタへ機械語命令数までのオフセットを加算
	dm add $OFFSET_TO_NUM_INST_ADDR
	## tmp領域5へACレジスタの値(自身の命令数のアドレス)を設定
	dm dac $SYS_TMP_5

	# 実験に応じた処理を使用する
	select_mutation_type
} >>$TMP_FILE

# 増殖処理を実施する関数
# 参照されるレジスタ・定数・変数:
# - ACレジスタ: 「自身のエネルギー - 増殖コスト」の結果(0以上)
# - tmp領域2: 自身のエネルギーのアドレス
# 変更されるレジスタ・変数:
# - ACレジスタ: 作業用
# 戻り値:
# - ACレジスタ: 増殖できた(=1)か否(=0)か
{
	# 関数アドレスを変数へ設定
	DIVISION_FUNC_ADDR=$SYS_AREA_NEXT

	# 戻り先アドレスが書かれる領域
	SYS_AREA_NEXT=$(calc_oct $SYS_AREA_NEXT + 1)

	# ACレジスタの値をtmp領域1へ退避
	dm dac $SYS_TMP_1

	# この時点でのtmp領域の使用状況
	# - tmp領域1: 「自身のエネルギー - 増殖コスト」の結果
	# - tmp領域2: 自身のエネルギーのアドレス

	# 「突然変異するか否か」と「新たに生まれるバイナリ生物と元生物のサイズ差」をとりあえず(※)決め、
	# それぞれtmp領域3とtmp領域4へ設定
	# ※ 本当にそれができるかは「そのサイズのメモリを確保できるか」等で後々決まるが、
	# 　 だめだったらその他の方式へ切り替える
	# - 突然変異する → 1をtmp領域3へ設定
	#   - 追加 → サイズ差1[ワード]をtmp領域4へ設定
	#   - 変更 → サイズ差0[ワード]をtmp領域4へ設定
	#   - 削除 → サイズ差-1[ワード]をtmp領域4へ設定
	# - 突然変異しない → 0をtmp領域3へ設定
	#   → サイズ差0[ワード]をtmp領域4へ設定
	## 突然変異するか否かを取得し分岐
	### 突然変異するか否かを判定する関数を呼び出す
	dm jms $IS_MUTATE_FUNC_ADDR
	### ACレジスタ == 0の時、次の命令をスキップ
	dm sza
	### (ACレジスタ != 0の時)突然変異する場合へジャンプ
	dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
	### (ACレジスタ == 0の時)突然変異しない場合へジャンプ
	dm jmp $(calc_oct $SYS_AREA_NEXT + 5)
	{
		# 突然変異する場合(4ワード)

		# tmp領域3へ1(突然変異する)を設定
		# ※ この時、ACレジスタは1
		dm dac $SYS_TMP_3

		# 突然変異タイプを決め、tmp領域4へ元サイズとの差を設定(2ワード)
		## 突然変異タイプを決め、それを示す値として元サイズとの差を返す関数を呼び出す
		dm jms $SELECT_MUTATION_TYPE_FUNC_ADDR
		## 戻り値をtmp領域4へ設定
		dm dac $SYS_TMP_4

		# 突然変異しない場合を飛ばす
		dm jmp $(calc_oct $SYS_AREA_NEXT + 6)
	}
	{
		# 突然変異しない場合(5ワード)
		# ※ この時、ACレジスタは0

		# tmp領域3へ0(突然変異しない)を設定
		dm dac $SYS_TMP_3

		# tmp領域4へ元サイズとの差として0を設定
		dm dac $SYS_TMP_4

		# 後で使うのでtmp領域5へ自身の命令数のアドレスを設定
		## 自身のアドレスをACレジスタへ取得
		dm lac $CUR_BINBIO_ADDR
		## ACレジスタへ機械語命令数までのオフセットを加算
		dm add $OFFSET_TO_NUM_INST_ADDR
		## tmp領域5へACレジスタの値(自身の命令数のアドレス)を設定
		dm dac $SYS_TMP_5
	}

	# この時点でのtmp領域の使用状況
	# - tmp領域1: 「自身のエネルギー - 増殖コスト」の結果
	# - tmp領域2: 自身のエネルギーのアドレス
	# - tmp領域3: 突然変異するか否か
	# - tmp領域4: 新たに生まれるバイナリ生物と元とのサイズ差
	# - tmp領域5: 自身の命令数のアドレス

	# 新たに生まれるバイナリ生物を配置するために必要なサイズを算出
	# (現バイナリ生物のサイズとtmp領域4の値の和)
	## ACレジスタへtmp領域5に設定されているアドレスが指す先の値
	## (自身の命令数)を取得
	dm lac i $SYS_TMP_5
	## ACレジスタへtmp領域4の値を加算
	## (これが新たに生まれるバイナリ生物の機械語命令列のサイズ)
	dm add $SYS_TMP_4
	## ACレジスタへ属性サイズを加算
	## (これが新たに生まれるバイナリ生物を配置するために必要なサイズ)
	dm add $BINBIO_ATTR_SIZE_ADDR

	# 算出したサイズをtmp領域6へ保存
	dm dac $SYS_TMP_6

	# この時点でのtmp領域の使用状況
	# - tmp領域1: 「自身のエネルギー - 増殖コスト」の結果
	# - tmp領域2: 自身のエネルギーのアドレス
	# - tmp領域3: 突然変異するか否か
	# - tmp領域4: 新たなバイナリ生物と元とのサイズ差
	# - tmp領域5: 自身の命令数のアドレス
	# - tmp領域6: 新たなバイナリ生物のサイズ

	# 自身の前後でメモリ確保
	# 前提: tmp領域5に自身の機械語命令数のアドレスが設定されている
	# この一連の処理のアウトプット:
	# - tmp領域5: 確保した領域の先頭アドレス
	# ※ 確保できなかった場合はその時点でリターン
	## 自身の後に必要なサイズの空きがあるか確認
	### 自身の直後のアドレスを算出
	#### ACレジスタへ自身の命令数を取得
	dm lac i $SYS_TMP_5
	#### ACレジスタへ属性サイズを加算
	#### (これが自身のデータ構造のサイズ)
	dm add $BINBIO_ATTR_SIZE_ADDR
	#### 算出したサイズをtmp領域5へ保存
	dm dac $SYS_TMP_5
	#### 自身のアドレスをACレジスタへ取得
	dm lac $CUR_BINBIO_ADDR
	#### ACレジスタへtmp領域5の値(自身のサイズ)を加算
	#### (これが自身の直後のアドレス)
	dm add $SYS_TMP_5
	#### 算出したアドレスをtmp領域5へ保存
	dm dac $SYS_TMP_5
	#### 算出したアドレスをtmp領域7へも保存
	dm dac $SYS_TMP_7
	### tmp領域6の値(新たに必要なサイズ)をtmp領域8へもコピー
	dm lac $SYS_TMP_6
	dm dac $SYS_TMP_8

	# この時点でのtmp領域の使用状況
	# - tmp領域1: 「自身のエネルギー - 増殖コスト」の結果
	# - tmp領域2: 自身のエネルギーのアドレス
	# - tmp領域3: 突然変異するか否か
	# - tmp領域4: 新たなバイナリ生物と元とのサイズ差
	# - tmp領域5: 自身の直後のアドレス(自身の直後が空いていると分かった時のために保存しておく)
	# - tmp領域6: 新たなバイナリ生物のサイズ(自身の直前を調べる必要が出てきた時のために保存しておく)
	# - tmp領域7: 自身の直後のアドレス(以降の処理でインクリメントしていく)
	# - tmp領域8: 新たなバイナリ生物のサイズ(以降の処理でデクリメントしていく)

	### 自身の直後の新たに必要なサイズ分の領域に開始シグネチャが無い事を確認
	#### tmp領域7 == バイナリ生物領域終了アドレス?
	dm law $BINBIO_AREA_END
	dm and $MASK_FOR_LAW_ADDR
	dm sad $SYS_TMP_7
	#### (tmp領域7 == バイナリ生物領域終了アドレスの場合)「自身の前に必要なサイズの空きがあるか確認」までジャンプ
	dm jmp LABEL_DIVISION_FUNC_CHECK_PREV	# addr:156
	#### (tmp領域7 != バイナリ生物領域終了アドレスの場合)以降の処理を実行
	#### ACレジスタへtmp領域7のアドレス先の値を取得
	dm lac i $SYS_TMP_7
	#### ACレジスタ == 開始シグネチャ?
	dm sad $BINBIO_BEGIN_SIG_ADDR
	#### (ACレジスタ == 開始シグネチャの場合)このループ処理を抜ける
	dm jmp LABEL_DIVISION_FUNC_CHECK_PREV
	{
		# (ACレジスタ != 開始シグネチャの場合)

		# tmp領域8の値(新たに必要なサイズ)をデクリメント
		## ACレジスタへ-1(2の補数)を設定
		dm lac $CONST_MINUS_1_TWOS_COMP_ADDR
		## ACレジスタへtmp領域8の値を加算
		dm tad $SYS_TMP_8
		## tmp領域8へ上書き
		dm dac $SYS_TMP_8

		# 開始シグネチャが無い事の確認が完了したか否か
		## ACレジスタ == 0?
		dm sza
		## (ACレジスタ != 0の場合)開始シグネチャが無い事の確認継続へジャンプ
		dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
		## (ACレジスタ == 0の場合)開始シグネチャが無い事の確認完了へジャンプ
		dm jmp $(calc_oct $SYS_AREA_NEXT + 5)
		{
			# 開始シグネチャが無い事の確認継続(4ワード)

			# tmp領域7(次に確認する場所を示すアドレス)をインクリメント
			dm lac $SYS_TMP_7
			dm add $CONST_1_ADDR
			dm dac $SYS_TMP_7

			# 「tmp領域7 == バイナリ生物領域終了アドレス?」まで戻る
			dm jmp $(calc_oct $SYS_AREA_NEXT - 20)	# 0o20 = 16
		}
		{
			# 開始シグネチャが無い事の確認完了

			# この時、tmp領域5には自身の直後のアドレスが入っている

			# DIVIDED_TO_NEXTへ1を設定
			dm lac $CONST_1_ADDR
			dm dac $DIVIDED_TO_NEXT_ADDR

			# 「突然変異するか否かで分岐」までジャンプ
			dm jmp $(calc_oct $SYS_AREA_NEXT + 30)	# 0o30 = 24
		}
	}

	# この時点でのtmp領域の使用状況(自身の直後に空きが無かった場合)
	# - tmp領域1: 「自身のエネルギー - 増殖コスト」の結果
	# - tmp領域2: 自身のエネルギーのアドレス
	# - tmp領域3: 突然変異するか否か
	# - tmp領域4: 新たなバイナリ生物と元とのサイズ差
	# - tmp領域6: 新たなバイナリ生物のサイズ

	set_label LABEL_DIVISION_FUNC_CHECK_PREV
	## 自身の前に必要なサイズの空きがあるか確認(3ワード)
	### 自身の直前のアドレスを算出
	#### ACレジスタへ自身のアドレスを取得
	dm lac $CUR_BINBIO_ADDR
	#### ACレジスタ -= 1
	dm tad $CONST_MINUS_1_TWOS_COMP_ADDR
	#### 算出したアドレスをtmp領域5へ設定
	dm dac $SYS_TMP_5

	# この時点でのtmp領域の使用状況(自身の直後に空きが無かった場合)
	# - tmp領域1: 「自身のエネルギー - 増殖コスト」の結果
	# - tmp領域2: 自身のエネルギーのアドレス
	# - tmp領域3: 突然変異するか否か
	# - tmp領域4: 新たなバイナリ生物と元とのサイズ差
	# - tmp領域5: 自身の直前のアドレス
	# - tmp領域6: 新たなバイナリ生物のサイズ

	### 自身の直前の新たに必要なサイズ分の領域に終了シグネチャが無い事を確認(20ワード)
	#### tmp領域5 == (バイナリ生物領域開始アドレス - 1)?
	dm law $(calc_oct $BINBIO_AREA_BEGIN - 1)
	dm and $MASK_FOR_LAW_ADDR
	dm sad $SYS_TMP_5
	#### (tmp領域5 == (バイナリ生物領域開始アドレス - 1)の場合)「自身の前後に空きが無かった場合」までジャンプ
	dm jmp $(calc_oct $SYS_AREA_NEXT + 17)	# 0o17 = 15
	#### (tmp領域5 != バイナリ生物領域終了アドレスの場合)以降の処理を実行
	#### ACレジスタへtmp領域5のアドレス先の値を取得
	dm lac i $SYS_TMP_5
	#### ACレジスタ == 終了シグネチャ?
	dm sad $BINBIO_END_SIG_ADDR
	#### (ACレジスタ == 終了シグネチャの場合)「自身の前後に空きが無かった場合」へジャンプ
	dm jmp $(calc_oct $SYS_AREA_NEXT + 14)	# 0o14 = 12
	{
		# (ACレジスタ != 終了シグネチャの場合)(11ワード)

		# tmp領域6の値(新たに必要なサイズ)をデクリメント
		## ACレジスタへ-1(2の補数)を設定
		dm lac $CONST_MINUS_1_TWOS_COMP_ADDR
		## ACレジスタへtmp領域6の値を加算
		dm tad $SYS_TMP_6
		## tmp領域6へ上書き
		dm dac $SYS_TMP_6

		# 終了シグネチャが無い事の確認が完了したか否か
		## ACレジスタ == 0?
		dm sza
		## (ACレジスタ != 0の場合)終了シグネチャが無い事の確認継続へジャンプ
		dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
		## (ACレジスタ == 0の場合)終了シグネチャが無い事の確認完了へジャンプ
		dm jmp $(calc_oct $SYS_AREA_NEXT + 5)
		{
			# 終了シグネチャが無い事の確認継続(4ワード)

			# tmp領域5(次に確認する場所を示すアドレス)をデクリメント
			dm lac $SYS_TMP_5
			dm tad $CONST_MINUS_1_TWOS_COMP_ADDR
			dm dac $SYS_TMP_5

			# 「tmp領域5 == (バイナリ生物領域開始アドレス - 1)?」まで戻る
			dm jmp $(calc_oct $SYS_AREA_NEXT - 20)	# 0o20 = 16
		}
		{
			# 終了シグネチャが無い事の確認完了(1ワード)

			# この時、tmp領域5には自身の直前に配置可能な領域の先頭アドレスが入っている

			# 「自身の前後に空きが無かった場合」の処理を飛ばす
			dm jmp $(calc_oct $SYS_AREA_NEXT + 3)
		}
	}
	{
		# 自身の前後に空きが無かった場合(2ワード)

		# ACレジスタへ0を設定しリターン
		dm cla
		dm jmp i $DIVISION_FUNC_ADDR
	}

	# この時点でのtmp領域の使用状況
	# - tmp領域1: 「自身のエネルギー - 増殖コスト」の結果
	# - tmp領域2: 自身のエネルギーのアドレス
	# - tmp領域3: 突然変異するか否か
	# - tmp領域4: 新たなバイナリ生物と元とのサイズ差
	# - tmp領域5: 新たなバイナリ生物を置く領域の先頭アドレス

	# 突然変異するか否かで分岐
	## tmp領域3 == 1?
	dm lac $SYS_TMP_3	# addr:226
	dm sad $CONST_1_ADDR
	## (tmp領域3 == 1の場合)「突然変異する場合」へジャンプ
	dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
	## (tmp領域3 != 1の場合)「突然変異しない場合」へジャンプ
	dm jmp LABEL_DIVISION_FUNC_NO_MUTATION
	{
		# 突然変異する場合

		# 自身の何番目の命令を突然変異対象にするか(0始まり)をtmp領域6へ設定
		select_mutation_target

		# この時点でのtmp領域の使用状況
		# - tmp領域1: 「自身のエネルギー - 増殖コスト」の結果
		# - tmp領域2: 自身のエネルギーのアドレス
		# - tmp領域3: 突然変異するか否か
		# - tmp領域4: 新たなバイナリ生物と元とのサイズ差
		# - tmp領域5: 新たなバイナリ生物を置く領域の先頭アドレス
		# - tmp領域6: 自身の何番目の命令を突然変異対象にするか(0始まり)

		# 選択した命令が自身の最後の命令である場合の処理
		# 最後の命令はリターン命令と決まっており、この命令は変更と削除を行わない事にしている
		# そこで、選択した命令が最後の命令でかつ突然変異タイプが追加でない場合、この時点でリターンする
		# なお、元々の突然変異タイプに沿って新たなバイナリ生物を置く領域のサイズが決められているので、
		# この時点で突然変異タイプを追加へ変更することはできない
		# また、この地点から突然変異なしの処理へジャンプするという事も、tmp領域の使い方が違うことや
		# スパゲッティコードをより促進することを考えると避けたい
		## 自身のアドレスをACレジスタへ取得
		dm lac $CUR_BINBIO_ADDR
		## ACレジスタへ命令数までのオフセットを加算
		dm add $OFFSET_TO_NUM_INST_ADDR
		## tmp領域7へACレジスタの値(自身の命令数のアドレス)を設定
		dm dac $SYS_TMP_7
		## ACレジスタへtmp領域7に設定されているアドレスが指す先の値
		## (自身の命令数)を取得
		dm lac i $SYS_TMP_7
		## ACレジスタ -= 1
		dm tad $CONST_MINUS_1_TWOS_COMP_ADDR
		## tmp領域6 == ACレジスタ?
		dm sad $SYS_TMP_6	# addr:241
		## (tmp領域6 == ACレジスタの場合)「選択した命令が自身の最後の命令である場合」へジャンプ
		dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
		## (tmp領域6 != ACレジスタの場合)「選択した命令が自身の最後の命令である場合」を飛ばす
		dm jmp LABEL_DIVISION_FUNC_SELECT_INST
		{
			# 選択した命令が自身の最後の命令である場合

			# 突然変異タイプが追加か?
			dm lac $CONST_1_ADDR
			dm sad $SYS_TMP_4	# addr:245
			## (突然変異タイプが追加の場合)「増殖できなかったとしてリターン」を飛ばす
			dm jmp LABEL_DIVISION_FUNC_SELECT_INST
			## (突然変異タイプが追加ではない場合)以降を実行
			{
				# 増殖できなかったとしてリターン

				# 戻り値としてACレジスタに0を設定
				dm cla

				# DIVIDED_TO_NEXTにも0を設定
				dm dac $DIVIDED_TO_NEXT_ADDR

				# リターン
				dm jmp i $DIVISION_FUNC_ADDR
			}
		}

		# この時点でのtmp領域の使用状況
		# - tmp領域1: 「自身のエネルギー - 増殖コスト」の結果
		# - tmp領域2: 自身のエネルギーのアドレス
		# - tmp領域3: 突然変異するか否か
		# - tmp領域4: 新たなバイナリ生物と元とのサイズ差
		# - tmp領域5: 新たなバイナリ生物を置く領域の先頭アドレス
		# - tmp領域6: 自身の何番目の命令を突然変異対象にするか(0始まり)

		set_label LABEL_DIVISION_FUNC_SELECT_INST
		# 突然変異タイプが削除でない場合、tmp領域7へ命令候補を設定(13ワード)
		## tmp領域4 == -1(1の補数)?
		dm lac $CONST_1_ADDR	# addr:252
		dm cma
		dm sad $SYS_TMP_4
		## (tmp領域4 == -1の場合)「突然変異タイプが削除でない場合」を飛ばす
		dm jmp $(calc_oct $SYS_AREA_NEXT + 12)	# 0o12 = 10
		{
			# (tmp領域4 != -1の場合)突然変異タイプが削除でない場合(9ワード)

			# tmp領域7へ命令候補のインデックスを設定
			## 乱数生成
			dm jms $GEN_RAND_FUNC_ADDR
			## ACレジスタへ生成した乱数を設定
			dm lac $RAND_VAL_ADDR
			## 命令候補テーブルインデックスのビットだけ抽出
			dm and $INST_CAND_TBL_MASK_ADDR
			## tmp領域7へACレジスタの値を設定
			dm dac $SYS_TMP_7

			# tmp領域7へ命令候補テーブルの先頭アドレスを加算
			dm lac $INST_CAND_TBL_BEGIN_ADDR
			dm add $SYS_TMP_7
			dm dac $SYS_TMP_7

			# tmp領域7へtmp領域7が指す先の値(命令候補)を設定
			dm lac i $SYS_TMP_7
			dm dac $SYS_TMP_7
		}

		# この時点でのtmp領域の使用状況
		# - tmp領域1: 「自身のエネルギー - 増殖コスト」の結果
		# - tmp領域2: 自身のエネルギーのアドレス
		# - tmp領域3: 突然変異するか否か
		# - tmp領域4: 新たなバイナリ生物と元とのサイズ差
		# - tmp領域5: 新たなバイナリ生物を置く領域の先頭アドレス
		# - tmp領域6: 自身の何番目の命令を突然変異対象にするか(0始まり)
		# - tmp領域7: (突然変異タイプ != 削除の場合)命令候補

		# ヘッダ情報をコピー(46ワード)
		# ただし、
		# - エネルギーは$BINBIO_INITIAL_ENERGY_DEC
		# - 命令数はtmp領域4(元とのサイズ差)を加算した値
		# - 戻り先アドレスは0
		## tmp領域8へ自身の開始アドレスを設定(2ワード)
		dm lac $CUR_BINBIO_ADDR
		dm dac $SYS_TMP_8
		## 新たなバイナリ生物へ開始シグネチャをコピーしコピー元と先をインクリメント(8ワード)
		### コピー
		dm lac i $SYS_TMP_8
		dm dac i $SYS_TMP_5
		### コピー元をインクリメント
		dm lac $SYS_TMP_8
		dm add $CONST_1_ADDR
		dm dac $SYS_TMP_8
		### コピー先をインクリメント
		dm lac $SYS_TMP_5
		dm add $CONST_1_ADDR
		dm dac $SYS_TMP_5
		## 新たなバイナリ生物のエネルギーへ初期値を設定しコピー元と先をインクリメント(8ワード)
		### 初期値を設定
		dm lac $BINBIO_INITIAL_ENERGY_ADDR
		dm dac i $SYS_TMP_5
		### コピー元をインクリメント
		dm lac $SYS_TMP_8
		dm add $CONST_1_ADDR
		dm dac $SYS_TMP_8
		### コピー先をインクリメント
		dm lac $SYS_TMP_5
		dm add $CONST_1_ADDR
		dm dac $SYS_TMP_5
		## 新たなバイナリ生物へ適応度をコピーしコピー元と先をインクリメント(8ワード)
		### コピー
		dm lac i $SYS_TMP_8
		dm dac i $SYS_TMP_5
		### コピー元をインクリメント
		dm lac $SYS_TMP_8
		dm add $CONST_1_ADDR
		dm dac $SYS_TMP_8
		### コピー先をインクリメント
		dm lac $SYS_TMP_5
		dm add $CONST_1_ADDR
		dm dac $SYS_TMP_5
		## 新たなバイナリ生物の命令数へtmp領域4(元とのサイズ差)を加算した値を設定しコピー元と先をインクリメント(9ワード)
		### tmp領域4(元とのサイズ差)を加算した値を設定
		dm lac i $SYS_TMP_8
		dm add $SYS_TMP_4
		dm dac i $SYS_TMP_5
		### コピー元をインクリメント
		dm lac $SYS_TMP_8
		dm add $CONST_1_ADDR
		dm dac $SYS_TMP_8
		### コピー先をインクリメント
		dm lac $SYS_TMP_5
		dm add $CONST_1_ADDR
		dm dac $SYS_TMP_5
		## 現在のtmp領域5に書かれているアドレスをオペランドとしたJMP I命令をtmp領域10に置いておく(3ワード)
		### ACレジスタへオペコード部分を設定
		dm lac $JMP_I_OPCODE_ADDR
		### ACレジスタへオペランド部分を加算
		dm add $SYS_TMP_5
		### tmp領域10へACレジスタの値を設定
		dm dac $SYS_TMP_10
		## 新たなバイナリ生物の戻り先アドレスへ0を設定しコピー元と先をインクリメント(8ワード)
		### 0を設定
		dm cla
		dm dac i $SYS_TMP_5
		### コピー元をインクリメント
		dm lac $SYS_TMP_8
		dm add $CONST_1_ADDR
		dm dac $SYS_TMP_8
		### コピー先をインクリメント
		dm lac $SYS_TMP_5
		dm add $CONST_1_ADDR
		dm dac $SYS_TMP_5

		# この時点でのtmp領域の使用状況
		# - tmp領域1: 「自身のエネルギー - 増殖コスト」の結果
		# - tmp領域2: 自身のエネルギーのアドレス
		# - tmp領域3: 突然変異するか否か
		# - tmp領域4: 新たなバイナリ生物と元とのサイズ差
		# - tmp領域5: 新たなバイナリ生物の命令列のアドレス
		# - tmp領域6: 自身の何番目の命令を突然変異対象にするか(0始まり)
		# - tmp領域7: (突然変異タイプ != 削除の場合)命令候補
		# - tmp領域8: 自身の命令列のアドレス
		# - tmp領域10: 新たなバイナリ生物のリターン命令

		# 突然変異を留意しつつ命令列をコピー(32ワード)
		## tmp領域9へ「現在自身の何番目の命令に注目しているか」の初期値として0を設定
		dm cla
		dm dac $SYS_TMP_9
		## (ループ処理ここから)
		## 現在注目している命令は突然変異対象か?
		### tmp領域9 == tmp領域6?
		dm lac $SYS_TMP_9
		dm sad $SYS_TMP_6
		### (tmp領域9 == tmp領域6の場合)「突然変異処理」へジャンプ
		dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
		### (tmp領域9 != tmp領域6の場合)「突然変異処理」を飛ばす
		dm jmp $(calc_oct $SYS_AREA_NEXT + 33)	# 0o33 = 27
		{
			# 突然変異処理(26ワード)

			# 突然変異タイプ == 追加?
			## tmp領域4 == 1?
			dm lac $CONST_1_ADDR
			dm sad $SYS_TMP_4
			## (tmp領域4 == 1の場合)「追加の場合」へジャンプ
			dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
			## (tmp領域4 != 1の場合)「変更・削除の場合」へジャンプ
			dm jmp $(calc_oct $SYS_AREA_NEXT + 7)
			{
				# 追加の場合(6ワード)

				# 命令候補を新たなバイナリ生物の現在の位置へ設定
				dm lac $SYS_TMP_7
				dm dac i $SYS_TMP_5

				# コピー先をインクリメント
				dm lac $SYS_TMP_5
				dm add $CONST_1_ADDR
				dm dac $SYS_TMP_5

				# 「変更・削除の場合」を飛ばす
				dm jmp $(calc_oct $SYS_AREA_NEXT + 21)	# 0o21 = 17
			}
			{
				# 変更・削除の場合(16ワード)

				# 突然変異タイプ == 変更?
				## tmp領域4 == 0?
				dm cla
				dm sad $SYS_TMP_4
				## (tmp領域4 == 0の場合)「変更の場合」へジャンプ
				dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
				## (tmp領域4 != 0の場合)「削除の場合」へジャンプ
				dm jmp $(calc_oct $SYS_AREA_NEXT + 12)	# 0o12 = 10
				{
					# 変更の場合(9ワード)

					# 命令候補を新たなバイナリ生物の現在の位置へ設定
					dm lac $SYS_TMP_7
					dm dac i $SYS_TMP_5

					# コピー先をインクリメント
					dm lac $SYS_TMP_5
					dm add $CONST_1_ADDR
					dm dac $SYS_TMP_5

					# コピー元もインクリメント
					dm lac $SYS_TMP_8
					dm add $CONST_1_ADDR
					dm dac $SYS_TMP_8

					# 「削除の場合」を飛ばす
					dm jmp $(calc_oct $SYS_AREA_NEXT + 4)
				}
				{
					# 削除の場合(3ワード)

					# コピー元をインクリメント
					dm lac $SYS_TMP_8
					dm add $CONST_1_ADDR
					dm dac $SYS_TMP_8
				}
				## ここでtmp領域9をインクリメントしないと、
				## それ以降tmp領域9は1つずれた値を示すことになるが、
				## 既に突然変異させる命令を見つける役割は終えていて
				## 特に挙動に問題も無いため、ずれたままにしておく
			}
		}

		# 命令をコピー(21ワード)
		## tmp領域8が指す先の値をACレジスタへ取得
		dm lac i $SYS_TMP_8
		## ACレジスタ == JMP I命令?
		dm and $JMP_I_OPCODE_MASK_ADDR
		dm sad $JMP_I_OPCODE_ADDR
		## (ACレジスタ == JMP I命令の場合)「ACレジスタへ新たなバイナリ生物のリターン命令を設定」へジャンプ
		dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
		## (ACレジスタ != JMP I命令の場合)「ACレジスタへ自身の命令を設定」へジャンプ
		dm jmp $(calc_oct $SYS_AREA_NEXT + 3)
		{
			# ACレジスタへ新たなバイナリ生物のリターン命令を設定(2ワード)
			dm lac $SYS_TMP_10
			## 「ACレジスタへ自身の命令を設定」を飛ばす
			dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
		}
		{
			# ACレジスタへ自身の命令を設定(1ワード)
			dm lac i $SYS_TMP_8
		}
		## ACレジスタの値をtmp領域5が指す先へ設定
		dm dac i $SYS_TMP_5
		## ACレジスタ == 終了シグネチャ?
		dm sad $BINBIO_END_SIG_ADDR
		## (ACレジスタ == 終了シグネチャの場合)ループ処理を抜ける
		dm jmp $(calc_oct $SYS_AREA_NEXT + 13)	# 0o13 = 11
		{
			# ACレジスタ != 終了シグネチャの場合(10ワード)

			# 自身の命令の番目をインクリメント
			dm lac $SYS_TMP_9
			dm add $CONST_1_ADDR
			dm dac $SYS_TMP_9

			# tmp領域8に書かれているアドレス(自身)をインクリメント
			dm lac $SYS_TMP_8
			dm add $CONST_1_ADDR
			dm dac $SYS_TMP_8

			# tmp領域5に書かれているアドレス(新たなバイナリ生物)をインクリメント
			dm lac $SYS_TMP_5
			dm add $CONST_1_ADDR
			dm dac $SYS_TMP_5

			# 「ループ処理ここから」まで戻る
			dm jmp $(calc_oct $SYS_AREA_NEXT - 62)	# 0o62 = 50
		}

		# 「突然変異しない場合」を飛ばす
		dm jmp $(calc_oct $SYS_AREA_NEXT + 100)	# 0o100 = 64
	}
	{
		set_label LABEL_DIVISION_FUNC_NO_MUTATION
		# 突然変異しない場合(63ワード)

		# この時点でのtmp領域の使用状況
		# - tmp領域1: 「自身のエネルギー - 増殖コスト」の結果
		# - tmp領域2: 自身のエネルギーのアドレス
		# - tmp領域3: 突然変異するか否か
		# - tmp領域4: 新たなバイナリ生物と元とのサイズ差
		# - tmp領域5: 新たなバイナリ生物を置く領域の先頭アドレス

		# ヘッダ情報をコピー(45ワード)
		# ただし、エネルギーは$BINBIO_INITIAL_ENERGY_DEC、戻り先アドレスは0とする
		## tmp領域6へ自身の開始アドレスを設定(2ワード)
		dm lac $CUR_BINBIO_ADDR	# addr:433
		dm dac $SYS_TMP_6
		## 新たなバイナリ生物へ開始シグネチャをコピーしコピー元と先をインクリメント(8ワード)
		### コピー
		dm lac i $SYS_TMP_6
		dm dac i $SYS_TMP_5
		### コピー元をインクリメント
		dm lac $SYS_TMP_6
		dm add $CONST_1_ADDR
		dm dac $SYS_TMP_6
		### コピー先をインクリメント
		dm lac $SYS_TMP_5
		dm add $CONST_1_ADDR
		dm dac $SYS_TMP_5
		## 新たなバイナリ生物のエネルギーへ初期値を設定しコピー元と先をインクリメント(8ワード)
		### 初期値を設定
		dm lac $BINBIO_INITIAL_ENERGY_ADDR
		dm dac i $SYS_TMP_5
		### コピー元をインクリメント
		dm lac $SYS_TMP_6
		dm add $CONST_1_ADDR
		dm dac $SYS_TMP_6
		### コピー先をインクリメント
		dm lac $SYS_TMP_5
		dm add $CONST_1_ADDR
		dm dac $SYS_TMP_5
		## 新たなバイナリ生物へ適応度と命令数をコピーしながらコピー元と先をインクリメント(16ワード)
		for i in $(seq 2); do
			### コピー
			dm lac i $SYS_TMP_6
			dm dac i $SYS_TMP_5
			### コピー元をインクリメント
			dm lac $SYS_TMP_6
			dm add $CONST_1_ADDR
			dm dac $SYS_TMP_6
			### コピー先をインクリメント
			dm lac $SYS_TMP_5
			dm add $CONST_1_ADDR
			dm dac $SYS_TMP_5
		done
		## 現在のtmp領域5に書かれているアドレスをオペランドとしたJMP I命令をtmp領域7に置いておく(3ワード)
		### ACレジスタへオペコード部分を設定
		dm lac $JMP_I_OPCODE_ADDR
		### ACレジスタへオペランド部分を加算
		dm add $SYS_TMP_5
		### tmp領域7へACレジスタの値を設定
		dm dac $SYS_TMP_7
		## 新たなバイナリ生物の戻り先アドレスへ0を設定しコピー元と先をインクリメント(8ワード)
		### 0を設定
		dm cla
		dm dac i $SYS_TMP_5
		### コピー元をインクリメント
		dm lac $SYS_TMP_6
		dm add $CONST_1_ADDR
		dm dac $SYS_TMP_6
		### コピー先をインクリメント
		dm lac $SYS_TMP_5
		dm add $CONST_1_ADDR
		dm dac $SYS_TMP_5

		# この時点でのtmp領域の使用状況
		# - tmp領域1: 「自身のエネルギー - 増殖コスト」の結果
		# - tmp領域2: 自身のエネルギーのアドレス
		# - tmp領域3: 突然変異するか否か
		# - tmp領域4: 新たなバイナリ生物と元とのサイズ差
		# - tmp領域5: 新たなバイナリ生物の命令列のアドレス
		# - tmp領域6: 自身の命令列のアドレス
		# - tmp領域7: 新たなバイナリ生物のリターン命令

		# 命令列をコピー(18ワード)
		## tmp領域6が指す先の値をACレジスタへ取得
		dm lac i $SYS_TMP_6
		## ACレジスタ == JMP I命令?
		dm and $JMP_I_OPCODE_MASK_ADDR
		dm sad $JMP_I_OPCODE_ADDR
		## (ACレジスタ == JMP I命令の場合)「ACレジスタへ新たなバイナリ生物のリターン命令を設定」へジャンプ
		dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
		## (ACレジスタ != JMP I命令の場合)「ACレジスタへ自身の命令を設定」へジャンプ
		dm jmp $(calc_oct $SYS_AREA_NEXT + 3)
		{
			# ACレジスタへ新たなバイナリ生物のリターン命令を設定(2ワード)
			dm lac $SYS_TMP_7
			## 「ACレジスタへ自身の命令を設定」を飛ばす
			dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
		}
		{
			# ACレジスタへ自身の命令を設定(1ワード)
			dm lac i $SYS_TMP_6
		}
		## ACレジスタの値をtmp領域5が指す先へ設定
		dm dac i $SYS_TMP_5
		## ACレジスタ == 終了シグネチャ?
		dm sad $BINBIO_END_SIG_ADDR
		## (ACレジスタ == 終了シグネチャの場合)ループ処理を抜ける
		dm jmp $(calc_oct $SYS_AREA_NEXT + 10)	# 0o10 = 8
		{
			# ACレジスタ != 終了シグネチャの場合(7ワード)

			# tmp領域6に書かれているアドレス(自身)をインクリメント
			dm lac $SYS_TMP_6
			dm add $CONST_1_ADDR
			dm dac $SYS_TMP_6

			# tmp領域5に書かれているアドレス(新たなバイナリ生物)をインクリメント
			dm lac $SYS_TMP_5
			dm add $CONST_1_ADDR
			dm dac $SYS_TMP_5

			# 「tmp領域6が指す先の値をACレジスタへ取得」まで戻る
			dm jmp $(calc_oct $SYS_AREA_NEXT - 21)	# 0o21 = 17
		}
	}

	# (分裂をした場合)自身のエネルギーを更新
	## tmp領域2が指す先をtmp領域1で上書きする
	dm lac $SYS_TMP_1
	dm dac i $SYS_TMP_2

	# 増殖できた場合のリターン
	## ACレジスタへ1を設定
	dm lac $CONST_1_ADDR
	## リターン
	dm jmp i $DIVISION_FUNC_ADDR
} >>$TMP_FILE

# バイナリ生物の1周期を実行
# 設定されているべき変数:
# - CUR_BINBIO
{
	# 関数アドレスを変数へ設定
	CYCLE_FUNC_ADDR=$SYS_AREA_NEXT

	# 戻り先アドレスが書かれる領域
	SYS_AREA_NEXT=$(calc_oct $SYS_AREA_NEXT + 1)

	# 代謝/運動
	## 評価関数を呼び出す
	dm jms $EVAL_FUNC_ADDR
	## 得られた適応度をバイナリ生物のデータ構造へ設定
	### 得られた適応度をtmp領域へ退避
	dm dac $SYS_TMP_1
	### 現在のバイナリ生物のアドレスをACレジスタへ取得
	dm lac $CUR_BINBIO_ADDR
	### ACレジスタへ適応度までのオフセットを加算
	dm add $OFFSET_TO_FITNESS_ADDR
	### ACレジスタの値(バイナリ生物の適応度のアドレス)をtmp領域へ設定
	dm dac $SYS_TMP_2
	### 退避した適応度をACレジスタへ復帰
	dm lac $SYS_TMP_1
	### ACレジスタの値(適応度)をバイナリ生物の適応度へ設定
	dm dac i $SYS_TMP_2

	# 成長
	# 適応度に比例したエネルギーを自身のエネルギーへ加算する
	# まずは、0〜100の範囲で取得した適応度をそのままエネルギー量としてみる
	## 現在のバイナリ生物のアドレスをACレジスタへ取得
	dm lac $CUR_BINBIO_ADDR
	## ACレジスタへエネルギーまでのオフセットを加算
	dm add $OFFSET_TO_ENERGY_ADDR
	## ACレジスタの値(バイナリ生物のエネルギーのアドレス)をtmp領域2へ設定
	dm dac $SYS_TMP_2
	## 取得したエネルギーをACレジスタへ設定
	## (tmp領域に退避されている適応度をそのまま使う)
	dm lac $SYS_TMP_1
	## バイナリ生物のエネルギーと取得したエネルギーの和をACレジスタへ設定
	dm add i $SYS_TMP_2
	## ACレジスタの値(エネルギー)をバイナリ生物のエネルギーへ設定
	dm dac i $SYS_TMP_2

	# この時点でのtmp領域の使用状況
	# - tmp領域2: 自身のエネルギーのアドレス

	# 増殖
	# ひとまずは、
	# 増殖コストを払えるだけのエネルギーがあったら常に増殖する
	## 自身のエネルギー >= 増殖コスト か確認
	### 自身のエネルギー - 増殖コスト を計算
	#### 増殖コストをACレジスタへ設定
	dm lac $DIVISION_COST_ADDR	# addr:614
	#### ACレジスタの値を2の補数表現の負の値へ変換
	##### 各ビットを反転
	dm cma
	##### 1を加算
	dm tad $CONST_1_ADDR
	#### ACレジスタ += tmp領域2(自身のエネルギーのアドレス)が指す先の値
	dm tad i $SYS_TMP_2
	## 結果が負の値(自身のエネルギー < 増殖コスト)か?
	dm sma
	## (負の値ではない場合)増殖する
	dm jms $DIVISION_FUNC_ADDR
	## (負の値の場合)以降を実行する

	# 定常的なエネルギー消費
	## 現在のバイナリ生物のアドレスをACレジスタへ取得
	dm lac $CUR_BINBIO_ADDR
	## ACレジスタへエネルギーまでのオフセットを加算
	dm add $OFFSET_TO_ENERGY_ADDR
	## ACレジスタの値(バイナリ生物のエネルギーのアドレス)をtmp領域1へ設定
	dm dac $SYS_TMP_1
	## ACレジスタへtmp領域1が指す先の値(現在のバイナリ生物のエネルギー)を取得
	dm lac i $SYS_TMP_1
	## ACレジスタへ定常的なエネルギー消費量(2の補数の負の値)を加算
	dm tad $CONSTANT_ENERGY_CONSUMPTION_ADDR	# addr:626
	## tmp領域1が指す先(現在のバイナリ生物のエネルギー)へACレジスタの値を設定
	dm dac i $SYS_TMP_1

	# 死
	# 前提:
	# - ACレジスタ: 現在のバイナリ生物のエネルギー
	## ACレジスタに-1を加算
	dm tad $CONST_MINUS_1_TWOS_COMP_ADDR
	## ACレジスタが負の値か?
	dm sma
	## (ACレジスタが負の値ではない場合)「現在のバイナリ生物の削除」を飛ばす
	dm jmp $(calc_oct $SYS_AREA_NEXT + 16)	# 0o16 = 14
	## (ACレジスタが負の値の場合)以降を実行する
	{
		# 現在のバイナリ生物の削除(13ワード)

		# 開始シグネチャをクリア(4ワード)
		## 現在のバイナリ生物(開始シグネチャ)のアドレスをACレジスタへ取得
		dm lac $CUR_BINBIO_ADDR
		## tmp領域1へACレジスタの値(開始シグネチャのアドレス)を設定
		dm dac $SYS_TMP_1
		## tmp領域1が指す先(現在のバイナリ生物の開始シグネチャ)をクリア
		dm cla
		dm dac i $SYS_TMP_1

		# 終了シグネチャをクリア(9ワード)
		## tmp領域1へ命令数までのオフセットを加算
		dm lac $SYS_TMP_1
		dm add $OFFSET_TO_NUM_INST_ADDR
		dm dac $SYS_TMP_1
		## ACレジスタへ「命令数」・「戻り先アドレス」・「命令列」の分のオフセットを設定
		### ACレジスタへ現在のバイナリ生物の命令数を取得
		dm lac i $SYS_TMP_1
		### 「命令数」・「戻り先アドレス」の分(2ワード)を加算
		dm add $CONST_2_ADDR
		## tmp領域1へACレジスタの値を加算
		dm add $SYS_TMP_1
		dm dac $SYS_TMP_1
		## tmp領域1が指す先(現在のバイナリ生物の終了シグネチャ)をクリア
		dm cla
		dm dac i $SYS_TMP_1
	}

	# リターン
	dm jmp i $CYCLE_FUNC_ADDR
} >>$TMP_FILE

# セットアップ関数
{
	# 関数アドレスを変数へ設定
	SETUP_FUNC_ADDR=$SYS_AREA_NEXT

	# 戻り先アドレスが書かれる領域
	SYS_AREA_NEXT=$(calc_oct $SYS_AREA_NEXT + 1)

	# 定数設定
	## 定数CONST_MINUS_100_DEC_TWOS_COMPへ0o777634を設定する
	echo "d $CONST_MINUS_100_DEC_TWOS_COMP_ADDR 777634"
	## 定数CONST_MINUS_50_DEC_TWOS_COMPへ-50(10進数)の2の補数を設定する
	echo "d $CONST_MINUS_50_DEC_TWOS_COMP_ADDR $(bc <<< 'obase=8;262144 - 50')"
	## 定数CONST_MINUS_10_DEC_TWOS_COMPへ0o777766を設定する
	echo "d $CONST_MINUS_10_DEC_TWOS_COMP_ADDR 777766"
	## 定数CONST_MINUS_1_TWOS_COMPへ0o777777を設定する
	echo "d $CONST_MINUS_1_TWOS_COMP_ADDR 777777"
	## 定数CONST_1へ1を設定する
	echo "d $CONST_1_ADDR 1"
	## 定数CONST_2へ2を設定する
	echo "d $CONST_2_ADDR 2"
	## 定数CONST_3へ3を設定する
	echo "d $CONST_3_ADDR 3"
	## 定数CONST_6へ6を設定する
	echo "d $CONST_6_ADDR 6"
	## 定数CONST_10_DECへ10を設定する
	echo "d -d $CONST_10_DEC_ADDR 10"
	## 定数CONST_50_DECへ50を設定する
	echo "d -d $CONST_50_DEC_ADDR 50"
	## 定数CONST_100_DECへ100を設定する
	echo "d -d $CONST_100_DEC_ADDR 100"
	## 定数JMP_I_OPCODEへ同名のシェル変数を設定する
	echo "d $JMP_I_OPCODE_ADDR $JMP_I_OPCODE"
	## 定数JMP_I_OPCODE_MASKへ同名のシェル変数を設定する
	echo "d $JMP_I_OPCODE_MASK_ADDR $JMP_I_OPCODE_MASK"
	## 定数JMS_OPCODEへ同名のシェル変数を設定する
	echo "d $JMS_OPCODE_ADDR $JMS_OPCODE"
	## 定数MASK_FOR_LAWへ0o017777を設定する
	echo "d $MASK_FOR_LAW_ADDR 017777"
	## 定数BINBIO_ATTR_SIZEへ同名のシェル変数を設定する
	echo "d $BINBIO_ATTR_SIZE_ADDR $BINBIO_ATTR_SIZE"
	## 定数OFFSET_TO_ENERGYへ1を設定する
	echo "d $OFFSET_TO_ENERGY_ADDR 1"
	## 定数OFFSET_TO_FITNESSへ2を設定する
	echo "d $OFFSET_TO_FITNESS_ADDR 2"
	## 定数OFFSET_TO_NUM_INSTへ2を設定する
	echo "d $OFFSET_TO_NUM_INST_ADDR 3"
	## 定数OFFSET_TO_RET_ADDRへ4を設定する
	echo "d $OFFSET_TO_RET_ADDR_ADDR 4"
	## 定数OFFSET_TO_INST_LISTへ5を設定する
	echo "d $OFFSET_TO_INST_LIST_ADDR 5"
	## 定数BINBIO_BEGIN_SIGへ同名のシェル変数を設定する
	echo "d $BINBIO_BEGIN_SIG_ADDR $BINBIO_BEGIN_SIG"
	## 定数BINBIO_INITIAL_ENERGYへシェル変数BINBIO_INITIAL_ENERGY_DECを設定する
	echo "d -d $BINBIO_INITIAL_ENERGY_ADDR $BINBIO_INITIAL_ENERGY_DEC"
	## 定数CONSTANT_ENERGY_CONSUMPTIONへ同名のシェル変数を設定する
	echo "d $CONSTANT_ENERGY_CONSUMPTION_ADDR $CONSTANT_ENERGY_CONSUMPTION"
	## 定数DIVISION_COSTへシェル変数DIVISION_COST_DECを設定する
	echo "d -d $DIVISION_COST_ADDR $DIVISION_COST_DEC"
	## 定数BINBIO_END_SIGへ同名のシェル変数を設定する
	echo "d $BINBIO_END_SIG_ADDR $BINBIO_END_SIG"
	## 定数INST_CAND_TBL_BEGINへ同名のシェル変数を設定する
	echo "d $INST_CAND_TBL_BEGIN_ADDR $INST_CAND_TBL_BEGIN"
	## 定数INST_CAND_TBL_MASKへ同名のシェル変数を設定する
	echo "d $INST_CAND_TBL_MASK_ADDR $INST_CAND_TBL_MASK"
	## 定数BINBIO_AREA_BEGINへ同名のシェル変数を設定する
	echo "d $BINBIO_AREA_BEGIN_ADDR $BINBIO_AREA_BEGIN"

	# 変数設定
	## 変数RAND_VALへ乱数の初期値を設定する
	echo "d -d $RAND_VAL_ADDR $((RANDOM % 262144))"	# 262144 = 0o1000000
	## CUR_BINBIOへバイナリ生物領域の開始アドレスを設定
	echo "d $CUR_BINBIO_ADDR $BINBIO_AREA_BEGIN"
	## DIVIDED_TO_NEXTへ初期値0を設定
	echo "d $DIVIDED_TO_NEXT_ADDR 0"

	# 実験固有の初期設定
	experiment_specific_init

	# リターン
	dm jmp i $SETUP_FUNC_ADDR
} >>$TMP_FILE

# 環境の1周期を実行する
{
	# 関数アドレスを変数へ設定
	ENV_CYCLE_FUNC_ADDR=$SYS_AREA_NEXT

	# 戻り先アドレスが書かれる領域
	SYS_AREA_NEXT=$(calc_oct $SYS_AREA_NEXT + 1)

	# CUR_BINBIOへバイナリ生物領域の開始アドレスを設定
	dm lac $BINBIO_AREA_BEGIN_ADDR
	dm dac $CUR_BINBIO_ADDR

	# バイナリ生物領域末尾まで、各生物で1周期を実行する
	set_label LABEL_ENV_CYCLE_FUNC_CHECK_START_SIG
	## *CUR_BINBIO == 開始シグネチャ?
	dm lac i $CUR_BINBIO_ADDR
	dm sad $BINBIO_BEGIN_SIG_ADDR
	## (*CUR_BINBIO == 開始シグネチャの場合)「DIVIDED_TO_NEXTが0ならバイナリ生物の1周期を実行」へジャンプ
	dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
	## (*CUR_BINBIO != 開始シグネチャの場合)「アドレスを進める」へジャンプ
	dm jmp LABEL_ENV_CYCLE_FUNC_SEARCH_NEXT_BEGIN
	{
		# DIVIDED_TO_NEXTが0ならバイナリ生物の1周期を実行

		# DIVIDED_TO_NEXTが0か?
		dm lac $DIVIDED_TO_NEXT_ADDR
		dm sna
		## (DIVIDED_TO_NEXTが0の場合)「バイナリ生物の1周期を実行」へジャンプ
		dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
		## (DIVIDED_TO_NEXTが0ではない場合)「DIVIDED_TO_NEXTをクリア」へジャンプ
		dm jmp LABEL_ENV_CYCLE_FUNC_CLR_DIVIDED_TO_NEXT
		{
			# バイナリ生物の1周期を実行

			# 関数呼び出し
			dm jms $CYCLE_FUNC_ADDR

			# 「次のアドレスを飛ばす」を飛ばす
			dm jmp LABEL_ENV_CYCLE_FUNC_SEARCH_NEXT_BEGIN
		}
		{
			set_label LABEL_ENV_CYCLE_FUNC_CLR_DIVIDED_TO_NEXT
			# DIVIDED_TO_NEXTをクリア
			dm cla
			dm dac $DIVIDED_TO_NEXT_ADDR
		}
	}
	set_label LABEL_ENV_CYCLE_FUNC_SEARCH_NEXT_BEGIN
	## アドレスを進める
	dm lac $CUR_BINBIO_ADDR
	dm add $CONST_1_ADDR
	dm dac $CUR_BINBIO_ADDR
	## CUR_BINBIO == バイナリ生物領域末尾?
	dm law $BINBIO_AREA_END
	dm and $MASK_FOR_LAW_ADDR
	dm sad $CUR_BINBIO_ADDR
	## (CUR_BINBIO == バイナリ生物領域末尾の場合)リターン
	dm jmp i $ENV_CYCLE_FUNC_ADDR
	## (CUR_BINBIO != バイナリ生物領域末尾の場合)「*CUR_BINBIO == 開始シグネチャ?」まで戻る
	dm jmp LABEL_ENV_CYCLE_FUNC_CHECK_START_SIG
} >>$TMP_FILE

# セットアップを実行しHLTする処理
{
	SETUP_AND_HLT_CODE_ADDR=$SYS_AREA_NEXT
	dm jms $SETUP_FUNC_ADDR
	dm hlt
} >>$TMP_FILE

# 環境の1周期を実行しHLTする処理
{
	ENV_CYCLE_AND_HLT_CODE_ADDR=$SYS_AREA_NEXT
	dm jms $ENV_CYCLE_FUNC_ADDR
	dm hlt
} >>$TMP_FILE

# セットアップを実行し、無限に環境の1周期を実行し続ける処理
{
	SETUP_AND_INF_ENV_CYCLE_CODE_ADDR=$SYS_AREA_NEXT
	dm jms $SETUP_FUNC_ADDR
	set_label LABEL_SETUP_AND_INF_ENV_CYCLE_CODE_INF_ENV_CYCLE
	dm jms $ENV_CYCLE_FUNC_ADDR
	additional_proc_on_env_cycle
	dm jmp LABEL_SETUP_AND_INF_ENV_CYCLE_CODE_INF_ENV_CYCLE
} >>$TMP_FILE

# 実験シナリオを配置
{
	experimental_scenario
} >>$TMP_FILE

#
# プリプロセス
#

# sedを処理
## プリプロセスのsed式を抽出
grep PRESED $TMP_FILE | cut -d' ' -f3- >$PRESED_FILE
## プリプロセスのsed行を除外してファイル生成
grep -v PRESED $TMP_FILE >$SIMH_FILE
## プリプロセスのsedを実施
sed -i.before-sed -f $PRESED_FILE $SIMH_FILE

# 動的に設定された箇所のメモリマップを出力
{
	echo "GEN_RAND_FUNC_ADDR=$GEN_RAND_FUNC_ADDR"
	echo "EVAL_FUNC_ADDR=$EVAL_FUNC_ADDR"
	echo "IS_MUTATE_FUNC_ADDR=$IS_MUTATE_FUNC_ADDR"
	echo "SELECT_MUTATION_TYPE_FUNC_ADDR=$SELECT_MUTATION_TYPE_FUNC_ADDR"
	echo "DIVISION_FUNC_ADDR=$DIVISION_FUNC_ADDR"
	echo "CYCLE_FUNC_ADDR=$CYCLE_FUNC_ADDR"
	echo "SETUP_FUNC_ADDR=$SETUP_FUNC_ADDR"
	echo "ENV_CYCLE_FUNC_ADDR=$ENV_CYCLE_FUNC_ADDR"
	echo "SETUP_AND_HLT_CODE_ADDR=$SETUP_AND_HLT_CODE_ADDR"
	echo "ENV_CYCLE_AND_HLT_CODE_ADDR=$ENV_CYCLE_AND_HLT_CODE_ADDR"
	echo "SETUP_AND_INF_ENV_CYCLE_CODE_ADDR=$SETUP_AND_INF_ENV_CYCLE_CODE_ADDR"
} >$MAP_FILE
## 画面にも表示
cat $MAP_FILE

# 一時ファイルを削除
rm $TMP_FILE $PRESED_FILE ${SIMH_FILE}.before-sed

#
# 実行
#

echo "LOG_DIR=$LOG_DIR"
$PDP7_CMD $SIMH_FILE
