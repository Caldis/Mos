<p align="center">
  <a href="https://mos.caldis.me/">
    <img width="160" src="assets/readme/app-icon.png" alt="Mos app icon">
  </a>
</p>

<h1 align="center">Mos</h1>

<p align="center">
  macOS のマウスホイールスクロールをトラックパッドのようになめらかにしながら、マウスらしい精密な操作感を保ちます。
</p>

<p align="center">
  <a href="https://github.com/Caldis/Mos/releases"><img alt="Latest release" src="https://img.shields.io/github/v/release/Caldis/Mos?style=flat-square"></a>
  <img alt="macOS 10.13+" src="https://img.shields.io/badge/macOS-10.13%2B-black?style=flat-square&logo=apple">
  <img alt="Swift 5" src="https://img.shields.io/badge/Swift-5.0-orange?style=flat-square&logo=swift">
  <a href="LICENSE"><img alt="License: CC BY-NC 4.0" src="https://img.shields.io/badge/license-CC%20BY--NC%204.0-lightgrey?style=flat-square"></a>
</p>

<p align="center">
  <a href="README.md">中文</a> ·
  <a href="README.enUS.md">English</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.id.md">Bahasa Indonesia</a>
</p>

<p align="center">
  <a href="https://mos.caldis.me/">ホームページ</a> ·
  <a href="https://github.com/Caldis/Mos/releases">ダウンロード</a> ·
  <a href="https://github.com/Caldis/Mos/wiki">Wiki</a> ·
  <a href="https://github.com/Caldis/Mos/discussions">Discussions</a>
</p>

<p align="center">
  <img src="assets/readme/en-us/application-settings.png" alt="Mos per-app scroll settings" width="920">
</p>

## なぜ Mos なのか

macOS では通常のマウスホイールスクロールがぎこちなく感じられることがあります。ホイールの精度が足りず、トラックパッドのような連続的で予測しやすい慣性が得られにくいためです。Mos はマウスホイールイベントを受け取り、生のデルタ値を補間してよりなめらかなスクロールに変換しながら、アプリ、軸、ボタンごとの挙動を自分で制御できるようにします。

また、Mos を使えば任意のマウスボタンを再割り当てしたり、動作を書き換えたりして、自分のワークフローに合わせられます。

Mos は macOS 10.13 以降に対応した、無料のオープンソースメニューバーユーティリティです。

## 機能ハイライト

- **スムーズスクロール**: 最小ステップ、速度ゲイン、持続時間を調整でき、トラックパッドを模擬するモードも使えます。
- **軸ごとの独立設定**: 垂直/水平スクロールのスムージングと反転を別々に設定できます。
- **スクロールホットキー**: 加速、方向変換、スムーズスクロールの一時無効化に任意のキーを割り当てられます。
- **アプリ別プロファイル**: 各 App はグローバル設定を継承することも、スクロール、ショートカット、ボタン割り当てを個別に上書きすることもできます。
- **ボタン割り当て**: マウス、キーボード、カスタムイベントを記録し、システム操作、ショートカット、App 起動、スクリプト実行、ファイルを開く操作に割り当てられます。
- **アクションライブラリ**: Mission Control、Spaces、スクリーンショット、Finder 操作、文書編集、マウススクロールなどのアクションを内蔵しています。
- **Logi/HID++ サポート**: Bolt、Unifying レシーバー、Bluetooth 直結デバイスの Logitech ボタンイベントに対応し、Logi 固有のアクションも扱えます。

## スクリーンショット

| スクロール調整 | アプリ別プロファイル |
| --- | --- |
| <img src="assets/readme/en-us/scrolling.png" alt="Mos scroll settings" width="420"> | <img src="assets/readme/en-us/application-settings.png" alt="Mos per-app profile settings" width="420"> |

| App、スクリプト、ファイルを開く | アクションライブラリ |
| --- | --- |
| <img src="assets/readme/en-us/buttons-open.png" alt="Mos open action" width="420"> | <img src="assets/readme/en-us/buttons-action.png" alt="Mos action library" width="420"> |

## ダウンロードとインストール

### 手動インストール

[GitHub Releases](https://github.com/Caldis/Mos/releases) から最新ビルドをダウンロードし、展開して `Mos.app` を `/Applications` に移動してください。

初回起動時に、macOS が Mos へのアクセシビリティ権限を求める場合があります。Mos はスクロールイベントを読み取り、書き換えるためにこの権限を必要とします。権限を付与しても動作しない場合は、[権限トラブルシューティングガイド](https://github.com/Caldis/Mos/wiki/If-the-App-not-work-properly) を参照してください。

### Homebrew

Homebrew でアプリを管理している場合:

```bash
brew install --cask mos
```

更新:

```bash
brew update
brew upgrade --cask mos
```

## コントリビューション

Mos はシステム入力、アクセシビリティ権限、Logi/HID デバイス、永続化されたユーザー設定を扱う小さなユーティリティです。保守コストと回帰リスクは現実的な問題なので、小さく焦点の絞られた変更を強く歓迎します。

Logi/HID、アクセシビリティ、署名、notarization、アプリ更新、実機テストに触れる変更はリスクが高めです。大きな PR を開く前に、issue または Discussions で背景を説明してください。

PR の説明には、変更の動機、検証方法、考えられる挙動への影響を書いてください。

> AI によって書かれたコードはすでに一般的になっており、多くの PR が AI 支援で作られていることも理解しています。私たち自身の作業も例外ではありません。ただし、提出者はすべての変更行が実際に何をするのかを理解し、整理し、検証する責任があります。PR のレビューには必ずコストがかかるためです。

### とても歓迎するもの

- 再現手順または検証メモのある小さなバグ修正。
- レイアウト、文言、読みやすさ、オンボーディングなどの UI/UX の小さな改善。
- 権限状態のより安全な扱い、入力保護、境界チェックなどの小さなセキュリティ強化。
- ローカライズ、ドキュメント、テストの改善。
- 単一テーマで、変更行数が少なく、レビュー範囲が明確な PR。

### 現時点ではマージしないもの

- 事前に議論されていない大きな新機能、モジュール、アーキテクチャの書き換え。
- 大量の AI 生成リライト、フォーマット変更、移行、ついでのクリーンアップ。
- 入力イベント処理、権限プロンプト、アプリ更新、既存ユーザーデータの読み取り、永続化形式に影響する挙動変更。
- ネイティブ話者が確認できない大規模な機械翻訳セット。

あらゆる形の貢献を歓迎します。提案やフィードバックがある場合は、[issue](https://github.com/Caldis/Mos/issues) を開いてください。

機能追加に強い関心がある場合は、まず [Discussions](https://github.com/Caldis/Mos/discussions) から始めてください。

## 謝辞

- [Charts](https://github.com/danielgindi/Charts)
- [LoginServiceKit](https://github.com/Clipy/LoginServiceKit)
- [Sparkle](https://github.com/sparkle-project/Sparkle)
- [Smoothscroll-for-websites](https://github.com/galambalazs/smoothscroll-for-websites)
- [Solaar](https://github.com/pwr-Solaar/Solaar)

## License

Copyright (c) 2017-2026 Caldis. All rights reserved.

Mos は [CC BY-NC 4.0](http://creativecommons.org/licenses/by-nc/4.0/) のもとでライセンスされています。Mos を App Store にアップロードしないでください。
