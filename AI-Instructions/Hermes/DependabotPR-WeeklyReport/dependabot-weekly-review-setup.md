# Dependabot 週次レビュー ジョブ セットアップガイド

> **このファイルの使い方（人間向け）**
> AI エージェント（Hermes Agent を想定）にこのファイルを渡して、
> 「このガイドに沿って Dependabot 週次レビューのジョブを作って」と依頼してください。
> エージェントはあなたのローカルリポジトリを調べて**判定基準の案を作り、あなたの確認を受けてから**、試しのレポートを見せたうえで定期ジョブを登録します。

## これは何か

Dependabot が作成した PR を週に一度レビューし、次の内容をまとめたレポートを **GitHub Issue** として残すジョブを作ります。

- **PR ごとの判定**：マージ前にプレビューデプロイで確認すべきか
  - A：プレビュー必須
  - B：プレビュー推奨
  - S：ローカル確認のみ
  - C：CI が通ればマージ可
- **推奨マージ順**
- **CI では気づきにくい点の自動検出**
  - 依存ツリーで新たに発生した重複
  - lockfile にある、更新対象以外の変化
  - ネイティブパッケージのバージョン整合（例：あるパッケージが内部で使っているバイナリと、自分で直接入れているバイナリのバージョンがずれていないか）
  - Dependabot の対象外にしているパッケージのバージョン整合
  - リリースノートに含まれる破壊的変更やセキュリティ修正

**判定の区分（A / B / S / C）はどのリポジトリでも共通です。** 一方、どのパッケージをどの区分に入れるかという判定基準は、リポジトリごとに大きく変わります。このガイドでは、判定基準をリポジトリの中身（依存パッケージ、ソースコードでの使われ方、CI、ドキュメント）から作り、ユーザーの確認を受けてから確定します。

想定している環境は、プレビューデプロイのストレージに上限があり（例：Vercel Hobby）、**Dependabot の PR ではプレビューを自動作成せず、必要なものだけ手動で作る**運用です。プレビューを自動で作る運用でも、判定とマージ順のレポートとしてそのまま使えます。

**ジョブはレポートを作るだけです。** PR のマージ、承認、コメント、push、デプロイは行いません。

## 前提条件

| 項目 | 必須 | 備考 |
|---|---|---|
| GitHub リポジトリ + Dependabot（npm エコシステム） | ✅ | `.github/dependabot.yml` |
| リポジトリのローカルクローン（依存パッケージをインストール済み） | ✅ | 判定基準の作成と、PR ごとの検証（一時的な作業ツリー `git worktree` を使う）に使います |
| GitHub CLI（`gh`）がログイン済み | ✅ | Issue の作成権限が必要です |
| `git`、`python3`（3.8 以上）、Node.js | ✅ | |
| パッケージマネージャー：pnpm または npm | ✅ | Yarn には未対応です（スクリプトの調整が必要） |
| Vercel CLI など、プレビューを作る手段 | 任意 | プレビューを手動で作るときに使います |
| 定期実行ができるエージェント | ✅ | Hermes Agent の cron を想定しています。ほかのエージェントでの代わりの方法は末尾に書いてあります |

---

## エージェントへの指示

ここから下は、作業するエージェントに向けた手順です。**各ステップで「ユーザーに確認」とあるところは、必ずユーザーに確認し、答えをもらってから先に進んでください。** 推測で埋めてはいけません。

### 守ること

- 作成するジョブでも、セットアップ作業中でも、**PR のマージ、承認、コメント、push、rebase、デプロイは行わない**。GitHub への書き込みは、レポート用 Issue とそのラベルの作成だけにする。
- ユーザーの作業ツリーには触らない。PR の検証は一時ディレクトリに作る `git worktree` で行い、終わったら削除する。依存パッケージのインストールが必要な場合も、ユーザーの許可を得てから行う。
- 認証情報（トークン、パスワード）を受け取らない、表示しない、ファイルに書かない。`gh` の認証が切れていたら、ユーザー自身に `gh auth login` を実行してもらう。
- Issue に載せる内容は公開リポジトリでは誰でも読めるので、ローカルの絶対パスや環境変数の値を書かない。
- **このガイドに出てくるパッケージ名（next、sharp、react-pdf など）は説明のための例にすぎない。** 判定基準は必ず Step 2 と Step 3 で、対象リポジトリから作る。

### Step 0. 事前チェック

次のコマンドを実行し、結果をユーザーに報告します。足りないものがあれば、**インストールしてよいかユーザーに確認**してから進めます。

```bash
gh auth status
git --version && python3 --version && node -v
pnpm -v || npm -v
vercel --version   # 任意（デプロイ先に合わせて読み替える）
```

### Step 1. ユーザーに確認すること

次の項目を**まとめて 1 回で**聞きます。

1. **リポジトリのローカルパス**（例：`~/repo/my-site`）
2. **実行スケジュール**：曜日、時刻、タイムゾーン。Dependabot の実行日の翌朝を推奨します。Dependabot のスケジュールは Step 2 で読み取ってから提案してもかまいません。
3. **レポートの残し方**：Issue のラベル名（初期値 `dependabot-report`）とタイトルの形式（初期値 `Dependabot 週次レビュー YYYY-MM-DD`）
4. **完了通知の送り先**：エージェントのチャット、Slack など
5. **プレビューの方針**：「レポートのみ（推奨）」か「A 判定の PR は自動でプレビューを作成」か。後者を選んだ場合は、ストレージ消費とデプロイの後片付け（削除）の方針も確認します。

パスを受け取ったら、`node_modules` があるか確認します。ない場合は、**依存をインストールしてよいか（`pnpm install` または `npm ci`）ユーザーに確認**します。インストールしないと、ネイティブパッケージの判定、`peer_checks`、`pinned_pairs` の候補検出ができません。

### Step 2. リポジトリを調べる（判定基準の材料を集める）

**2-1. 機械的な棚卸し**：付録 E の `inventory.py` を実行します。

```bash
python3 <SKILL_DIR>/scripts/inventory.py --repo-dir <リポジトリのパス> --format md   # ユーザーに見せる表
python3 <SKILL_DIR>/scripts/inventory.py --repo-dir <リポジトリのパス> > "$TMPDIR/inventory.json"  # 判定基準の下書き（draft_config）
```

このスクリプトは、直接依存しているすべてのパッケージについて次を調べ、判定区分の案とその根拠を出力します。

- ソースコードで import されているか。UI ファイル（`.tsx`、`.vue`、`.css` など）か、それ以外のコードか
- ビルド設定ファイルで参照されているか
- ビルド時に実行されるスクリプトで使われているか
- CI では実行されないビルド・テスト系の scripts に関わるか
- ネイティブバイナリを持つか
- `dependabot.yml` のどのグループに入っているか、`ignore` されているか

**2-2. 運用ルールと過去の経緯を読む**：機械的な棚卸しでは分からない情報を集めます。

