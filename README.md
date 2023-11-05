# PDP-7版DaisyOS

同人誌「よりシンプルなバイナリ生物学の本」で解説した設計のPoC実装です。

ここでは、このリポジトリ内のスクリプトの説明や、使い方を紹介します。

そもそも「DaisyOSとは何なのか」といった所などは上記の同人誌をご覧ください。同人誌の情報は↓のウェブサイトにまとめています。

- 作者ウェブサイト
  - http://yuma.ohgami.jp/

## 各スクリプトの説明

- `daisy-os-pdp7.sh`
  - 書式: `./daisy-os-pdp7.sh`
    - `PDP7_CMD`というシェル変数を指定して実行することで、実行時に使用される`pdp7`コマンドを変更できる
      - 例: `PDP7_CMD=pdp7-debug ./daisy-os-pdp7.sh`
  - SimHというシミュレータ上で実行可能なPDP-7プログラム(SimHスクリプト)の形式でDaisyOSのプログラムを生成し、シミュレータ上で実行する
  - 実行時に生成されるファイル/ディレクトリ
    - `daisy-os-pdp7.simh`: SimHスクリプト形式のDaisyOSのプログラム
    - `daisy-os-pdp7.map`: 内部的な各関数のアドレスが書かれているファイル
    - `LOG-<年月日時分秒>`: 実行時の`daisy-os-pdp7.sh`と`config.sh`自体のコピーや、実験に応じたログを保存するディレクトリ(以降、「ログディレクトリ」と呼ぶ)
- `config.sh`
  - 実験設定が書かれたファイルへのシンボリックリンク
  - `daisy-os-pdp7.sh`は実験設定を、`config.sh`というファイルから読み込む
  - このファイルをシンボリックリンクにしておくことで、実験の切り替えをしやすくしている
    - が、上述の通り、`config-a_ret-random_imd.sh`は現状では動かないと思われるので、実質、今動くのは`config-daisy-world.sh`の実験のみ
- `config-daisy-world.sh`
  - デイジーワールド実験の設定が書かれたファイル
  - 実験のシナリオとしては、環境周期毎に地表温度が1℃ずつ上がっていく状況で、環境周期100周期分のデイジーワールド環境を実行する
    - このスクリプト内の`experimental_scenario`関数内でコメントアウトする行を切り替えることで、「環境周期50周期目に地表温度を100℃にする」という外乱を与える実験を行える
  - この実験固有でログディレクトリに生成されるファイル
    - ※: 環境周期0は初期状態を示す
    - `<環境周期>.BA`: ファイル名の環境周期を終えた時点のバイナリ生物領域のメモリダンプ(8進数表記)
    - `<環境周期>.ST`: ファイル名の環境周期を終えた時点の地表温度
      - コロン(`:`)区切りの、左側が地表温度の変数のアドレス(8進数表記)、右側が地表温度(10進数表記)
    - `<環境周期>.sav`: ファイル名の環境周期を終えた時点のシミュレータの状態をSimHの`save`コマンドで保存したもの
- `config-a_ret-random_imd.sh`
  - 「初期配置:リターンのみのバイナリ生物1つ、突然変異:追加・変更・削除をランダム」という実験の設定が書かれたファイル
  - ただ、`config-daisy-world.sh`の実験設定を作り込んでいる中で増えた設定項目をこのファイルへ反映していないと思うので、今はうまく動かないかも
- `batch-normal-expr.sh`
  - 書式: `./batch-normal-expr.sh <実験回数>`
  - 指定された回数分、`daisy-os-pdp7.sh`を繰り返し実行する
  - 実行毎に標準出力へ以下のフォーマットの行を出力する
    - i=<実行番目> [<実行開始日時>] <ログディレクトリ名> [<実行終了日時>]
  - 実行時の標準出力を`expr.log`、標準エラー出力を`expr.err`というファイル名でログディレクトリへ保存する
