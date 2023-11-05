# 初期配置:リターンのみのバイナリ生物1つ、突然変異:追加・変更・削除をランダム
# の実験に依存するパラメータ値や関数定義

# 初期バイナリ生物に関するパラメータ
## 初期バイナリ生物のアドレス
INITIAL_BINBIO_ADDR=014004
## 適応度(10進指定)
INITIAL_BINBIO_FITNESS_DEC=50
## 命令数(10進指定)
INITIAL_BINBIO_NUM_INST_DEC=1
## 命令(関数リターンするJMP I命令のみ)
INITIAL_BINBIO_EXEC_BIN=$(gen_return_inst $INITIAL_BINBIO_ADDR)

# エネルギー消費に関するパラメータ
## 増殖コスト(10進指定)
DIVISION_COST_DEC=100
## 定常的なエネルギー消費量(2の補数の負の値)
CONSTANT_ENERGY_CONSUMPTION=777622	# -0o156 = -110

# その他実験パラメータ
## 命令候補テーブルのインデックスのビットだけ抽出するマスク
INST_CAND_TBL_MASK=000007

# 実験固有の初期設定
experiment_specific_init() {
	# 命令候補テーブル設定
	local ict_last_idx_dec=$(bc <<< "ibase=8;$INST_CAND_TBL_MASK")
	for i in $(seq 0 $ict_last_idx_dec); do
		ict_idx=$(bc <<< "obase=8;$i")
		echo "d -m $(calc_oct $INST_CAND_TBL_BEGIN + $ict_idx) nop"
	done
}

# バイナリ生物の初期配置
setup_initial_binbio() {
	# 開始シグネチャ
	addr=$INITIAL_BINBIO_ADDR
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
	echo "d $addr $INITIAL_BINBIO_EXEC_BIN"

	# 終了シグネチャ
	addr=$(calc_oct $addr + 1)
	echo "d $addr $BINBIO_END_SIG"
}