| 確認するもの | 読み取ること |
|---|---|
| `AGENTS.md`、`CLAUDE.md`、`CONTRIBUTING.md`、`README.md`、`docs/` | 依存更新時のルールや、**過去の不具合の記録**（例：「デプロイ先でだけ壊れた」）。記録があれば、関係するパッケージの判定を上げる根拠になる |
| `dependabot.yml` のコメント | グループや `ignore` を設定した理由。`pinned_pairs` の根拠になる |
| `.github/workflows/*.yml` | CI が確認していること、**確認していないこと**（表示の確認、デプロイ先での動作、Storybook のビルドなど） |
| `vercel.json`、Ignored Build Step のスクリプト、`netlify.toml` など | Dependabot のプレビューをどうスキップしているか。ブランチ単位で止めている場合は空コミットでは作れないため、CLI でデプロイする手順になる |
| 直近でマージされた Dependabot PR（`gh pr list --author app/dependabot --state merged --limit 20`） | ユーザーが実際にマージした順番、手動でプレビューを作ったか（`statusCheckRollup` にデプロイのステータスがあるか） |

### Step 3. 判定基準を作り、ユーザーに確認する

#### 判定区分（固定。変えない）

| 区分 | 意味 | どのパッケージが入るか |
|---|---|---|
| **A プレビュー必須** | 本番に近い環境（プレビュー）で必ず確認してからマージする | フレームワーク本体（`build` スクリプトで実行されるもの）。デプロイ先でだけ不具合が起きた記録があるパッケージ。実行時に使うパッケージ（`dependencies`）の major 更新（※自動） |
| **B プレビュー推奨** | minor・major 更新ならプレビューで確認する。patch 更新は C 扱い | 本番の見た目や出力に影響するパッケージ。UI で import しているもの、CSS から読み込んでいるもの、ビルド設定で参照しているもの、ビルド時に生成されて本番に載るもの |
| **S ローカル確認のみ** | 本番には載らないが、CI では検証されない成果物がある。ローカルで該当の script を実行して確認する | CI で実行されないビルド・テスト系 scripts（例：Storybook、ドキュメントサイトのビルド）に関わるパッケージと、その Dependabot グループ |
| **C CI 通過でマージ可** | CI が通っていればそのままマージしてよい | GitHub Actions、型定義、lint や format のツール、CI で検証される開発ツール。`low_risk_runtime_packages` に入れたパッケージの、major 以外の更新 |
| （−）対象外 | Dependabot が更新しない | `dependabot.yml` で `ignore` しているもの。`pinned_pairs` の follower になることが多い |

※ 自動で区分を上げるルールもあります。`dependencies` の major 更新は常に A になります。また、レポートを作るときに次のどれかに当たれば、区分を一段上げます。

- リリースノートの破壊的変更が、自分のコードの使っている部分に関係する
- 本番に載るパッケージで、依存ツリーに新たな重複が生まれた
- `peer_checks` で不一致が見つかった
- 依存のインストールに失敗した

#### 判定基準の案を作る

1. `inventory.json` の `packages[].tier` と `evidence` をもとに、Step 2-2 で分かったことを反映して調整します。
   - **過去の不具合の記録がある** → A に上げる。このとき `peer_checks` の候補や、グループのまとめ方も見直す。
   - **`B?` になっているパッケージ**は、「計測・監視用など、見た目に影響しない」なら `low_risk_runtime_packages`、「出力に影響する」なら B にします。どちらとも判断できなければ、ユーザーに聞く項目として残します。
     - 例：Markdown のレンダラーは HTML を出力するので B。設定ファイル用のパーサーは low_risk の候補。
   - **`peer_checks` / `pinned_pairs` の候補**は、ドキュメントや CI に根拠があるか確認し、根拠の有無を明記します。
2. マージ順（`merge_order`）を決めます。基本は次の順です。
   > GitHub Actions(0) → A を含むグループ(1) → UI の基盤（例：react）(2) → B を含むグループ(3) → その他の実行時パッケージ(4〜5) → 型定義・lint(6) → S のグループ・開発ツール(7)

   Step 2-2 で調べた「ユーザーが実際にマージした順番」と大きく違う場合は、その差を示してユーザーに聞きます。

#### ユーザーに確認する（必須）

次の内容を**1 つのメッセージにまとめて**見せ、確認をもらいます。

1. **区分ごとの表**：パッケージ、Dependabot グループ、判定案、根拠。根拠にはファイル名や、ドキュメントの該当箇所も書く。
2. **判断を保留している項目**：`B?` のパッケージ（B にするか low_risk にするか）、根拠の弱い `peer_checks` / `pinned_pairs`、S のローカル確認で実行する script（実行時間の目安も添える）
3. **マージ順の案**と、過去にマージされた順番との違い

ユーザーが修正したら、表を直して再度見せます。**ユーザーの OK をもらうまで Step 4 には進みません。** 確定した内容は `review-config.json` に書き出します（形式は付録 B。`inventory.json` の `draft_config` が下書きになります）。

### Step 4. スキル（またはそれに相当するファイル）を作る

次の構成でファイルを置きます。Hermes Agent の場合はスキルとして作成します。

```
<SKILL_DIR>/                         # 例: ~/.hermes/skills/software-development/dependabot-weekly-review/
├── SKILL.md                         # 付録 C のテンプレートを埋めたもの。Tier rules には Step 3 で確定した表を載せる
└── scripts/
    ├── collect.py                   # 付録 A をそのまま保存
    ├── inventory.py                 # 付録 E をそのまま保存（依存が増えたときに再実行する）
    └── review-config.json           # Step 3 でユーザーが確認した設定
```

`chmod +x scripts/*.py` を実行しておきます。

※ Step 2 で `inventory.py` を実行するには、先にファイルを保存しておく必要があります。`scripts/inventory.py` だけは Step 2 の前に保存してかまいません。

### Step 5. 試しに実行し、レポートを確認してもらう

直近でマージされた Dependabot PR（5〜10 件）を対象に実行します。

```bash
python3 <SKILL_DIR>/scripts/collect.py --config <SKILL_DIR>/scripts/review-config.json \
  --prs <番号をカンマ区切り> --local-check > "$TMPDIR/depbot.json"
```

- 付録 D の形式で試しのレポートを作り、**Issue にはせずチャットに貼ります**。
- ユーザーが実際にマージした順番と推奨順を比べた結果も添えます。
- 判定に違和感がないかユーザーに確認し、必要なら `review-config.json` や SKILL.md を直して、もう一度実行します。
- 実行時間の目安は、1 PR あたり数十秒から数分です。依存のインストールが主で、ローカル確認（`local_check_script`）があるとさらに延びます。

### Step 6. 定期ジョブを登録する

ユーザーの OK をもらってから登録します。Hermes Agent の場合は次の設定です。

- `schedule`：Step 1 で確認した値（例：`0 9 * * 2`）。`timezone` も指定する。
- `skills`：作成したスキル（加えて `github` スキルがあれば）
- `workdir`：リポジトリのローカルパス（`AGENTS.md` などが自動で読み込まれる）
- `prompt`：次の文面（`<...>` を埋める）

~~~text
<owner/repo>（ローカル: <リポジトリのパス>）の open な Dependabot PR を、スキル <スキル名> の手順どおりにレビューしてください。

- collect.py を --config <設定ファイルのパス> --state open --local-check で実行し、判定（A プレビュー必須 / B プレビュー推奨 / S ローカル確認のみ / C CI 通過でマージ可）と推奨マージ順を決める。A/B の PR と minor・major 更新の PR はリリースノートを読み、ソースコードでの利用箇所も確認して判定理由を書く。
- review-config.json に登録されていない新しい依存が PR に含まれていたら、レポートに「判定基準に未登録」と書き、inventory.py を再実行して基準を見直すよう提案する（基準は勝手に変えない）。
- レポートは日本語で、スキルのテンプレートに沿って GitHub issue（ラベル <ラベル名>、タイトル「<タイトル形式>」）として作成する。同じタイトルの issue が既にあれば作らない。
- 対象 PR が 0 件なら issue は作らず、その旨だけ返す。
- 禁止: PR のマージ・承認・コメント、push、rebase、デプロイ、review-config.json の変更。書き込みは issue（とラベル）の作成のみ。
- 最終回答: issue の URL と、PR ごとの判定・マージ順を 1 行ずつ。
~~~

