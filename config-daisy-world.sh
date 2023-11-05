# デイジーワールド
# の実験に依存するパラメータ値や関数定義

# 実験固有領域(0o006000〜0o007677)のメモリマップ
## 定数
DAISY_GROWING_TEMP_ADDR=006000	# デイジーの生育適温
MINUS_DAISY_GROWING_TEMP_ADDR=006001	# -デイジーの生育適温(2の補数)
STRONG_FEEDBACK_TH_ADDR=006002
STRONG_FEEDBACK_EXTREME_HIGH_FITNESS_ADDR=006003
STRONG_FEEDBACK_EXTREME_LOW_FITNESS_ADDR=006004
WHITE_DAISY_INST_ADDR=006005	# 白デイジー固有の命令
## 変数
SURFACE_TEMP_ADDR=006006	# 現在の地表温度

# 初期バイナリ生物に関するパラメータ
## 適応度(10進指定)
INITIAL_BINBIO_FITNESS_DEC=50
## 命令数(10進指定)
INITIAL_BINBIO_NUM_INST_DEC=2

# エネルギー消費に関するパラメータ
## 増殖コスト(10進指定)
DIVISION_COST_DEC=900
## 定常的なエネルギー消費量(2の補数の負の値)
CONSTANT_ENERGY_CONSUMPTION=$(bc <<< "obase=8;262144 - 110")

# 適応度算出関数: 地表温度と生育適温の差が大きい時は強いフィードバックを掛ける
# に関するパラメータ
## 強いフィードバックを掛ける地表温度と生育適温の差のしきい値(10進数)
STRONG_FEEDBACK_TH_DEC=50
## 強いフィードバックを掛ける際の極端に高い適応度(10進数)
STRONG_FEEDBACK_EXTREME_HIGH_FITNESS_DEC=50
## 強いフィードバックを掛ける際の極端に低い適応度(10進数)
STRONG_FEEDBACK_EXTREME_LOW_FITNESS_DEC=0

# その他実験パラメータ
## 命令候補テーブルのインデックスのビットだけ抽出するマスク
INST_CAND_TBL_MASK=000001
## デイジーの生育適温(10進指定)
DAISY_GROWING_TEMP_DEC=20
## -デイジーの生育適温(2の補数)
MINUS_DAISY_GROWING_TEMP=$(bc <<< "obase=8;262144 - $DAISY_GROWING_TEMP_DEC")
## 地表温度の初期値(10進指定)
INITIAL_SURFACE_TEMP_DEC=0
## 白デイジー固有の命令
TAD_OPCODE=340000
WHITE_DAISY_INST=$(calc_oct $TAD_OPCODE + $CONST_MINUS_1_TWOS_COMP_ADDR)

# 実験固有の初期設定
experiment_specific_init() {
	# 定数設定
	## 定数DAISY_GROWING_TEMPへシェル変数DAISY_GROWING_TEMP_DECを設定する
	echo "d -d $DAISY_GROWING_TEMP_ADDR $DAISY_GROWING_TEMP_DEC"
	## 定数MINUS_DAISY_GROWING_TEMPへ同名のシェル変数を設定する
	echo "d $MINUS_DAISY_GROWING_TEMP_ADDR $MINUS_DAISY_GROWING_TEMP"
	## 定数STRONG_FEEDBACK_THへシェル変数STRONG_FEEDBACK_TH_DECを設定する
	echo "d -d $STRONG_FEEDBACK_TH_ADDR $STRONG_FEEDBACK_TH_DEC"
	## 定数STRONG_FEEDBACK_EXTREME_HIGH_FITNESSへシェル変数STRONG_FEEDBACK_EXTREME_HIGH_FITNESS_DECを設定する
	echo "d -d $STRONG_FEEDBACK_EXTREME_HIGH_FITNESS_ADDR $STRONG_FEEDBACK_EXTREME_HIGH_FITNESS_DEC"
	## 定数STRONG_FEEDBACK_EXTREME_LOW_FITNESSへシェル変数STRONG_FEEDBACK_EXTREME_LOW_FITNESS_DECを設定する
	echo "d -d $STRONG_FEEDBACK_EXTREME_LOW_FITNESS_ADDR $STRONG_FEEDBACK_EXTREME_LOW_FITNESS_DEC"
	## 定数WHITE_DAISY_INSTへ同名のシェル変数を設定する
	echo "d $WHITE_DAISY_INST_ADDR $WHITE_DAISY_INST"

	# 変数設定
	## 変数SURFACE_TEMPへシェル変数INITIAL_SURFACE_TEMP_DECを設定する
	echo "d -d $SURFACE_TEMP_ADDR $INITIAL_SURFACE_TEMP_DEC"

	# 命令候補テーブル設定
	# 下記の2つのみ
	# 0: ACレジスタをデクリメント(地表温度を下げる。白いデイジー)
	# 1: ACレジスタをインクリメント(地表温度を上げる。黒いデイジー)
	echo "d -m $INST_CAND_TBL_BEGIN tad $CONST_MINUS_1_TWOS_COMP_ADDR"
	echo "d -m $(calc_oct $INST_CAND_TBL_BEGIN + 1) tad $CONST_1_ADDR"
}