- `daisy-world-log-analysis-tools/`
  - デイジーワールド実験のログ分析ツールをこのディレクトリにまとめている
  - `make-report.sh`
    - 書式: `./make-report.sh [<ログディレクトリ名>]`
      - ログディレクトリの指定が無い場合、カレントディレクトリに存在する最新のログディレクトリが選択される
    - ログディレクトリ内のデータから、以下のフィールドを持つCSVを生成する
      - 環境周期
      - 地表温度
      - 個体数
      - 白デイジー個体数
      - 黒デイジー個体数
    - 生成したCSVは`report2.csv`というファイル名でログディレクトリへ保存する
  - `make-result-st-file.sh`
    - 書式: `./make-result-st-file.sh`
    - カレントディレクトリ内の全ログディレクトリで、環境周期100周期分の地表温度を`result-st.txt`というファイル名でログディレクトリへ保存する
  - `make-result-err-file.sh`
    - 書式: `./make-result-err-file.sh`
    - カレントディレクトリ内の全ログディレクトリで、`result-st.txt`を元に、各環境周期の「地表温度 - 生育適温(20℃)」(以降、これを「誤差」と呼ぶ)を算出する
    - 算出した結果は`result-err.txt`というファイル名でログディレクトリへ保存する
  - `make-sorted-st-file.sh`
    - 書式: `./make-sorted-st-file.sh`
    - カレントディレクトリ内の全ログディレクトリで、`result-st.txt`を昇順にソートした結果を`sorted-st.txt`に保存する
  - `make-sorted-err-file.sh`
    - 書式: `./make-sorted-err-file.sh`
    - カレントディレクトリ内の全ログディレクトリで、`result-err.txt`を昇順にソートした結果を`sorted-err.txt`に保存する
  - `report-pct.sh`
    - 書式: `./report-pct.sh`
    - カレントディレクトリ内の各ログディレクトリの`sorted-err.txt`から、それぞれの実験における誤差のパーセンタイルを算出し、以下のフィールドを持つCSVとして、カレントディレクトリに`report-pct.csv`というファイル名で保存する
      - ログディレクトリ名
      - 50パーセンタイル
      - 90パーセンタイル
      - 95パーセンタイル
  - `visualize-binbioarea.sh`
    - 書式: `./visualize-binbioarea.sh <ログディレクトリ名> <環境周期>`
    - 指定されたログディレクトリの環境周期時点のバイナリ生物領域を可視化する
    - 可視化の方法としては、4096ワードのバイナリ生物領域を64x64ピクセルので以下のように色分けする
      - 白色: 白いデイジーのバイナリ生物が存在する領域
      - 黒色: 黒いデイジーのバイナリ生物が存在する領域
      - 灰色: バイナリ生物が居ない領域
    - 可視化した結果はPGM形式の画像ファイルで`<環境周期>.pgm`というファイル名でログディレクトリへ保存する

## 使い方

`daisy-os-pdp7.sh`を実行すれば、PDP-7版DaisyOSのSimH向けプログラムの生成と実行が行われますが、その際にどのような実験設定やシナリオで動作するかは同じディレクトリに存在する`config.sh`の内容によります。

ここでは、`config.sh`がデイジーワールド実験のもの(`config-daisy-world.sh`)である場合の使用例を紹介します。

### 1回分の実験を行う

`daisy-os-pdp7.sh`を実行することで、1回分の実験を行います。デイジーワールド実験の場合、環境周期100周期分の実行が行われ、そのログがログディレクトリへ保存されます。

書式:
```sh
$ ./daisy-os-pdp7.sh
```

### N回分の実験を行う

N回分の実験を行う際、単純に`./daisy-os-pdp7.sh`を`for`で繰り返し実行すれば良いです。

ただ、その際に「各実験の開始/終了時刻やログディレクトリ名の表示」や「`./daisy-os-pdp7.sh`実行時の標準出力/標準エラー出力の保存」を行おうと思うと、その都度書くのは少し面倒なので、スクリプト化したものを`batch-normal-expr.sh`というファイル名で用意しています。

書式:
```sh
$ ./batch-normal-expr.sh <実験回数>
```