登録後に、ジョブ ID と次回の実行日時をユーザーに伝えます。

### 判定基準の見直し

依存パッケージを追加・削除したときや、グループ構成を変えたときは、`inventory.py` を再実行します。今の `review-config.json` との違いを表にしてユーザーに見せ、確認をもらってから更新します（Step 3 と同じ流れ）。

### Hermes Agent 以外で使う場合

- **Claude Code など**：Step 0〜5 はそのまま実施できます。定期実行は、OS の cron や launchd、または GitHub Actions の `schedule` からエージェントの CLI を呼び出す形にします。Actions で動かす場合はローカルの作業ツリーがないので、`actions/checkout` と `GH_TOKEN`（`issues: write` の権限）が必要です。
- **AI を使わず動かす場合**：`collect.py` の JSON 出力は機械判定までなので、リリースノートの読み込みとレポートの作成は別に用意する必要があります。

---

## 付録 A：`collect.py`

PR ごとの事実を集めて JSON で出力するスクリプトです。GitHub への書き込みは一切しません。

~~~~python
#!/usr/bin/env python3
"""Collect facts about Dependabot PRs for a weekly review report.

Usage:
  collect.py --config review-config.json [--prs 12,13] [--state open|merged]
             [--local-check] [--keep-worktrees]

Prints one JSON document to stdout (progress goes to stderr).
Read-only towards GitHub: never comments, merges, deploys or pushes.
Package managers: pnpm and npm (lockfile analysis + install). Yarn: not supported.
"""
import argparse, json, os, re, subprocess, sys, tempfile, shutil

DEFAULT_ORDER = {"github-actions": 0, "preview-required": 1, "visual": 3,
                 "runtime-other": 5, "dev-other": 7, "local-only": 7}


def sh(cmd, cwd=None, check=True, timeout=900):
    r = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, timeout=timeout)
    if check and r.returncode != 0:
        raise RuntimeError(f"cmd failed ({r.returncode}): {cmd}\n{r.stderr[-2000:]}")
    return r


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def rx(patterns):
    return re.compile("^(" + "|".join(patterns) + ")$") if patterns else re.compile("(?!)")


def semver_tuple(v):
    m = re.match(r"v?(\d+)(?:\.(\d+))?(?:\.(\d+))?", v or "")
    return tuple(int(x or 0) for x in m.groups()) if m else None


def bump_kind(a, b):
    ta, tb = semver_tuple(a), semver_tuple(b)
    if not ta or not tb:
        return "unknown"
    if ta[0] != tb[0]:
        return "major"
    if ta[1] != tb[1]:
        return "major(0.x)" if ta[0] == 0 else "minor"  # 0.x minor = breaking
    return "patch" if ta[2] != tb[2] else "none"


def parse_updates(title, body):
    ups = [m.groups() for m in re.finditer(
        r"Updates `([^`]+)` from ([\w.\-+]+) to ([\w.\-+]+)", body or "")]
    if not ups:
        m = re.search(r"Bump (\S+) from ([\w.\-+]+) to ([\w.\-+]+)", title)
        if m:
            ups = [m.groups()]
    seen, out = set(), []
    for u in ups:
        if u[0] not in seen:
            seen.add(u[0]); out.append(u)
    return out


# ------------------------------------------------------------ lockfiles
def lock_packages(text, pm):
    """Return set of 'name@version' resolved in the lockfile."""
    out = set()
    if pm == "npm":
        for path, info in (json.loads(text).get("packages") or {}).items():
            if path and info.get("version"):
                out.add(path.split("node_modules/")[-1] + "@" + info["version"])
        return out
    in_pk = False  # pnpm-lock.yaml v9: top-level `packages:` section
    for line in text.splitlines():
        if re.match(r"^\S", line):
            in_pk = line.startswith("packages:")
            continue
        if in_pk:
            m = re.match(r"^  '?([^'\s][^:']*?)'?:\s*$", line)
            if m:
                out.add(m.group(1))
    return out


def split_key(k):
    i = k.rfind("@")
    return (k[:i], k[i + 1:]) if i > 0 else (k, "")


def multi(keys):
    d = {}
    for k in keys:
        n, v = split_key(k); d.setdefault(n, set()).add(v)
    return {k: sorted(v) for k, v in d.items() if len(v) > 1}


def walk_versions(tree, name, acc):
    if isinstance(tree, list):
        for t in tree:
            walk_versions(t, name, acc)
        return
    if not isinstance(tree, dict):
        return
    for sect in ("dependencies", "devDependencies", "optionalDependencies"):
        for n, info in (tree.get(sect) or {}).items():
            if n == name and isinstance(info, dict) and info.get("version"):
                acc.add(info["version"])
            walk_versions(info, name, acc)


def read_json(path):
    with open(path) as f:
        return json.load(f)