# バイナリ生物の初期配置
## 指定された色のデイジーを指定されたアドレスへ配置する関数
## 引数:
## - 第1引数: デイジーの色('white'あるいは'black')
## - 第2引数: アドレス(8進数)
put_daisy_binbio() {
	local color=$1
	local addr=$2

	# 予めこのバイナリ生物のリターン命令を生成
	local return_inst=$(gen_return_inst $addr)

	# 開始シグネチャ
	echo "d $addr $BINBIO_BEGIN_SIG"

	# エネルギー
	addr=$(calc_oct $addr + 1)
	echo "d -d $addr $BINBIO_INITIAL_ENERGY_DEC"

	# 適応度
	addr=$(calc_oct $addr + 1)
	echo "d -d $addr $INITIAL_BINBIO_FITNESS_DEC"

	# 命令数
	addr=$(calc_oct $addr + 1)
	echo "d -d $addr $INITIAL_BINBIO_NUM_INST_DEC"

	# 戻り先アドレス
	addr=$(calc_oct $addr + 1)
	# JMS命令時に設定される領域であり、特に何も設定しておく必要はない

	# 機械語命令列
	addr=$(calc_oct $addr + 1)
	case "$color" in
	'white')
		# 白いデイジーは地表の熱を放出する
		# (ACレジスタをデクリメント)
		echo "d -m $addr tad $CONST_MINUS_1_TWOS_COMP_ADDR"
		;;
	'black')
		# 黒いデイジーは地表の熱を蓄積する
		# (ACレジスタをインクリメント)
		echo "d -m $addr tad $CONST_1_ADDR"
		;;
	esac
	addr=$(calc_oct $addr + 1)
	echo "d $addr $return_inst"

	# 終了シグネチャ
	addr=$(calc_oct $addr + 1)
	echo "d $addr $BINBIO_END_SIG"
}
## 本体
setup_initial_binbio() {
	# バイナリ生物領域を前半と後半に分けるために
	# 中間のアドレスを算出する
	local mid_addr=$(calc_oct "$BINBIO_AREA_BEGIN + (($BINBIO_AREA_END + 1 - $BINBIO_AREA_BEGIN) / 2)")

	# 前半の中間に白いデイジーを1つ配置
	## 前半の中間のアドレスを算出
	local top_half_mid_addr=$(calc_oct "$BINBIO_AREA_BEGIN + (($mid_addr - $BINBIO_AREA_BEGIN) / 2)")
	## 白いデイジーを配置
	put_daisy_binbio 'white' $top_half_mid_addr

	# 後半の中間に黒いデイジーを1つ配置
	## 後半の中間のアドレスを算出
	local bottom_half_mid_addr=$(calc_oct "$mid_addr + (($BINBIO_AREA_END + 1 - $mid_addr) / 2)")
	## 白いデイジーを配置
	put_daisy_binbio 'black' $bottom_half_mid_addr
}

