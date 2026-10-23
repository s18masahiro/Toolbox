# launchd

macOS に標準搭載されているサービス管理フレームワーク「launchd」の自作設定ファイルをまとめてあるディレクトリです。

## 注意事項

### 環境・権限

- **PATH が最小限**: launchd から起動されたジョブはシェルの設定（`.zshrc` など）を読み込みません。`PATH` は `/usr/bin:/bin:/usr/sbin:/sbin` 程度なので、`brew` などはスクリプト内で `PATH` を設定するか、絶対パスで呼び出してください
- **絶対パスが必要**: plist 内のパスに `~` や環境変数は使えません。スクリプトを置いたフォルダを移動したら、plist を作り直して再登録が必要です
- **プライバシー保護（TCC）**: 「書類」「デスクトップ」「ダウンロード」、iCloud Drive などにアクセスするジョブは権限エラーで失敗することがあります。スクリプトはこれら以外の場所に置くか、「システム設定 → プライバシーとセキュリティ → フルディスクアクセス」で `/bin/bash` などを許可してください
- **バックグラウンド項目**: macOS 13 以降、登録時に「バックグラウンド項目が追加されました」と通知されます。「システム設定 → 一般 → ログイン項目と機能拡張」でオフにするとジョブは実行されません

### 実行タイミング

- `~/Library/LaunchAgents` に置いたジョブ（LaunchAgent）は、そのユーザーがログインしている間だけ動きます
- `StartCalendarInterval` の時刻にスリープしていた場合は、復帰後に1回だけ実行されます（複数回分が溜まっても1回）
- 電源オフ・ログアウト中だった時刻の分は実行されません

### 登録・確認

- plist を編集しても自動では反映されません。`launchctl bootout` → `launchctl bootstrap` で登録し直してください
- `launchctl load` / `unload` は古い書き方です。`bootstrap` / `bootout` を使ってください
- plist の書式は `plutil -lint <plist>` で確認できます
- `StandardOutPath` / `StandardErrorPath` を指定しないと、出力はどこにも残りません
- 登録状況や直近の終了コードは次のコマンドで確認できます

  ```sh
  launchctl print gui/$(id -u)/<ラベル>
  ```

## リンク

- [Macの「ターミナル」でのlaunchdを使ったスクリプトの管理 - Apple サポート (日本)](https://support.apple.com/ja-jp/guide/terminal/apdc6c1077b-5d5d-4d35-9c19-60f2397b2369/mac)