# ------------------------------------------------------------ main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--prs", default="")
    ap.add_argument("--state", default="open")
    ap.add_argument("--local-check", action="store_true",
                    help="run config.local_check_script for local-only tier PRs")
    ap.add_argument("--keep-worktrees", action="store_true")
    a = ap.parse_args()

    cfg = read_json(os.path.expanduser(a.config))
    repo = os.path.expanduser(cfg["repo_dir"])
    base_branch = cfg.get("base_branch", "main")
    pm = cfg.get("package_manager", "pnpm")
    lockfile = {"pnpm": "pnpm-lock.yaml", "npm": "package-lock.json"}[pm]
    install = {"pnpm": ["pnpm", "install", "--frozen-lockfile", "--ignore-scripts",
                        "--reporter=silent"],
               "npm": ["npm", "ci", "--ignore-scripts", "--no-audit", "--no-fund"]}[pm]
    preview_groups = set(cfg.get("preview_required_groups", []))
    preview_pkgs = rx(cfg.get("preview_required_packages", []))
    visual = rx(cfg.get("visual_packages", []))
    low_risk = rx(cfg.get("low_risk_runtime_packages", []))
    local_only = rx(cfg.get("local_only_packages", []))
    order = {**DEFAULT_ORDER, **cfg.get("merge_order", {})}
    os.environ.setdefault("CI", "1")

    fields = ("number,title,body,headRefName,headRefOid,createdAt,mergedAt,state,"
              "mergeable,mergeStateStatus,statusCheckRollup,url,commits")
    if a.prs:
        numbers = a.prs.split(",")
    else:  # numbers only: heavy fields in `gh pr list` exceed GraphQL node limits
        numbers = [str(p["number"]) for p in json.loads(sh(
            ["gh", "pr", "list", "--author", "app/dependabot", "--state", a.state,
             "--limit", "50", "--json", "number"], cwd=repo).stdout)]
    prs = [json.loads(sh(["gh", "pr", "view", n, "--json", fields], cwd=repo).stdout)
           for n in numbers]

    sh(["git", "fetch", "-q", "origin", base_branch], cwd=repo)
    main_pkg = json.loads(sh(["git", "show", f"origin/{base_branch}:package.json"],
                             cwd=repo).stdout)
    deps, devdeps = set(main_pkg.get("dependencies", {})), set(main_pkg.get("devDependencies", {}))

    wt_root = tempfile.mkdtemp(prefix="depbot-wt-", dir=os.environ.get("TMPDIR"))
    results = []
    for pr in sorted(prs, key=lambda p: p["number"]):
        n = pr["number"]
        log(f"== PR #{n} {pr['title']}")
        sh(["git", "fetch", "-q", "origin", f"+pull/{n}/head:refs/remotes/depbot/pr-{n}"], cwd=repo)
        head = pr["headRefOid"]
        if pr.get("mergedAt"):  # merged: compare with the commit before the PR's commits
            base = sh(["git", "rev-parse", f"{head}~{len(pr.get('commits') or []) or 1}"],
                      cwd=repo).stdout.strip()
        else:
            base = sh(["git", "merge-base", f"origin/{base_branch}", head], cwd=repo).stdout.strip()
        files = sh(["git", "diff", "--name-only", base, head], cwd=repo).stdout.split()
        is_actions = pr["headRefName"].startswith("dependabot/github_actions")
        m = re.search(r"the (\S+) group", pr["title"])
        grp = m.group(1) if m else ("github-actions" if is_actions else None)

        ups = []
        for name, frm, to in parse_updates(pr["title"], pr.get("body")):
            ups.append({"name": name, "from": frm, "to": to, "bump": bump_kind(frm, to),
                        "dep_type": "github-actions" if is_actions else
                        "dependencies" if name in deps else
                        "devDependencies" if name in devdeps else "transitive/other"})
        body = pr.get("body") or ""
        notes = {"breaking_mentions": len(re.findall(r"(?i)breaking", body)),
                 "security_advisories": sorted(set(re.findall(r"GHSA-[\w-]+", body))),
                 "deprecation_mentions": len(re.findall(r"(?i)deprecat", body))}
        checks = [{"name": c.get("name") or c.get("context"),
                   "status": c.get("status") or c.get("state"),
                   "conclusion": c.get("conclusion")} for c in pr.get("statusCheckRollup") or []]
        authors = sorted({((c.get("authors") or [{}])[0]).get("login", "?")
                          for c in pr.get("commits") or []})

        lock = {}
        if lockfile in files:
            lb = lock_packages(sh(["git", "show", f"{base}:{lockfile}"], cwd=repo).stdout, pm)
            lh = lock_packages(sh(["git", "show", f"{head}:{lockfile}"], cwd=repo).stdout, pm)
            names = {u["name"] for u in ups}
            mb, mh = multi(lb), multi(lh)
            lock = {
                "added_count": len(lh - lb), "removed_count": len(lb - lh),
                "added_other": sorted(k for k in lh - lb if split_key(k)[0] not in names),
                "removed_other": sorted(k for k in lb - lh if split_key(k)[0] not in names),
                "newly_duplicated": {k: v for k, v in mh.items() if k not in mb},
                "duplicate_set_changed": {k: {"before": mb[k], "after": v} for k, v in mh.items()
                                          if k in mb and set(v) != set(mb[k])},
                "duplicate_resolved": sorted(k for k in mb if k not in mh),
            }

        names = [u["name"] for u in ups]
        resolved, extra, install_ok, install_err = {}, {}, None, None
        if not is_actions:
            wt = os.path.join(wt_root, f"pr-{n}")
            sh(["git", "worktree", "add", "-q", "--detach", wt, head], cwd=repo)
            r = sh(install, cwd=wt, check=False)
            install_ok = r.returncode == 0
            if not install_ok:
                install_err = (r.stderr or r.stdout)[-1500:]
            else:
                for nm in names:
                    cmd = ([pm, "list", nm, "--depth", "Infinity", "--json"] if pm == "pnpm"
                           else ["npm", "ls", nm, "--all", "--json"])
                    vs = set()
                    try:
                        walk_versions(json.loads(sh(cmd, cwd=wt, check=False).stdout), nm, vs)
                    except Exception:
                        pass
                    resolved[nm] = sorted(vs)
                pkgj = read_json(os.path.join(wt, "package.json"))
                alldeps = {**pkgj.get("devDependencies", {}), **pkgj.get("dependencies", {})}
                # peer_checks: a package whose own (optional)dependency must match our direct one
                for pc in cfg.get("peer_checks", []):
                    if pc["package"] not in names:
                        continue
                    try:
                        own = read_json(os.path.join(wt, "node_modules", pc["package"], "package.json"))
                        want = (own.get(pc.get("field", "dependencies")) or {}).get(pc["peer"])
                        have = read_json(os.path.join(wt, "node_modules", pc["peer"], "package.json"))["version"]
                        extra[f"peer:{pc['package']}->{pc['peer']}"] = {
                            "requires": want, "installed_direct": have,
                            "package_json": alldeps.get(pc["peer"])}
                    except Exception as e:
                        extra[f"peer:{pc['package']}->{pc['peer']}"] = {"error": str(e)}
                # pinned_pairs: follower is ignored by Dependabot and must equal leader's pin
                for pp in cfg.get("pinned_pairs", []):
                    if pp["leader"] not in names:
                        continue
                    to = next(u["to"] for u in ups if u["name"] == pp["leader"])
                    req = sh(["npm", "view", f"{pp['leader']}@{to}", f"dependencies.{pp['follower']}"],
                             cwd=wt, check=False).stdout.strip()
                    have = alldeps.get(pp["follower"])
                    extra[f"pinned:{pp['leader']}->{pp['follower']}"] = {
                        "leader_requires": req, "package_json": have,
                        "match": None if have is None else req == have}
                if a.local_check and cfg.get("local_check_script") and names and \
                        all(local_only.match(x) for x in names):
                    log("   local check...")
                    r = sh([pm, "run", cfg["local_check_script"]], cwd=wt, check=False, timeout=1200)
                    extra["local_check"] = {"script": cfg["local_check_script"],
                                            "ok": r.returncode == 0,
                                            "tail": (r.stderr or r.stdout)[-800:]}
            if not a.keep_worktrees:
                sh(["git", "worktree", "remove", "--force", wt], cwd=repo, check=False)

        # ---------------------------------------------------- tier / order
        kinds = [u["bump"] for u in ups]
        bigger = any(k.startswith(("major", "minor")) for k in kinds)
        major = any(k.startswith("major") for k in kinds)
        runtime = any(u["dep_type"] == "dependencies" for u in ups)
        if is_actions:
            tier, bucket = "C", "github-actions"
        elif grp in preview_groups or any(preview_pkgs.match(x) for x in names):
            tier, bucket = "A", grp if grp in order else "preview-required"
        elif names and all(local_only.match(x) for x in names):
            tier, bucket = "S", grp if grp in order else "local-only"
        elif any(visual.match(x) for x in names):
            tier, bucket = ("B" if bigger else "C"), grp if grp in order else "visual"
        elif runtime and all(low_risk.match(x) for x in names if x in deps):
            tier, bucket = ("B" if major else "C"), grp if grp in order else "runtime-other"
        elif runtime:
            tier, bucket = ("B" if bigger else "C"), grp if grp in order else "runtime-other"
        else:
            tier, bucket = "C", grp if grp in order else "dev-other"
        if major and runtime and tier in ("B", "C"):
            tier = "A"

        results.append({
            "number": n, "title": pr["title"], "url": pr["url"], "branch": pr["headRefName"],
            "state": pr["state"], "merged_at": pr.get("mergedAt"), "created_at": pr["createdAt"],
            "mergeable": pr.get("mergeable"), "merge_state": pr.get("mergeStateStatus"),
            "group": grp, "updates": ups, "files": files, "checks": checks,
            "commit_authors": authors, "release_notes": notes, "lockfile": lock,
            "install_ok": install_ok, "install_error": install_err,
            "resolved_versions": resolved, "extra": extra,
            "suggested_tier": tier, "order_bucket": bucket, "order_rank": order.get(bucket, 5),
        })

    if not a.keep_worktrees:
        shutil.rmtree(wt_root, ignore_errors=True)
        sh(["git", "worktree", "prune"], cwd=repo, check=False)
    print(json.dumps({"repo_dir": repo, "count": len(results), "prs": results},
                     ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
~~~~

**出力のおもな項目**

| キー | 意味 |
|---|---|
| `updates[]` | 更新されるパッケージ、更新前後のバージョン、semver の種別（major / minor / patch。0.x の minor は major として扱う）、依存の種類 |
| `checks[]` | CI とデプロイのステータス。プレビュー用のチェックがあれば、プレビューは作成済み |
| `release_notes` | PR 本文に出てくる "breaking" や "deprecat" の数と、GHSA（セキュリティ勧告）の ID |
| `lockfile.newly_duplicated` | この PR で**新たに** 2 つ以上のバージョンが共存するようになったパッケージ。最も重要な確認項目 |
| `lockfile.duplicate_set_changed` / `duplicate_resolved` | 以前からあった重複のバージョンが変わったもの、解消されたもの。たいていは問題なし |
| `lockfile.added_other` / `removed_other` | 更新対象以外で lockfile に追加・削除されたパッケージ |
| `extra["peer:A->B"]` | A が要求する B のバージョン、実際に入った B のバージョン、package.json の指定 |
| `extra["pinned:A->B"]` | A の新しいバージョンが固定で要求する B のバージョンと、package.json の指定。`match: false` なら、手動でバージョンを揃えるコミットが必要 |
| `extra.local_check` | `local_check_script` の実行結果（成功したか、出力の末尾） |
| `suggested_tier` / `order_rank` | 設定に基づいて機械的に出した判定とマージ順。最終的な判定は、エージェントがリリースノートを読んで調整する |

**ハマりどころ**

- `gh pr list --json body,commits,statusCheckRollup ...` は GitHub API の上限（GraphQL のノード数）を超えます。そのためスクリプトは、PR 番号だけを一覧で取ってから `gh pr view` で 1 件ずつ取得しています。
- 依存のインストールは `--ignore-scripts` で行います。インストール時のスクリプトを実行しないので、安全で速いですが、ネイティブバイナリのビルドが要るテストはできません。

## 付録 B：`review-config.json` の形式

値は Step 3 でユーザーが確認したものだけを入れます。`inventory.py` の出力にある `draft_config` が下書きになります。パッケージ名は**正規表現（全体一致）**で書きます。

| キー | 型 | 内容 |
|---|---|---|
| `repo_dir` | string | ローカルクローンのパス |
| `base_branch` | string | PR のマージ先ブランチ |
| `package_manager` | `"pnpm"` / `"npm"` | |
| `preview_required_groups` | string[] | A にする Dependabot グループ名 |
| `preview_required_packages` | regex[] | A にするパッケージ |
| `visual_packages` | regex[] | B にするパッケージ（minor・major なら B、patch なら C） |
| `low_risk_runtime_packages` | regex[] | `dependencies` だが見た目に影響しないもの（major 以外は C） |
| `local_only_packages` | regex[] | S にするパッケージ。PR の更新対象が**すべて**これに当たるときだけ S |
| `local_check_script` | string / null | `--local-check` を付けたとき、S の PR で `<pm> run <script>` を実行する |
| `merge_order` | {キー: 数値} | 小さいほど先にマージ。キーは Dependabot グループ名、または組み込みのバケット（`github-actions` / `preview-required` / `visual` / `runtime-other` / `dev-other` / `local-only`） |
| `peer_checks` | [{package, peer, field}] | `package` の `field`（`dependencies` か `optionalDependencies`）が要求する `peer` のバージョンと、自分で直接入れている `peer` のバージョンを照合する |
| `pinned_pairs` | [{leader, follower}] | `follower` は Dependabot で ignore し、`leader` が固定で要求するバージョンに手動で揃える |

形だけの雛形です。値は必ず対象リポジトリから作ってください。

```json
{
  "repo_dir": "<path>",
  "base_branch": "<branch>",
  "package_manager": "<pnpm|npm>",
  "preview_required_groups": [],
  "preview_required_packages": [],
  "visual_packages": [],
  "low_risk_runtime_packages": [],
  "local_only_packages": [],
  "local_check_script": null,
  "merge_order": { "github-actions": 0, "preview-required": 1, "visual": 3, "runtime-other": 5, "dev-other": 7, "local-only": 7 },
  "peer_checks": [],
  "pinned_pairs": []
}
```

## 付録 C：SKILL.md テンプレート

`<...>` の部分を埋めて使います。

~~~~markdown
---
name: dependabot-weekly-review
description: "Use when triaging Dependabot PRs weekly. File report issue."
version: 1.0.0
---

# Dependabot weekly review (<owner/repo>)

Repo: `<repo path>`（<フレームワーク> + <パッケージマネージャー> + <デプロイ先・プラン>）。
Dependabot は <曜日 時刻> に実行し、このレビューは <曜日 時刻> に実行して GitHub issue を作成する。
リポジトリ内の依存更新ルール（<AGENTS.md など>）が最優先。以下はそれを運用に落としたもの。

## Hard limits (report-only)
- PR のマージ・承認・コメント、push、rebase、デプロイは禁止。書き込みは issue とラベルの作成のみ。
- ユーザーの作業ツリーには触れない（collect.py は git worktree を使う）。
- review-config.json は定期実行の中で変更しない。見直しはユーザーの確認を経て行う。

## Procedure
1. `python3 <SKILL_DIR>/scripts/collect.py --config <SKILL_DIR>/scripts/review-config.json --state open --local-check > "$TMPDIR/depbot.json"`
2. `count` が 0 なら issue は作らず「今週の Dependabot PR はありません」と返す。
3. A/B の PR と minor・major 更新の PR は `gh pr view N --json body` でリリースノートを読み、破壊的変更や非推奨になった API をソースで grep する。判定を変えた場合は理由を書く。
4. review-config.json のどこにも出てこない新しい依存が PR に含まれていたら、「判定基準に未登録」とレポートに書き、`inventory.py` の再実行を提案する。
5. 付録 D のテンプレートで `$TMPDIR/depbot-report.md` を作る。
6. 同じタイトルの issue がないか確認してから作成する:
   gh label create <label> --color 0366d6 2>/dev/null || true
   gh issue list --label <label> --state all --search "<title> in:title" --json number -q length
   gh issue create --title "<title>" --label <label> --body-file "$TMPDIR/depbot-report.md"
7. 最終回答: issue の URL と、PR ごとの判定・マージ順を 1 行ずつ。

## Tier rules（<確定日> にユーザー確認済み）
<Step 3 で確定した区分ごとの表（パッケージ / グループ / 区分 / 根拠）>

判定を一段上げる条件: リリースノートの破壊的変更が自分のコードに関係する / `lockfile.newly_duplicated` に本番バンドルに入るパッケージがある / `peer:*` が不一致 / `install_ok` が false。
dependencies の major 更新は常に A。セキュリティ勧告（GHSA）は判定ではなく優先度を上げる。

## Interpreting output
- `pinned:*` の `match == false`: その PR に、follower のバージョンを合わせるコミットが必要。
- `checks` にプレビュー用のステータスがあれば、プレビューは作成済み。
- `mergeable == CONFLICTING`: 「`@dependabot rebase` が必要」と書く。
- 判明した「問題のない重複」はここに追記していく。

## Merge order
order_rank の昇順。同じ順位の中では、セキュリティ修正 → 更新幅が小さいもの。
1 件マージするたびに Dependabot が残りの PR を rebase し CI が再実行されるので、次の PR は CI が再び通ったのを確認してからマージする。

## Pitfalls
- <プレビューのスキップ方法と、手動で立てる手順（例: ブランチ単位で止めているなら空コミットでは作られないので CLI でデプロイする）>
~~~~

## 付録 D：レポート（Issue 本文）テンプレート

~~~~markdown
## サマリー
- 対象: N 件（A: x / B: x / S: x / C: x）
- 優先: <セキュリティ修正を含む PR など>
- 判定基準に未登録の依存: <あれば>

## 推奨マージ順
| 順 | PR | 内容 | 種別 | 判定 | CI | 備考 |
|---|---|---|---|---|---|---|

## PR 別の詳細
### #N タイトル — 判定
- 更新: pkg a → b（patch, dependencies）
- リリースノートの要点 / 影響する箇所
- 依存ツリー: 重複・lockfile の想定外の変化
- 確認手順（A/B のみ）

## プレビュー確認手順（A/B 用）
<デプロイ先に合わせたコマンド。例: gh pr checkout <N> && vercel deploy → 確認後 vercel remove <url> --yes>

## マージ後の確認
- [ ] 依存ツリーに重複がない（`pnpm why <pkg>` / `npm ls <pkg>`）
- [ ] lockfile に想定外の追加がない
~~~~

## 付録 E：`inventory.py`

リポジトリを読むだけのスクリプトです。判定区分の案と根拠、`review-config.json` の下書き（`draft_config`）を出力します。`--format md` を付けると、ユーザーに見せる表形式で出力します。

~~~~python
#!/usr/bin/env python3
"""Inventory a JS/TS repo and draft Dependabot review rules (tiers A/B/S/C).

Usage:
  inventory.py --repo-dir <path> [--format json|md]

Read-only. Needs node_modules installed for native/peer/pinned detection
(otherwise those columns are reported as unknown). Output is a DRAFT: every
proposal carries its evidence and must be confirmed by the user.
"""
import argparse, fnmatch, glob, json, os, re, subprocess, sys

SRC_DIRS = ["src", "app", "pages", "components", "lib", "layouts", "styles", "content"]
BUILD_SCRIPT_DIRS = ["scripts"]  # prebuild / codegen helpers run during the build
LOW_RISK_HINT = re.compile(r"(analytics|insights|sentry|monitor|telemetry|gtag|datadog|posthog|segment|newrelic)", re.I)
UI_EXT = {".tsx", ".jsx", ".vue", ".svelte", ".astro", ".css", ".scss", ".sass", ".mdx"}
CODE_EXT = UI_EXT | {".ts", ".js", ".mjs", ".cjs", ".mts", ".cts"}
CONFIG_GLOBS = ["next.config.*", "nuxt.config.*", "astro.config.*", "vite.config.*",
                "svelte.config.*", "remix.config.*", "gatsby-config.*", "postcss.config.*",
                "tailwind.config.*", "babel.config.*", ".babelrc*", "webpack.config.*"]
DEV_TOOL_CONFIG_GLOBS = [".storybook/*", "eslint.config.*", ".eslintrc*", "prettier.config.*",
                         ".prettierrc*", "playwright.config.*", "vitest.config.*",
                         "jest.config.*", ".husky/*", "lint-staged.config.*"]
NON_CI_EXCLUDE = re.compile(r"(--ui|--watch|\bdev\b|\bserve\b|\bstart\b|--open)")
PM_RUN = re.compile(r"\b(?:pnpm|npm|yarn|bun)\s+(?:run\s+)?([\w:.\-]+)")


def sh(cmd, cwd):
    return subprocess.run(cmd, cwd=cwd, text=True, capture_output=True)


def read_json(p):
    try:
        with open(p) as f:
            return json.load(f)
    except Exception:
        return None


# ------------------------------------------------------------ dependabot.yml
def parse_dependabot(path):
    """Return (groups{name:[patterns]}, ignores[{name,versions}], schedule str)."""
    if not os.path.exists(path):
        return {}, [], None
    text = open(path).read()
    try:
        import yaml  # optional
        d = yaml.safe_load(text) or {}
        groups, ignores, sched = {}, [], None
        for u in d.get("updates", []):
            if u.get("package-ecosystem") not in ("npm", "npm_and_yarn"):
                continue
            sched = u.get("schedule")
            for g, spec in (u.get("groups") or {}).items():
                groups[g] = list(spec.get("patterns") or [])
            for ig in u.get("ignore") or []:
                ignores.append({"name": ig.get("dependency-name"),
                                "versions": ig.get("versions"),
                                "update_types": ig.get("update-types")})
        return groups, ignores, json.dumps(sched, ensure_ascii=False) if sched else None
    except ImportError:
        pass
    # minimal fallback parser (handles the common dependabot.yml layout)
    groups, ignores, sched = {}, [], None
    eco, section, cur_group, sect_indent = None, None, None, 0
    for raw in text.splitlines():
        line = raw.split(" #")[0].rstrip() if not raw.lstrip().startswith("#") else ""
        if not line.strip():
            continue
        ind = len(line) - len(line.lstrip())
        s = line.strip()
        m = re.match(r"-?\s*package-ecosystem:\s*['\"]?([\w-]+)", s)
        if m:
            eco, section = m.group(1), None
            continue
        if eco != "npm":
            continue
        if re.match(r"(groups|ignore|schedule):\s*$", s):
            section, sect_indent, cur_group = s[:-1], ind, None
            continue
        if section and ind <= sect_indent:
            section = None
        if section == "groups":
            m = re.match(r"([\w.\-]+):\s*$", s)
            if m and ind == sect_indent + 2:
                cur_group = m.group(1); groups[cur_group] = []
            m = re.match(r"-\s*['\"]?([^'\"]+)['\"]?\s*$", s)
            if m and cur_group and not s.startswith("- dependency"):
                groups[cur_group].append(m.group(1))
        elif section == "ignore":
            m = re.match(r"-\s*dependency-name:\s*['\"]?([^'\"]+)['\"]?", s)
            if m:
                ignores.append({"name": m.group(1), "versions": None, "update_types": None})
            m = re.match(r"versions:\s*\[(.*)\]", s)
            if m and ignores:
                ignores[-1]["versions"] = [v.strip(" '\"") for v in m.group(1).split(",")]
        elif section == "schedule":
            sched = (sched or "") + s + " "
    return groups, ignores, sched.strip() if sched else None


def group_of(name, groups):
    for g, pats in groups.items():  # dependabot: first matching group wins
        if any(fnmatch.fnmatch(name, p) for p in pats):
            return g
    return None


# ------------------------------------------------------------ CI coverage
def ci_scripts(repo, scripts):
    """package.json scripts invoked (directly or via pre/post) by GitHub workflows."""
    ran = set()
    for wf in glob.glob(os.path.join(repo, ".github/workflows/*.y*ml")):
        for m in PM_RUN.finditer(open(wf).read()):
            if m.group(1) in scripts:
                ran.add(m.group(1))
            elif m.group(1) == "test" and "test" in scripts:
                ran.add("test")
    for s in list(ran):
        for p in ("pre" + s, "post" + s):
            if p in scripts:
                ran.add(p)
    return ran


# ------------------------------------------------------------ source usage
def source_files(repo, dirs=SRC_DIRS):
    out = []
    for d in dirs:
        for root, dirs, files in os.walk(os.path.join(repo, d)):
            dirs[:] = [x for x in dirs if x not in ("node_modules", ".next", "dist", "build")]
            out += [os.path.join(root, f) for f in files if os.path.splitext(f)[1] in CODE_EXT]
    return out


def usage(name, files, repo):
    pat = re.compile(r"""(?:from\s+|import\s*\(?\s*|require\(\s*|@import\s+(?:url\()?)['"]"""
                     + re.escape(name) + r"""(?:/[^'"]*)?['"]""")
    hits = []
    for f in files:
        try:
            if pat.search(open(f, errors="ignore").read()):
                hits.append(os.path.relpath(f, repo))
        except Exception:
            pass
    return hits


def config_refs(name, repo, globs_):
    hits = []
    for g in globs_:
        for f in glob.glob(os.path.join(repo, g)):
            if os.path.isfile(f) and re.search(r"""['"]""" + re.escape(name) + r"""(?:/[^'"]*)?['"]""",
                                               open(f, errors="ignore").read()):
                hits.append(os.path.relpath(f, repo))
    return hits


# ------------------------------------------------------------ node_modules facts
def pkg_meta(repo, name):
    return read_json(os.path.join(repo, "node_modules", name, "package.json"))


PLATFORM = re.compile(r"(darwin|linux|win32|freebsd|android)-(x64|arm64|arm|ia32)")


def is_native(meta):
    if not meta:
        return None
    if meta.get("gypfile") or meta.get("binary") or meta.get("napi"):
        return True
    opt = meta.get("optionalDependencies") or {}
    return any(PLATFORM.search(k) for k in opt)


def bin_owner(repo, direct):
    owners = {}
    for n in direct:
        meta = pkg_meta(repo, n) or {}
        b = meta.get("bin")
        if isinstance(b, str):
            owners[n.split("/")[-1]] = n
        elif isinstance(b, dict):
            for k in b:
                owners[k] = n
    return owners


# ------------------------------------------------------------ main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo-dir", required=True)
    ap.add_argument("--format", default="json", choices=["json", "md"])
    a = ap.parse_args()
    repo = os.path.expanduser(a.repo_dir)

    pkg = read_json(os.path.join(repo, "package.json")) or {}
    deps, devdeps = pkg.get("dependencies", {}), pkg.get("devDependencies", {})
    scripts = pkg.get("scripts", {})
    direct = list(deps) + list(devdeps)
    pm = ("pnpm" if os.path.exists(os.path.join(repo, "pnpm-lock.yaml")) else
          "npm" if os.path.exists(os.path.join(repo, "package-lock.json")) else
          "yarn" if os.path.exists(os.path.join(repo, "yarn.lock")) else "unknown")
    base = sh(["git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD"], repo).stdout.strip()
    base = base.split("/", 1)[1] if "/" in base else (base or "main")
    nm_ok = os.path.isdir(os.path.join(repo, "node_modules"))

    groups, ignores, sched = parse_dependabot(os.path.join(repo, ".github/dependabot.yml"))
    ignored_full = {i["name"] for i in ignores if not i.get("versions") and not i.get("update_types")}
    ran_in_ci = ci_scripts(repo, scripts)
    not_in_ci = {s: c for s, c in scripts.items() if s not in ran_in_ci}
    local_check_candidates = {s: c for s, c in not_in_ci.items()
                              if re.search(r"\b(build|test|check|typecheck)\b", c + " " + s)
                              and not NON_CI_EXCLUDE.search(c) and not s.startswith(("pre", "post"))}
    owners = bin_owner(repo, direct) if nm_ok else {}

    def script_pkgs(cmd):
        out = set()
        for tok in re.findall(r"[\w@/.\-]+", cmd):
            if tok in owners:
                out.add(owners[tok])
            elif tok in direct:
                out.add(tok)
        return out

    build_cmd = scripts.get("build", "")
    framework = script_pkgs(build_cmd)
    local_pkgs = {}
    for s, c in local_check_candidates.items():
        for p in script_pkgs(c):
            local_pkgs.setdefault(p, s)

    files = source_files(repo)
    bfiles = source_files(repo, BUILD_SCRIPT_DIRS)
    rx_name = lambda n: n.replace(".", r"\.")
    rows = []
    for name in direct:
        runtime = name in deps
        grp = group_of(name, groups)
        used = usage(name, files, repo)
        build_used = usage(name, bfiles, repo)
        ui_used = [f for f in used if os.path.splitext(f)[1] in UI_EXT]
        build_cfg = config_refs(name, repo, CONFIG_GLOBS)
        dev_cfg = config_refs(name, repo, DEV_TOOL_CONFIG_GLOBS)
        meta = pkg_meta(repo, name) if nm_ok else None
        native = is_native(meta) if nm_ok else None
        ev, tier = [], None
        if name in ignored_full:
            tier = "-"; ev.append("dependabot.yml で ignore（Dependabot は更新しない）")
        elif name in framework:
            tier = "A"; ev.append(f"build スクリプト `{build_cmd}` の本体")
        elif runtime and LOW_RISK_HINT.search(name):
            tier = "B?"; ev.append("計測/監視系の名前 → 見た目に影響しなければ low_risk 候補" + (f"（import: {', '.join(used[:2])}）" if used else ""))
        elif runtime and (ui_used or build_cfg):
            tier = "B"
            if ui_used: ev.append(f"UI ファイルで import: {', '.join(ui_used[:3])}" + (" 他" if len(ui_used) > 3 else ""))
            if build_cfg: ev.append(f"ビルド設定で参照: {', '.join(build_cfg)}")
        elif not runtime and build_cfg:
            tier = "B"; ev.append(f"devDependencies だが本番ビルド設定で参照: {', '.join(build_cfg)}（CSS/バンドルに影響）")
        elif not runtime and any(f.endswith((".css", ".scss")) for f in used):
            tier = "B"; ev.append("CSS から @import（本番の見た目に影響）")
        elif runtime and build_used and not used:
            tier = "B"; ev.append(f"ビルド時スクリプトで使用: {', '.join(build_used[:2])}（生成物が本番に載る）")
        elif runtime and used:
            tier = "B?"; ev.append(f"非 UI コードで使用: {', '.join(used[:3])} → 見た目に影響しなければ low_risk 候補")
        elif runtime:
            tier = "B?"; ev.append("dependencies だがソースからの import が見つからない（間接利用か未使用）")
        elif name in local_pkgs:
            tier = "S"; ev.append(f"CI で実行されない `{local_pkgs[name]}` スクリプトで使用")
        else:
            tier = "C"
            if name.startswith("@types/"): ev.append("型定義")
            elif dev_cfg: ev.append(f"開発ツール設定: {', '.join(dev_cfg[:2])}")
            else: ev.append("devDependencies（本番バンドル外）")
        if native:
            ev.append("ネイティブバイナリあり")
        rows.append(dict(name=name, dep_type="dependencies" if runtime else "devDependencies",
                         group=grp, tier=tier, evidence=ev, native=native,
                         used_in=len(used)))

    # group-level: a dependabot group is S if any member is S and none is A/B
    for g in groups:
        members = [r for r in rows if r["group"] == g]
        if any(r["tier"] == "S" for r in members) and not any(r["tier"] in ("A", "B") for r in members):
            for r in members:
                if r["tier"] == "C":
                    r["tier"] = "S"; r["evidence"].append(f"グループ `{g}` が S のため同梱")

    # peer checks: native direct dep that another direct dep also depends on
    peer_checks = []
    if nm_ok:
        for r in rows:
            if not r["native"]:
                continue
            for q in direct:
                if q == r["name"]:
                    continue
                qm = pkg_meta(repo, q) or {}
                # peerDependencies resolve to our own copy, so only (optional)dependencies can drift
                for field in ("dependencies", "optionalDependencies"):
                    if r["name"] in (qm.get(field) or {}):
                        peer_checks.append({"package": q, "peer": r["name"], "field": field,
                                            "requires": qm[field][r["name"]],
                                            "package_json": {**devdeps, **deps}.get(r["name"])})
    # pinned pairs: fully-ignored package that a direct dep pins exactly
    pinned = []
    if nm_ok:
        for ig in ignored_full:
            for q in direct:
                v = ((pkg_meta(repo, q) or {}).get("dependencies") or {}).get(ig)
                if v and re.match(r"^\d+\.\d+\.\d+", v):
                    pinned.append({"leader": q, "follower": ig, "leader_pins": v})

    t = {r["name"]: r["tier"] for r in rows}
    draft = {
        "repo_dir": a.repo_dir, "base_branch": base,
        "package_manager": pm if pm in ("pnpm", "npm") else "UNSUPPORTED:" + pm,
        "preview_required_groups": sorted({r["group"] for r in rows if r["tier"] == "A" and r["group"]}),
        "preview_required_packages": sorted(rx_name(n) for n, x in t.items() if x == "A"),
        "visual_packages": sorted(rx_name(n) for n, x in t.items() if x == "B"),
        "low_risk_runtime_packages": [],
        "local_only_packages": sorted(rx_name(n) for n, x in t.items() if x == "S"),
        "local_check_script": next(iter(sorted({s for s in local_pkgs.values()})), None),
        "merge_order": {"github-actions": 0, **{g: 1 for g in groups if any(t.get(r["name"]) == "A" for r in rows if r["group"] == g)},
                        **{g: 3 for g in groups if any(t.get(r["name"]) == "B" for r in rows if r["group"] == g)
                           and not any(t.get(r["name"]) == "A" for r in rows if r["group"] == g)},
                        "preview-required": 1, "visual": 3, "runtime-other": 5,
                        **{g: 7 for g in groups if all(t.get(r["name"]) == "S" for r in rows if r["group"] == g)
                           and any(r["group"] == g for r in rows)},
                        "dev-other": 7, "local-only": 7},
        "peer_checks": [{k: p[k] for k in ("package", "peer", "field")} for p in peer_checks],
        "pinned_pairs": [{"leader": p["leader"], "follower": p["follower"]} for p in pinned],
    }
    for g in groups:  # groups holding only unconfirmed runtime deps (B?) go before dev tooling
        if any(t.get(r["name"]) == "B?" for r in rows if r["group"] == g):
            draft["merge_order"].setdefault(g, 5)
        draft["merge_order"].setdefault(g, 6)
    out = dict(repo=a.repo_dir, package_manager=pm, base_branch=base, node_modules=nm_ok,
               dependabot=dict(schedule=sched, groups=groups, ignores=ignores),
               ci_runs_scripts=sorted(ran_in_ci), scripts_not_in_ci=not_in_ci,
               local_check_candidates=local_check_candidates, framework=sorted(framework),
               packages=rows, peer_check_candidates=peer_checks, pinned_candidates=pinned,
               needs_confirmation=[r["name"] for r in rows if r["tier"].endswith("?")],
               draft_config=draft)
    if a.format == "json":
        print(json.dumps(out, ensure_ascii=False, indent=1))
        return
    print(f"## 判定案（{a.repo_dir}）\n")
    print("| パッケージ | 種別 | Dependabot グループ | 判定案 | 根拠 |\n|---|---|---|---|---|")
    order = {"A": 0, "B": 1, "B?": 2, "S": 3, "C": 4, "-": 5}
    for r in sorted(rows, key=lambda r: (order.get(r["tier"], 9), r["group"] or "~", r["name"])):
        print(f"| `{r['name']}` | {'dep' if r['dep_type'] == 'dependencies' else 'dev'} | "
              f"{r['group'] or '—'} | {r['tier']} | {'; '.join(r['evidence'])} |")
    print(f"\n- CI で実行される scripts: {', '.join(sorted(ran_in_ci)) or 'なし'}")
    print(f"- CI で実行されないビルド/テスト系 scripts（S 候補）: {', '.join(local_check_candidates) or 'なし'}")
    print(f"- peer_checks 候補: {peer_checks or 'なし'}")
    print(f"- pinned_pairs 候補: {pinned or 'なし'}")
    if not nm_ok:
        print("- ⚠️ node_modules が無いため native / peer / pinned は未判定")


if __name__ == "__main__":
    main()
~~~~

**判定案の付け方**（どれも案であり、Step 3 でユーザーが確認する）

| 判定案 | 条件 |
|---|---|
| `-` | `dependabot.yml` で、バージョン指定なしに丸ごと `ignore` されている |
| `A` | `build` スクリプトのコマンドが、そのパッケージの bin（または同名のパッケージ）を実行している |
| `B?` | `dependencies` で、名前が計測・監視系（analytics、insights、sentry など）。または UI 以外のコードでしか使っていない、ソースからの import が見つからない |
| `B` | `dependencies` で、UI ファイルで import している、ビルド設定で参照している、またはビルド時スクリプトで使っている。`devDependencies` でも、ビルド設定や CSS から参照しているもの |
| `S` | CI で実行されないビルド・テスト系 scripts（`--ui`、`--watch`、`dev`、`start` を含むものは除く）で使われている。同じ Dependabot グループで A・B がないものは、グループごと S にする |
| `C` | 上のどれにも当たらない `devDependencies`（型定義、lint、テストツールなど） |
| `peer_checks` 候補 | ネイティブバイナリを持つ直接依存 P を、別の直接依存 Q も `dependencies` または `optionalDependencies` で要求している（`peerDependencies` は自分のコピーが使われるので対象外） |
| `pinned_pairs` 候補 | 丸ごと `ignore` されたパッケージ F を、直接依存 L が完全一致のバージョン（`x.y.z`）で要求している |

**限界**：ソースの探索対象は `src`、`app`、`pages`、`components`、`lib`、`layouts`、`styles`、`content`（ビルド時スクリプトとして `scripts`）です。モノレポや、これ以外の構成の場合は、エージェントが根拠を補うか `SRC_DIRS` を調整します。PyYAML がなくても、簡易パーサーで `dependabot.yml` を読みます。