# 評価関数
## 候補: 戻り値へ適応度100を設定
eval_func_return_fitness_100() {
	dm lac $CONST_100_DEC_ADDR
}
## 候補: 戻り値へ現在の適応度を設定
eval_func_return_current_fitness() {
	# ACレジスタへ自身のアドレスを取得
	dm lac $CUR_BINBIO_ADDR

	# ACレジスタへ適応度までのオフセットを加算
	dm add $OFFSET_TO_FITNESS_ADDR

	# tmp領域1へACレジスタの値(自身の適応度のアドレス)を設定
	dm dac $SYS_TMP_1

	# ACレジスタへtmp領域1に設定されているアドレスが指す先の値
	# (自身の適応度)を取得
	dm lac i $SYS_TMP_1
}
## 本体
## 戻り値:
## - ACレジスタ: 適応度(0〜100)
eval_func() {
	# 使用したい評価関数のコメントアウトを外す

	# 戻り値へ適応度100を設定
	# eval_func_return_fitness_100

	# 戻り値へ現在の適応度を設定
	eval_func_return_current_fitness
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
select_mutation_type() {
	# ランダムに追加・変更・削除のいずれかを選びリターン
	# ただし、自身の命令数が1なら突然変異タイプは「追加」とする

	# ACレジスタへ自身の命令数を取得
	## ACレジスタへtmp領域5に設定されているアドレスが指す先の値
	## (自身の命令数)を取得
	dm lac i $SYS_TMP_5

	# 自身の命令数 == 1?
	dm sad $CONST_1_ADDR
	## (自身の命令数 == 1の場合)「突然変異タイプが追加のみの場合」へジャンプ
	dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
	## (自身の命令数 != 1の場合)「突然変異タイプを選ぶ場合」へジャンプ
	dm jmp $(calc_oct $SYS_AREA_NEXT + 3)
	{
		# 突然変異タイプが追加のみの場合(2ワード)

		# ACレジスタへ元サイズとの差として1を設定
		dm lac $CONST_1_ADDR

		# リターン
		dm jmp i $SELECT_MUTATION_TYPE_FUNC_ADDR
	}
	{
		# 突然変異タイプを選ぶ場合(14ワード)

		# 突然変異のタイプを決める(2ワード)
		## ACレジスタへ乱数を取得
		dm jms $GEN_RAND_FUNC_ADDR
		## ACレジスタの下位2ビットを抽出
		## これが突然変異タイプになる
		## - 0: 削除
		## - 1: 変更
		## - 2あるいは3: 追加
		dm and $CONST_3_ADDR

		# タイプ別の処理(12ワード)
		## ACレジスタ == 0の時、次の命令をスキップ
		dm sza
		## (ACレジスタ != 0の時)追加あるいは変更の場合へジャンプ
		dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
		## (ACレジスタ == 0の時)削除の場合へジャンプ
		dm jmp $(calc_oct $SYS_AREA_NEXT + 10)	# 0o10 = 8
		{
			# 追加あるいは変更の場合(7ワード)

			# ACレジスタ != 1の時、次の命令をスキップ
			dm sad $CONST_1_ADDR
			## (ACレジスタ == 1の時)変更の場合へジャンプ
			dm jmp $(calc_oct $SYS_AREA_NEXT + 2)
			## (ACレジスタ != 1の時)追加の場合へジャンプ
			dm jmp $(calc_oct $SYS_AREA_NEXT + 3)
			{
				# 変更の場合(2ワード)

				# ACレジスタへ元サイズとの差として0を設定
				dm cla

				# リターン
				dm jmp i $SELECT_MUTATION_TYPE_FUNC_ADDR
			}
			{
				# 追加の場合(2ワード)

				# ACレジスタへ元サイズとの差として1を設定
				dm lac $CONST_1_ADDR

				# リターン
				dm jmp i $SELECT_MUTATION_TYPE_FUNC_ADDR
			}
		}
		{
			# 削除の場合(2ワード)

			# ACレジスタへ元サイズとの差として-1(1の補数)を設定
			dm lac $CONST_1_ADDR
			dm cma
		}
	}

	# リターン
	# ※ ここに来るのは「突然変異タイプを選ぶ場合」かつ「削除の場合」であるはず
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
	# 自身の命令列で最後の命令(リターン命令)も含めた中からランダムに選ぶ

	# MQレジスタへ乱数を設定
	## ACレジスタへ乱数を取得
	dm jms $GEN_RAND_FUNC_ADDR
	## MQレジスタへACレジスタの値を設定
	dm lmq

	# tmp領域6へ自身の命令数のアドレスを設定
	## 自身のアドレスをACレジスタへ取得
	dm lac $CUR_BINBIO_ADDR
	## ACレジスタへ命令数までのオフセットを加算
	dm add $OFFSET_TO_NUM_INST_ADDR
	## tmp領域6へACレジスタの値を設定
	dm dac $SYS_TMP_6

	# ACレジスタへ自身の命令数を設定
	## ACレジスタへtmp領域6に設定されているアドレスが指す先の値を設定
	dm lac i $SYS_TMP_6

	# DIV命令の次のアドレスをシェル変数へ設定
	div_next_addr=$(calc_oct $SYS_AREA_NEXT + 4)
	{
		# DIV命令の次のアドレスまでのカウント用

		# DIV命令の次のアドレスへACレジスタの値を設定(オフセット0)
		dm dac $div_next_addr

		# Lレジスタをクリア(オフセット1)
		dm cll

		# ACレジスタをクリア(オフセット2)
		dm cla

		# ((AC << 18) + MQ) / (DIV命令の次のアドレスの値)の商をMQレジスタへ、余りをACレジスタへ設定(オフセット3)
		dm div
		## 除数を配置するために1ワード進める(オフセット4)
		SYS_AREA_NEXT=$(calc_oct $SYS_AREA_NEXT + 1)
	}

	# tmp領域6へACレジスタの値を設定
	dm dac $SYS_TMP_6
}

# 実験固有の周期毎の事後処理
post_simh_commands_by_cycle() {
	# 特に無し
	return
}
