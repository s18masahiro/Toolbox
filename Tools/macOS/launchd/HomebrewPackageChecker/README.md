# HomebrewPackageChecker（launchd 版）

Homebrew の `update` → `outdated` → `doctor` をまとめて実行し、結果を Markdown レポートに保存して通知で知らせるシェルスクリプトです。launchd（LaunchAgent）で毎週月曜 9:00 に自動実行します。

ショートカット.app で動かしたい場合は [Shortcuts 版](../../Shortcuts/HomebrewPackageChecker/README.md) を使ってください。

## 利用条件

1. ターミナルからコマンド実行できるなど、基礎知識があること
   1. スクリプトの登録や、パッケージのアップデートを手動実行するために必要

## 動作

1. `brew update` でパッケージ情報を更新
2. `brew outdated --formula` / `--cask` で更新可能なパッケージを一覧化
3. `brew doctor` で環境を診断し、`Warning:` の件数を数える
4. `reports/brew-check-YYYY-MM-DD.md` にレポートを保存し、`logs/brew-check.log` に実行結果を追記
5. 結果を通知「brew check」で表示

`brew upgrade` は実行しません（確認のみ）。90日より古いレポートは自動で削除されます。

### 通知メッセージ

| 状態 | 通知 |
|---|---|
| `brew` が見つからない | brew が見つかりませんでした |
| `brew update` 失敗 | brew update に失敗しました。レポートを確認してください |
| 更新あり / 警告あり | 更新 N 件（formula N / cask N）、doctor 警告 N 件 |
| 問題なし | すべて最新です。問題はありません |

## 必要なもの、事前準備

- macOS
- [Homebrew](https://brew.sh/)（`/opt/homebrew/bin` または `/usr/local/bin`）
- 通知を表示するには「システム設定 → 通知」で「スクリプトエディタ」の通知を許可する（`osascript` の通知はスクリプトエディタ名義で届きます）

## ファイル構成

| ファイル | 内容 |
|---|---|
| `brew-check.sh` | チェック本体。レポート作成と通知を行う |
| `install.sh` | LaunchAgent の plist を生成して登録する |
| `uninstall.sh` | LaunchAgent の登録を解除して plist を削除する |

## インストール

このフォルダを置きたい場所に配置してから、次を実行します。

```sh
./install.sh
```

- `~/Library/LaunchAgents/com.masahiro.brew-check.plist` が作られ、launchd に登録されます
- plist にはこのフォルダの絶対パスが書き込まれるため、**フォルダを移動したら `install.sh` を再実行**してください
- 再実行しても、既存の登録を解除してから登録し直すので問題ありません

### 動作確認（今すぐ実行）

```sh
launchctl kickstart gui/$(id -u)/com.masahiro.brew-check
```

手動で直接実行することもできます。

```sh
./brew-check.sh
```

## アンインストール

```sh
./uninstall.sh
```

`reports/` と `logs/` は残るので、不要なら手動で削除してください。

## 設定

### 実行タイミング

`install.sh` 内の `StartCalendarInterval` を変更し、`install.sh` を再実行します。

| キー | 既定値 | 内容 |
|---|---|---|
| `Weekday` | `1` | 曜日（0 と 7 が日曜、1 が月曜） |
| `Hour` | `9` | 時 |
| `Minute` | `0` | 分 |

- 指定時刻に Mac がスリープしていた場合は、復帰後に実行されます
- 電源オフ・ログアウト中だった場合は実行されません

### スクリプト内の設定

`brew-check.sh` 冒頭の変数で変更できます。

| 変数 | 既定値 | 内容 |
|---|---|---|
| `REPORT_DIR` | `<このフォルダ>/reports` | レポートの保存先 |
| `KEEP_DAYS` | `90` | これより古いレポートを削除 |

### ラベル

LaunchAgent のラベルは `install.sh` / `uninstall.sh` の `LABEL`（既定 `com.masahiro.brew-check`）です。変更する場合は両方をそろえてください。

## 出力例

```
HomebrewPackageChecker/
├── reports/
│   └── brew-check-2026-10-26.md   # レポート（概要表・更新可能な formula / cask・brew doctor の出力）
└── logs/
    ├── brew-check.log             # [2026-10-26 09:00:05] 完了: 更新 3 件 / doctor 警告 0 件 → ...
    └── brew-check.err.log         # エラー出力
```

更新する場合はレポート末尾の案内どおり `brew upgrade`（cask も含めるなら `brew upgrade --greedy`）を手動で実行してください。

## オプション：Claude Cowork でリリースノートをまとめる

更新可能なパッケージのリリースノートまで調べた詳細レポートを Claude Cowork で定期的に作りたい場合は、[brew-release-notes](../../../../AI-Instructions/Claude/brew-release-notes/README.md) スキルを利用してください。

- このツールのレポート（`brew-check-YYYY-MM-DD.md`）を読み、セキュリティ修正・破壊的変更をまとめた `release-notes-YYYY-MM-DD.md` を同じフォルダに書き出します
- Cowork のセッションまたはプロジェクトに、`reports/` フォルダを紐づけて使います