# 評価関数
# 戻り値:
# - ACレジスタ: 適応度(0〜100)
## 適応度算出関数
## 引数:
## - ACレジスタ: 現在の地表温度
## 戻り値:
## - ACレジスタ: 適応度(0〜100)
### P制御のみ
eval_func_calc_fitness_term_p_only() {
	# 地表温度 - 生育適温を算出し、ACレジスタへ設定
	# (これをP制御における誤差とする)
	## ACレジスタへ-生育適温を加算
	dm tad $MINUS_DAISY_GROWING_TEMP_ADDR

	# 誤差 < 0か?
	dm sma
	## (誤差 >= 0の場合)「白デイジーへ誤差に比例した適応度を設定」へジャンプ
	dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
	## (誤差 < 0の場合)「黒デイジーへ誤差に比例した適応度を設定」へジャンプ
	dm jmp LABEL_EVAL_FUNC_CALC_FITNESS_PROP_ERR_TO_BLACK_DAISY
	{
		# 白デイジーへ誤差に比例した適応度を設定

		# 誤差をtmp領域2へ退避
		dm dac $SYS_TMP_2

		# 誤差 > 50か?
		## ACレジスタ(誤差) - 50を計算
		dm tad $CONST_MINUS_50_DEC_TWOS_COMP_ADDR
		## ACレジスタ < 0か?
		dm sma
		## (ACレジスタ >= 0の場合)「誤差を50とする」へジャンプ
		dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
		## (誤差 < 0の場合)「誤差を50とする」を飛ばす
		dm jmp LABEL_EVAL_FUNC_CALC_FITNESS_SKIP_ERR_50
		{
			# 誤差を50とする
			dm lac $CONST_50_DEC_ADDR
			dm dac $SYS_TMP_2
		}
		set_label LABEL_EVAL_FUNC_CALC_FITNESS_SKIP_ERR_50

		# 自身が白デイジー/黒デイジーのどちらなのか判別
		## ACレジスタへ自身の最初の命令のアドレスを設定
		dm lac $CUR_BINBIO_ADDR
		dm add $OFFSET_TO_INST_LIST_ADDR
		## tmp領域1を用いてACレジスタへ自身の最初の命令を取得する
		dm dac $SYS_TMP_1
		dm lac i $SYS_TMP_1
		## ACレジスタ == 白デイジー固有の命令?
		dm sad $WHITE_DAISY_INST_ADDR
		## (ACレジスタ == 白デイジー固有の命令の場合)「ACレジスタへ誤差に比例した適応度を設定」へジャンプ
		dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
		## (ACレジスタ != 白デイジー固有の命令の場合)「ACレジスタへ誤差に反比例した適応度を設定」へジャンプ
		dm jmp LABEL_EVAL_FUNC_CALC_FITNESS_SET_INVPROP_ERR
		{
			# (自身が白デイジーの場合)ACレジスタへ誤差に比例した適応度を設定

			# 「50 + 誤差」を適応度とする
			dm lac $CONST_50_DEC_ADDR
			dm tad $SYS_TMP_2

			# 「ACレジスタへ誤差に反比例した適応度を設定」を飛ばす
			dm jmp LABEL_EVAL_FUNC_CALC_FITNESS_SKIP_SET_INVPROP_ERR
		}
		{
			set_label LABEL_EVAL_FUNC_CALC_FITNESS_SET_INVPROP_ERR
			# (自身が黒デイジーの場合)ACレジスタへ誤差に反比例した適応度を設定

			# 「50 - 誤差」を適応度とする
			## 誤差を負の値(2の補数)にしたものをACレジスタへ設定
			dm lac $SYS_TMP_2
			dm cma
			dm tad $CONST_1_ADDR
			## ACレジスタへ50を加算
			dm tad $CONST_50_DEC_ADDR
		}
		set_label LABEL_EVAL_FUNC_CALC_FITNESS_SKIP_SET_INVPROP_ERR

		# 「黒デイジーへ誤差に比例した適応度を設定」を飛ばす
		dm jmp LABEL_EVAL_FUNC_CALC_FITNESS_SKIP_PROP_ERR_TO_BLACK_DAISY
	}
	{
		set_label LABEL_EVAL_FUNC_CALC_FITNESS_PROP_ERR_TO_BLACK_DAISY
		# 黒デイジーへ誤差に比例した適応度を設定

		# 誤差をtmp領域2へ退避
		dm dac $SYS_TMP_2

		# 誤差 < -50か?
		## ACレジスタ(誤差) + 50を計算
		dm tad $CONST_50_DEC_ADDR
		## ACレジスタ < 0か?
		dm sma
		## (ACレジスタ >= 0の場合)「誤差を-50とする」を飛ばす
		dm jmp LABEL_EVAL_FUNC_CALC_FITNESS_SKIP_ERR_MINUS_50
		## (誤差 < 0の場合)
		{
			# 「誤差を-50とする」
			dm lac $CONST_MINUS_50_DEC_TWOS_COMP_ADDR
			dm dac $SYS_TMP_2
		}
		set_label LABEL_EVAL_FUNC_CALC_FITNESS_SKIP_ERR_MINUS_50

		# 自身が白デイジー/黒デイジーのどちらなのか判別
		## ACレジスタへ自身の最初の命令のアドレスを設定
		dm lac $CUR_BINBIO_ADDR
		dm add $OFFSET_TO_INST_LIST_ADDR
		## tmp領域1を用いてACレジスタへ自身の最初の命令を取得する
		dm dac $SYS_TMP_1
		dm lac i $SYS_TMP_1
		## ACレジスタ == 白デイジー固有の命令?
		dm sad $WHITE_DAISY_INST_ADDR
		## (ACレジスタ == 白デイジー固有の命令の場合)「ACレジスタへ誤差に反比例した適応度を設定」へジャンプ
		dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
		## (ACレジスタ != 白デイジー固有の命令の場合)「ACレジスタへ誤差に比例した適応度を設定」へジャンプ
		dm jmp LABEL_EVAL_FUNC_CALC_FITNESS_SET_PROP_ERR
		{
			# (自身が白デイジーの場合)ACレジスタへ誤差に反比例した適応度を設定

			# 「50 - 誤差」を適応度とする
			## 誤差(負の値)をACレジスタへ設定
			dm lac $SYS_TMP_2
			## ACレジスタへ50を加算
			dm tad $CONST_50_DEC_ADDR

			# 「ACレジスタへ誤差に比例した適応度を設定」を飛ばす
			dm jmp LABEL_EVAL_FUNC_CALC_FITNESS_SKIP_SET_PROP_ERR
		}
		{
			set_label LABEL_EVAL_FUNC_CALC_FITNESS_SET_PROP_ERR
			# (自身が黒デイジーの場合)ACレジスタへ誤差に比例した適応度を設定

			# 誤差を正の値にしたものへ50を加算したものを適応度とする
			dm lac $SYS_TMP_2
			dm cma
			dm tad $CONST_1_ADDR
			dm tad $CONST_50_DEC_ADDR
		}
		set_label LABEL_EVAL_FUNC_CALC_FITNESS_SKIP_SET_PROP_ERR
	}
	set_label LABEL_EVAL_FUNC_CALC_FITNESS_SKIP_PROP_ERR_TO_BLACK_DAISY
}
### 適応度算出関数: 地表温度と生育適温の差が大きい時は強いフィードバックを掛ける
eval_func_calc_fitness_strong_feedback() {
	# ACレジスタへ現在の地表温度と生育適温の差を設定
	## ACレジスタから生育適温を減算
	dm tad $MINUS_DAISY_GROWING_TEMP_ADDR
	## ACレジスタの絶対値をACレジスタへ設定
	### ACレジスタ < 0か?
	dm sma
	### (ACレジスタ >= 0場合)「絶対値計算」を飛ばす
	dm jmp LABEL_EVAL_FUNC_SKIP_ABS
	### (ACレジスタ < 0の場合)
	{
		# 絶対値計算
		dm cma
		dm tad $CONST_1_ADDR
	}
	set_label LABEL_EVAL_FUNC_SKIP_ABS

	# ACレジスタへ-(地表温度と生育適温の差)(2の補数)を設定
	dm cma
	dm tad $CONST_1_ADDR
	## 後で使う可能性があるのでACレジスタの値をtmp領域1へコピーしておく
	dm dac $SYS_TMP_1

	# ACレジスタへ強いフィードバックを掛けるしきい値を加算
	dm tad $STRONG_FEEDBACK_TH_ADDR

	# ACレジスタ < 0か?
	# (地表温度と生育適温の差がしきい値を超えているか?)
	dm sma
	## (ACレジスタ >= 0(しきい値を超えていない)の場合)『「100(10進数) - (地表温度と生育適温の差)」を適応度とする』へジャンプ
	dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
	## (ACレジスタ < 0(しきい値を超えている)の場合)「強いフィードバックを掛ける」へジャンプ
	dm jmp LABEL_EVAL_FUNC_CALC_FITNESS_STRONG_FEEDBACK
	{
		# 「100(10進数) - (地表温度と生育適温の差)」を適応度とする

		# ACレジスタへ100(10進数)を設定
		dm lac $CONST_100_DEC_ADDR

		# ACレジスタへ-(地表温度と生育適温の差)を加算
		dm tad $SYS_TMP_1
		## しきい値(STRONG_FEEDBACK_TH)との比較を事前に行なっているので、
		## このときのACレジスタの値は少なくとも0〜100の範囲内ではあるはず
		## なので、これをこのまま適応度とする

		# 「強いフィードバックを掛ける」を飛ばす
		dm jmp LABEL_EVAL_FUNC_CALC_FITNESS_SKIP_STRONG_FEEDBACK
	}
	{
		set_label LABEL_EVAL_FUNC_CALC_FITNESS_STRONG_FEEDBACK
		# 強いフィードバックを掛ける

		# ACレジスタへ-生育適温(2の補数)を設定
		dm lac $MINUS_DAISY_GROWING_TEMP_ADDR

		# ACレジスタへ地表温度を加算
		dm tad $SURFACE_TEMP_ADDR

		# ACレジスタ < 0か?
		# (地表温度が生育適温より低いか?)
		dm sma
		## (ACレジスタ >= 0(地表温度が生育適温より高い)の場合)「白デイジーの適応度を極端に高くする」へジャンプ
		dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
		## (ACレジスタ < 0(地表温度が生育適温より低い)の場合)「黒デイジーの適応度を極端に高くする」へジャンプ
		dm jmp LABEL_EVAL_FUNC_CALC_FITNESS_HIGH_FITNESS_FOR_BLACK_DAISY
		{
			# 白デイジーの適応度を極端に高くする

			# ACレジスタへ自身の最初の命令のアドレスを設定
			dm lac $CUR_BINBIO_ADDR
			dm add $OFFSET_TO_INST_LIST_ADDR

			# tmp領域1を用いてACレジスタへ自身の最初の命令を取得する
			dm dac $SYS_TMP_1
			dm lac i $SYS_TMP_1

			# ACレジスタ == 白デイジー固有の命令?
			dm sad $WHITE_DAISY_INST_ADDR
			## (ACレジスタ == 白デイジー固有の命令の場合)「ACレジスタへ極端に高い適応度を設定」へジャンプ
			dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
			## (ACレジスタ != 白デイジー固有の命令の場合)「ACレジスタへ極端に低い適応度を設定」へジャンプ
			dm jmp LABEL_EVAL_FUNC_CALC_FITNESS_EXTREME_LOW_FITNESS
			{
				# ACレジスタへ極端に高い適応度を設定
				dm lac $STRONG_FEEDBACK_EXTREME_HIGH_FITNESS_ADDR

				# 「ACレジスタへ極端に低い適応度を設定」を飛ばす
				dm jmp LABEL_EVAL_FUNC_CALC_FITNESS_SKIP_EXTREME_LOW_FITNESS
			}
			{
				set_label LABEL_EVAL_FUNC_CALC_FITNESS_EXTREME_LOW_FITNESS
				# ACレジスタへ極端に低い適応度を設定
				dm lac $STRONG_FEEDBACK_EXTREME_LOW_FITNESS_ADDR
			}
			set_label LABEL_EVAL_FUNC_CALC_FITNESS_SKIP_EXTREME_LOW_FITNESS

			# 「黒デイジーの適応度を極端に高くする」を飛ばす
			dm jmp LABEL_EVAL_FUNC_CALC_FITNESS_SKIP_HIGH_FITNESS_FOR_BLACK_DAISY
		}
		{
			set_label LABEL_EVAL_FUNC_CALC_FITNESS_HIGH_FITNESS_FOR_BLACK_DAISY
			# 黒デイジーの適応度を極端に高くする

			# ACレジスタへ自身の最初の命令のアドレスを設定
			dm lac $CUR_BINBIO_ADDR
			dm add $OFFSET_TO_INST_LIST_ADDR

			# tmp領域1を用いてACレジスタへ自身の最初の命令を取得する
			dm dac $SYS_TMP_1
			dm lac i $SYS_TMP_1

			# ACレジスタ == 白デイジー固有の命令?
			dm sad $WHITE_DAISY_INST_ADDR
			## (ACレジスタ == 白デイジー固有の命令の場合)「ACレジスタへ極端に低い適応度を設定」へジャンプ
			dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
			## (ACレジスタ != 白デイジー固有の命令の場合)「ACレジスタへ極端に高い適応度を設定」へジャンプ
			dm jmp LABEL_EVAL_FUNC_CALC_FITNESS_EXTREME_HIGH_FITNESS
			{
				# ACレジスタへ極端に低い適応度を設定
				dm lac $STRONG_FEEDBACK_EXTREME_LOW_FITNESS_ADDR

				# 「ACレジスタへ極端に高い適応度を設定」を飛ばす
				dm jmp LABEL_EVAL_FUNC_CALC_FITNESS_SKIP_EXTREME_HIGH_FITNESS
			}
			{
				set_label LABEL_EVAL_FUNC_CALC_FITNESS_EXTREME_HIGH_FITNESS
				# ACレジスタへ極端に高い適応度を設定
				dm lac $STRONG_FEEDBACK_EXTREME_HIGH_FITNESS_ADDR
			}
			set_label LABEL_EVAL_FUNC_CALC_FITNESS_SKIP_EXTREME_HIGH_FITNESS
		}
		set_label LABEL_EVAL_FUNC_CALC_FITNESS_SKIP_HIGH_FITNESS_FOR_BLACK_DAISY
	}
	set_label LABEL_EVAL_FUNC_CALC_FITNESS_SKIP_STRONG_FEEDBACK
}
## 本体
eval_func() {
	# 現在のバイナリ生物を実行し、その結果の地表温度と生育適温の差が
	# 小さいほど高くなるように適応度を算出する

	# 現在のバイナリ生物を実行する
	## 自身のアドレスをACレジスタへ取得
	dm lac $CUR_BINBIO_ADDR
	## ACレジスタへ戻り先アドレスまでのオフセットを加算
	dm add $OFFSET_TO_RET_ADDR_ADDR
	## ACレジスタへJMS命令のオペコードを加算
	## (これでACレジスタにバイナリ生物の命令列を関数として実行するJMS命令ができあがった状態)
	dm add $JMS_OPCODE_ADDR
	## JMS命令実行地点へACレジスタの値を設定(☆)
	dm dac $(calc_oct $SYS_AREA_NEXT + 2)
	## ACレジスタへ現在の地表温度を設定
	dm lac $SURFACE_TEMP_ADDR
	## JMS命令実行地点
	dm jms 0	# ☆によって上書きされる
	## 現在の地表温度へACレジスタの値を設定
	dm dac $SURFACE_TEMP_ADDR

	# 適応度を算出し、ACレジスタへ設定する
	# 使用する関数のコメントアウトを外す
	## P制御のみ
	eval_func_calc_fitness_term_p_only
	## 地表温度と生育適温の差が大きい時は強いフィードバックを掛ける
	# eval_func_calc_fitness_strong_feedback
}

