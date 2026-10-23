#!/bin/bash
# Homebrew 週次チェック: update → outdated → doctor を実行し、
# reports/ に Markdown レポートを保存して macOS 通知を出す。
set -u

# launchd は最小限の PATH で起動するため明示的に設定
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export HOMEBREW_NO_AUTO_UPDATE=1   # update は下で明示的に実行
export HOMEBREW_NO_ENV_HINTS=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPORT_DIR="$SCRIPT_DIR/reports"
KEEP_DAYS=90                       # これより古いレポートは削除
mkdir -p "$REPORT_DIR"

DATE="$(date +%Y-%m-%d)"
REPORT="$REPORT_DIR/brew-check-$DATE.md"

notify() {
  /usr/bin/osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
}

BREW="$(command -v brew || true)"
if [ -z "$BREW" ]; then
  echo "[$(date '+%F %T')] brew が見つかりません" >&2
  notify "brew check" "brew が見つかりませんでした"
  exit 1
fi

echo "[$(date '+%F %T')] 開始"

# 1. update
UPDATE_OUT="$("$BREW" update 2>&1)"; UPDATE_RC=$?

# 2. outdated
FORMULA_OUT="$("$BREW" outdated --formula --verbose 2>&1)"
CASK_OUT="$("$BREW" outdated --cask --verbose 2>&1)"
FORMULA_N=$(printf '%s' "$FORMULA_OUT" | grep -c . || true)
CASK_N=$(printf '%s' "$CASK_OUT" | grep -c . || true)
TOTAL=$((FORMULA_N + CASK_N))

# 3. doctor（警告があると終了コード 1 を返す）
DOCTOR_OUT="$("$BREW" doctor 2>&1)"; DOCTOR_RC=$?
WARN_N=$(printf '%s\n' "$DOCTOR_OUT" | grep -c '^Warning:' || true)

block() { if [ -n "$1" ]; then printf '```\n%s\n```\n' "$1"; else printf '%s\n' "$2"; fi; }

{
  echo "# brew check — $DATE"
  echo
  echo "| 項目 | 結果 |"
  echo "|---|---|"
  echo "| brew update | $([ $UPDATE_RC -eq 0 ] && echo OK || echo "失敗 (rc=$UPDATE_RC)") |"
  echo "| 更新可能 formula | $FORMULA_N |"
  echo "| 更新可能 cask | $CASK_N |"
  echo "| brew doctor 警告 | $WARN_N |"
  echo
  echo "## 更新可能な formula"
  block "$FORMULA_OUT" "なし"
  echo
  echo "## 更新可能な cask"
  block "$CASK_OUT" "なし"
  echo
  echo "## brew doctor"
  block "$DOCTOR_OUT" "出力なし"
  if [ $UPDATE_RC -ne 0 ]; then
    echo
    echo "## brew update 出力"
    block "$UPDATE_OUT" ""
  fi
  echo
  echo "---"
  echo "更新するには: \`brew upgrade\`（cask も含める場合は \`brew upgrade --greedy\`）"
} > "$REPORT"

# 古いレポートを削除
find "$REPORT_DIR" -name 'brew-check-*.md' -mtime +"$KEEP_DAYS" -delete 2>/dev/null || true

# 通知
if [ $UPDATE_RC -ne 0 ]; then
  notify "brew check" "brew update に失敗しました。レポートを確認してください"
elif [ $TOTAL -gt 0 ] || [ $WARN_N -gt 0 ]; then
  notify "brew check" "更新 ${TOTAL} 件（formula ${FORMULA_N} / cask ${CASK_N}）、doctor 警告 ${WARN_N} 件"
else
  notify "brew check" "すべて最新です。問題はありません"
fi

echo "[$(date '+%F %T')] 完了: 更新 $TOTAL 件 / doctor 警告 $WARN_N 件 → $REPORT"
