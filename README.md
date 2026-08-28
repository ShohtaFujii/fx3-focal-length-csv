# FX3 Focal Length CSV Tool

Sony FX3（および他のSonyカメラ）で撮影したMP4クリップに埋め込まれているRTMD
（Real-Time MetaData）タイムドメタデータから、実際の焦点距離
（`LensZoom (Actual Focal Length)`）をフレーム単位で読み取り、クリップごとの
開始／最小／最大焦点距離をCSVにまとめるMac用ツールです。

Sony純正Eマウントレンズ（本ツールはFE 24-70mm F2.8 GM IIで検証済み）で撮影
した場合、カメラとレンズの電子通信内容が動画内部のタイムドメタデータ
（`rtmd`ストリーム）に記録されます。このツールはその生データを直接パースして、
ズーム中の焦点距離の変化も含めて抽出します。

## 使い方

1. `fx3_focal_length.command` をFinder上の好きな場所に置く。
2. 解析したいクリップが入ったフォルダを、このファイルのアイコンにドラッグ＆
   ドロップする（ドラッグが効かない環境では、ダブルクリックすると代わりに
   フォルダ選択ダイアログが出ます）。
3. Terminalが開き、クリップを1本ずつ解析します。
4. 完了すると、ドロップしたフォルダの直下に
   `focal_length_report_YYYYMMDD_HHMMSS.csv` が作成されます。

フォルダはサブフォルダも含めて再帰的にスキャンするので、複数のクリップフォル
ダをまとめて持つ親フォルダを1つドロップすれば、その配下全部を1本のCSVにまと
められます。

### 出力されるCSVの列

| 列 | 内容 |
|---|---|
| `Clip` | クリップの相対パス |
| `Start_mm` | クリップ先頭フレームの焦点距離(mm) |
| `Min_mm` / `Max_mm` | クリップ内での焦点距離の最小値・最大値(mm) |
| `Zoomed` | クリップ内でズームがあった場合 `YES` |
| `Frames` | 焦点距離を取得できたフレーム数 |
| `Status` | `OK`、またはスキップ理由（レンズ通信情報が記録されていない等） |

## 必要な環境

- macOS
- [ffmpeg](https://ffmpeg.org/)（`ffprobe`コマンドを使用）
  - 未インストールの場合、スクリプトが自動で案内します。Homebrewが入っていれば
    `brew install ffmpeg` を自動実行します。
- Python 3（macOS標準の `/usr/bin/python3` で動作）

## 仕組み

Sonyの`rtmd`ストリームは、映像フレームごとに1つのメタデータサンプルを持つ
タイムドメタデータトラックです。各サンプルは、SMPTE RP210系のタグ(2byte)・
長さ(2byte)・値、という単純なTLV形式が入れ子になった構造をしており、
`0x8005`タグに「実際の焦点距離」が、Sony独自の圧縮浮動小数点形式
（12bit仮数部 × 10^(4bit符号付き指数部)、単位はメートル）で格納されています。

本ツールは `ffprobe` で各クリップの`rtmd`ストリームのパケット位置
（バイトオフセットとサイズ）を取得し、そのバイト範囲を直接読み取って上記の
パース処理をPythonで行っています。Rust/Cargoのビルド環境は一切不要です。

### クリップによって値が取得できない場合

`Status`列に `RTMD present but no focal length tag` と出るクリップは、
このツールの不具合ではなく、**カメラ自身がそのクリップの撮影時にレンズと
電子的に通信できていなかった**ことを示しています。同梱のXMLサイドカー
（`...M01.XML`）内の `LensControlInformation` が `status="none"` になって
おり、`<Lens modelName=.../>` の記載自体が存在しません。レンズがきちんと
ロックされていなかった、あるいはカメラ側の「レンズなしレリーズ」設定が
有効になっていた等が典型的な原因です。

## クレジット

RTMDのタグ体系・パース方法は、[AdrianEddy/telemetry-parser]
(https://github.com/AdrianEddy/telemetry-parser)（`src/sony/rtmd_tags.rs`,
`src/sony/mod.rs`、MIT OR Apache-2.0）の実装を参考に、Rustのロジックを
Pythonへ移植したものです。素晴らしいリバースエンジニアリングと実装に感謝します。

> Copyright © 2021 Adrian \<adrian.eddy at gmail\>
> Licensed under MIT OR Apache-2.0

## ライセンス

このリポジトリ自体は [MIT License](LICENSE) の下で公開しています。