# 突然変異タイプを決め、それを示す値として元サイズとの差を返す
# 引数:
# - tmp領域5: 自身の命令数のアドレス
# 戻り値:
# - ACレジスタ: 元サイズとの差
#   -  1: 追加
#   -  0: 変更
#   - -1: 削除
# 実装上の注意:
# - 元サイズとの差は、負の数を1の補数で表す
# - tmp領域1〜3は書き換えないこと
## 変更のみを選びリターン
select_mutation_type() {
	# ACレジスタへ0(変更)を設定
	dm cla

	# リターン
	dm jmp i $SELECT_MUTATION_TYPE_FUNC_ADDR
}

# 自身の命令列の中から突然変異対象の命令を選ぶ
# 引数:
# - tmp領域1: 「自身のエネルギー - 増殖コスト」の結果
# - tmp領域2: 自身のエネルギーのアドレス
# - tmp領域3: 突然変異するか否か
#             (この処理が呼ばれる時、1(突然変異する)が設定されている)
# - tmp領域4: 新たなバイナリ生物と元とのサイズ差
# - tmp領域5: 新たなバイナリ生物を置く領域の先頭アドレス
# 戻り値:
# - tmp領域6: 突然変異対象の命令の命令列先頭からのオフセット[ワード]
#             (0始まりで先頭から何番目かという値)
# 実装上の注意:
# - tmp領域1〜5は書き換えないこと
select_mutation_target() {
	# 0番目を選ぶ
	dm cla
	dm dac $SYS_TMP_6
}

# 環境の1周期で追加で実施する処理
additional_proc_on_env_cycle() {
	# 地表温度を1上げる
	dm lac $SURFACE_TEMP_ADDR
	dm tad $CONST_1_ADDR
	dm dac $SURFACE_TEMP_ADDR
}

# 実験シナリオ
experimental_scenario_normal() {
	echo "break -e $(calc_oct $ENV_CYCLE_FUNC_ADDR + 1)"
	echo "go $SETUP_AND_INF_ENV_CYCLE_CODE_ADDR"
	for i in $(seq 0 100); do
		local i_ex="$(extend_digit $ENV_CYCLE_DIGITS $i)"

		# 現状をセーブしておく
		echo "sa ${LOG_DIR}/${i_ex}.sav"

		# 現在の地表温度をダンプ
		echo "e -d @${LOG_DIR}/${i_ex}.ST $SURFACE_TEMP_ADDR"

		# 現在のバイナリ生物領域をダンプ
		echo "e @${LOG_DIR}/${i_ex}.BA ${BINBIO_AREA_BEGIN}-${BINBIO_AREA_END}"

		# 続きを実行
		echo 'cont'
	done
	echo 'q'
}
experimental_scenario_disturbance() {
	echo "break -e $(calc_oct $ENV_CYCLE_FUNC_ADDR + 1)"
	echo "go $SETUP_AND_INF_ENV_CYCLE_CODE_ADDR"
	for i in $(seq 0 100); do
		local i_ex="$(extend_digit $ENV_CYCLE_DIGITS $i)"

		# 現状をセーブしておく
		echo "sa ${LOG_DIR}/${i_ex}.sav"

		# 現在の地表温度をダンプ
		echo "e -d @${LOG_DIR}/${i_ex}.ST $SURFACE_TEMP_ADDR"

		# 現在のバイナリ生物領域をダンプ
		echo "e @${LOG_DIR}/${i_ex}.BA ${BINBIO_AREA_BEGIN}-${BINBIO_AREA_END}"

		# 外乱
		if [ $i -eq 50 ]; then
			# 地表温度を100℃にする
			echo "d -d $SURFACE_TEMP_ADDR 100"
		fi

		# 続きを実行
		echo 'cont'
	done
	echo 'q'
}
experimental_scenario() {
	# 使用する方のコメントアウトを外す
	experimental_scenario_normal
	# experimental_scenario_disturbance
}
