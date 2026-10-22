# デザインシステム＆ハーネス セットアップ要件定義書

既存の Web アプリケーションのリポジトリを pnpm ワークスペースのモノレポに組み替え、デザインシステム（packages）とデザインハーネスの枠をセットアップするための要件定義書です。Claude Code などのコーディングエージェントに読み込ませ、フェーズごとに指示して使うことを想定しています。

対象リポジトリの環境（フレームワーク、スタイリング手法、パッケージマネージャなど）は事前に確認されていない前提です。エージェントは最初に環境を調査し、本書の判定表に従って構成を決めてから作業します。

---

## 0. 使い方

### 0.1 リポジトリへの置き方

本書を対象リポジトリの `docs/design-system-setup.md` として配置します（場所は任意。以下の指示文のパスを合わせてください）。

### 0.2 エージェントへの指示手順

次の順に、1フェーズずつ指示します。各フェーズの最後にエージェントが報告を出すので、内容を確認してから次へ進みます。

| 手順 | 指示文の例 | エージェントの成果物 |
| --- | --- | --- |
| 1 | `docs/design-system-setup.md` を読み、フェーズ0（環境調査）を実行して調査レポートを出してください。ファイルは変更しないでください。 | 調査レポート、構成案、変数の決定案 |
| 2 | 調査レポートの内容で確定します。（変更点があればここで伝える）フェーズ1を実行してください。 | 既存アプリの `apps/website` への移設 |
| 3 | フェーズ2を実行してください。 | `packages/` 配下5パッケージ |
| 4 | フェーズ3を実行してください。 | `apps/storybook`、`apps/docs`、`apps/harness` |
| 5 | フェーズ4を実行してください。 | 境界ルール、検査スクリプト、CI |
| 6 | フェーズ5を実行してください。 | 最終確認レポート、手動作業の手順書 |

途中で中断しても、どのフェーズまで完了したかは各フェーズの完了レポートとコミット履歴で判断できるようにします（2.3）。

### 0.3 本書で扱わないこと

- コンポーネントの網羅的な実装、ガイドライン本文の執筆
- ハーネスの中身（生成・レビュー・評価のロジック）の実装
- npm への公開、専用リポジトリへの切り出し
- Claude Design への同期の実行

---

## 1. 目的と全体像

### 1.1 目的

- **人とAIの両方が参照できるデザインシステム**：Material Design のように人が読めるガイドラインを持ち、同じファイルを Claude Design やハーネスの文脈としても使う。人向けとAI向けでドキュメントを二重管理しない。
- **Claude Design へ同期できる構成**：プロダクトUI用と、ブランド・コミュニケーション（スライド、広告バナー）用の2つのデザインシステムとして取り込めるようにする。
- **ハーネスを載せられる土台**：AIにデザインの文脈と制約を渡し、出力を検査・記録して改善につなげる仕組み（デザインハーネス）を、プロダクトから切り離した実験場として置けるようにする。
- **後から専用リポジトリへ切り出せること**：パッケージ間の境界と依存の向きを最初から守り、切り出し時の書き換えを最小にする。

### 1.2 完成後の構成

```
<repo>/
├─ package.json                  # ワークスペース定義と共通スクリプトのみ
├─ pnpm-workspace.yaml
├─ tsconfig.base.json
├─ <lint 設定>                   # 共通の lint 設定（境界ルールを含む）
│
├─ packages/
│  ├─ tokens/                    # {{SCOPE}}/tokens
│  ├─ brand/                     # {{SCOPE}}/brand
│  ├─ design-system/             # {{SCOPE}}/design-system（プロダクトUI）
│  ├─ communication/             # {{SCOPE}}/communication（スライド・バナー）
│  └─ guidelines/                # {{SCOPE}}/guidelines（横断ルール）
│
└─ apps/
   ├─ website/                   # 既存アプリを移設したもの
   ├─ storybook/                 # デザインシステム用カタログ
   ├─ docs/                      # 人向けドキュメントサイト（枠のみ）
   └─ harness/                   # デザインハーネス（枠のみ）
```

将来、専用リポジトリへ切り出すときは `packages/` 全体と `apps/storybook`・`apps/docs`・`apps/harness` をセットで移し、`apps/website` だけが残る想定です。この単位で移しても動くことを設計上の制約とします。

---

## 2. エージェントへの共通ルール

すべてのフェーズで守ってください。

### 2.1 安全に関するルール

1. 作業は専用のブランチ（例：`chore/design-system-setup`）で行う。既定ブランチへ直接コミットしない。
2. ファイルの移動は `git mv` で行い、履歴を保つ。ファイルの削除が必要な場合は、理由を報告して確認を取ってから行う。
3. 既存の依存パッケージのバージョンを上げない。新しく追加する依存は、既存の依存と互換性があるバージョンを選ぶ。
4. 既存アプリのアプリケーションコード（ページ、コンポーネント、ロジック）は変更しない。変更してよいのは、移設に伴うパスや設定ファイルの修正のみ。
5. 秘密情報（`.env*`、認証情報）の中身を読み取ったり、出力に含めたりしない。移設が必要な場合はファイルごと移す。
6. デプロイ先のサービス（Vercel、Netlify など）の設定は変更しない。必要な変更は手順書として提示する（フェーズ5）。

### 2.2 判断に迷ったときのルール

- 本書の判定表で決まらないこと、調査結果が本書の前提と食い違うことがあれば、推測で進めずに作業を止めて質問する。
- 「停止条件」に当てはまった場合は、そのフェーズを中断して状況を報告する。
- 本書の指示と、リポジトリ内の既存ルール（`CLAUDE.md`、`CONTRIBUTING.md` など）が食い違う場合は、作業を止めて確認する。

### 2.3 フェーズの進め方

- 1回の指示で実行するのは1フェーズのみ。次のフェーズへ勝手に進まない。
- フェーズの完了時に、その内容を1つ以上のコミットにまとめる。コミットメッセージの先頭に `[design-system-setup phase N]` を付ける。
- フェーズの完了時に、次の形式で完了レポートを出す：実施内容、変更・追加したファイルの一覧、受け入れ基準の確認結果（項目ごとに合否）、未解決事項、次のフェーズで必要な判断。
- 受け入れ基準を満たせない項目がある場合は、完了扱いにせず報告する。

---

## 3. 変数

本書では次の変数を使います。値はフェーズ0で決定し、調査レポートで提示します。以降のフェーズでは確定した値に置き換えて作業します。

| 変数 | 意味 | 決め方の既定 |
| --- | --- | --- |
| `{{SCOPE}}` | パッケージのスコープ名 | `@` ＋ ルートの package.json の `name`（スコープ付きならそのスコープ） |
| `{{FRAMEWORK}}` | 既存アプリのフレームワーク | 4.2 の判定表 |
| `{{STYLING}}` | スタイリング手法 | 4.3 の判定表 |
| `{{STORYBOOK_FRAMEWORK}}` | デザインシステム用 Storybook のフレームワーク | 常に `@storybook/react-vite` |
| `{{LINT_CONFIG}}` | lint の設定形式 | 既存に合わせる（flat config ／ 従来形式） |
| `{{DEPLOY}}` | デプロイ先 | 4.5 の判定表 |
| `{{REACT_VERSION}}` | React のバージョン | 既存アプリの package.json |

---

## 4. フェーズ0：環境調査

ファイルを一切変更せずに対象リポジトリを調査し、構成案を作ります。

### 4.1 調査項目

次の項目をすべて調べ、調査レポートに記載してください。

| 項目 | 調べる場所の例 |
| --- | --- |
| リポジトリ構成 | ルート直下のディレクトリとファイル、既にワークスペース構成か（`pnpm-workspace.yaml`、`workspaces` フィールド、`apps/`・`packages/` の有無） |
| パッケージマネージャ | `packageManager` フィールド、ロックファイル（`pnpm-lock.yaml`／`package-lock.json`／`yarn.lock`／`bun.lockb`） |
| フレームワーク | `dependencies`、設定ファイル（`next.config.*`、`vite.config.*`、`astro.config.*` など）、`app/`・`pages/`・`src/` の構成 |
| React の有無とバージョン | `react`、`react-dom` |
| スタイリング | `tailwindcss` のバージョン、`postcss.config.*`、`tailwind.config.*`、CSS Modules、CSS-in-JS ライブラリ |
| TypeScript | `typescript` のバージョン、`tsconfig.json` の設定（`paths`、`strict`） |
| Storybook | `storybook` のバージョン、`.storybook/` の設定とフレームワーク |
| テスト | Vitest、Jest、Playwright、Testing Library の有無 |
| lint・整形 | ESLint のバージョンと設定形式、Prettier、Stylelint、Biome |
| Git フック | husky、lint-staged、lefthook |
| CI | `.github/workflows/` などの内容 |
| デプロイ | `vercel.json`、`netlify.toml`、`@vercel/*` の依存、`Dockerfile` など |
| ビルド前後の処理 | `pre*`／`post*` スクリプト、`scripts/` 配下のスクリプトと、それが参照するパス |
| パスに依存する設定 | 絶対パスや相対パスを含む設定（`tsconfig` の `paths`、エイリアス、画像やフォントの参照） |
| 既存のデザイン資産 | 既存のデザイントークン、テーマ設定、共通コンポーネントの場所 |

### 4.2 フレームワークの判定

| 判定 | 条件 | 対応 |
| --- | --- | --- |
| `next-app` | `next` があり、`app/` または `src/app/` がある | 本書の標準対応。6.6 の Next.js 向け要件を適用 |
| `next-pages` | `next` があり、`pages/` のみ | 標準対応。6.6 のうち `"use client"` 以外を適用 |
| `vite-react` | `vite` と `react` があり、`next` がない | 標準対応。追加要件なし |
| `other-react` | React を使うその他（Remix、React Router、Astro＋React、Gatsby など） | 対応可能だが、調査レポートで個別の注意点を挙げて確認を取る |
| `non-react` | React を使わない（Vue、Svelte、Angular など） | **停止条件**。本書の packages は React 前提のため、作業を止めて報告する |

### 4.3 スタイリングの判定

| 判定 | 条件 | design-system／communication のスタイル方式 |
| --- | --- | --- |
| `tailwind-v4` | `tailwindcss` が 4.x | トークンから Tailwind の `@theme` を生成し、ユーティリティクラスで書く（6.3） |
| `tailwind-v3` | `tailwindcss` が 3.x | トークンから Tailwind のプリセット（`theme` 設定）を生成し、ユーティリティクラスで書く。既存アプリの Tailwind はアップグレードしない |
| `css` | Tailwind を使っていない | CSS Modules ＋ トークンの CSS カスタムプロパティで書く |
| `css-in-js` | styled-components、Emotion などが主 | **確認が必要**。CSS Modules ＋ CSS カスタムプロパティを提案し、既存アプリとの共存方法を調査レポートで示す |

いずれの方式でも、色・余白・角丸などの値はトークン経由でのみ使えるようにし、直値を書けないことを検査で担保します（8.3）。

### 4.4 パッケージマネージャの判定

| 判定 | 対応 |
| --- | --- |
| pnpm | そのまま使う |
| npm／yarn／bun | **確認が必要**。pnpm への移行を提案する。ユーザーが既存のパッケージマネージャを希望した場合は、そのワークスペース機能で同等の構成を作り、本書の pnpm 固有の記述を読み替える |

### 4.5 デプロイ先の判定

| 判定 | 移設後に必要な手動作業（フェーズ5で手順書にする） |
| --- | --- |
| Vercel | Root Directory を `apps/website` に変更、変更検知の条件（Ignored Build Step など）の設定 |
| Netlify | Base directory を `apps/website` に変更、ビルドコマンドの見直し |
| その他・不明 | 調査レポートで、移設がデプロイに与える影響と確認すべき点を挙げる |

### 4.6 停止条件

次のいずれかに当てはまる場合は、構成案を作らずに理由を報告してください。

- フレームワークの判定が `non-react`
- 既にモノレポ構成で、`apps/` や `packages/` に本書と衝突する既存のパッケージがある
- 作業ツリーにコミットされていない変更がある
- 既存アプリのビルドが、調査時点で失敗する（移設の前後で比較できないため）

### 4.7 調査レポートの形式

次の見出しで出力してください。

1. **調査結果**：4.1 の項目ごとの結果
2. **判定**：4.2〜4.5 の判定結果と、その根拠
3. **変数の決定案**：3章の変数ごとの値
4. **移設計画**：`apps/website` へ移すファイルとディレクトリの一覧、ルートに残すものの一覧、修正が必要な設定とパスの一覧
5. **リスクと注意点**：移設で壊れる可能性がある箇所と、その確認方法
6. **ユーザーに確認したいこと**：判断が必要な事項（なければ「なし」）

---

## 5. フェーズ1：既存アプリの移設

既存アプリを `apps/website` へ移し、リポジトリをワークスペース構成にします。このフェーズでは packages は作りません。

### 5.1 作業内容

1. 移設前の状態を記録する：既存アプリの `build`（あれば `test`、`lint`、`storybook` のビルドも）を実行し、結果を控える。
2. 調査レポートの移設計画に従い、アプリを構成するファイルとディレクトリを `apps/website/` へ `git mv` で移す。
3. ルートに残すもの：ワークスペース全体に関わる設定（`.git*`、`.github/`、Git フックの設定、エディタ設定、ライセンス、リポジトリ全体の README、本書）。
4. ルートの `package.json` を作り直す：`private: true`、`packageManager`、ワークスペース全体のスクリプト、共通の devDependencies（lint、整形、TypeScript、Git フック）のみにする。パッケージマネージャ全体の設定（pnpm の `overrides`、`onlyBuiltDependencies` など）はルートに残す。
5. `apps/website/package.json` を作る：アプリ固有の依存とスクリプトを既存の package.json から移す。`name` は `{{SCOPE}}/website` とする。
6. `pnpm-workspace.yaml` を作成し、`apps/*` と `packages/*` を登録する。
7. `tsconfig.base.json` をルートに作り、既存の `tsconfig.json` の共通部分を移す。`apps/website/tsconfig.json` はこれを `extends` する。
8. 移設で壊れたパス（スクリプト内のパス、設定ファイルの相対パス、`tsconfig` の `paths` など）を修正する。
9. Git フック（lint-staged など）がモノレポ全体に効くように設定を調整する。
10. ルートに、`apps/website` を対象にした `dev`・`build` などの委譲スクリプトを用意する（例：`pnpm --filter {{SCOPE}}/website dev`）。

### 5.2 受け入れ基準

- [ ] クリーンな状態から `pnpm install` が通る
- [ ] 移設前に実行できたコマンド（`build`、`test`、`lint`、`storybook` のビルドなど）が、`apps/website` で同じ結果になる
- [ ] ルートから `pnpm dev`・`pnpm build` で `apps/website` を起動・ビルドできる
- [ ] Git フックが動作する
- [ ] アプリケーションコードに、パス修正以外の差分がない

---

## 6. フェーズ2：packages の作成

`packages/` 配下に5つのパッケージを作ります。責務は次の基準で分けます。

- 媒体を問わないブランドの核 → `brand`
- 画面を操作させるための部品 → `design-system`
- 伝えるための表現（スライド、バナー） → `communication`
- 部品をまたぐルール → `guidelines`
- すべての値の正 → `tokens`

packages はアプリのフレームワークに依存させず、どの React 環境（Claude Design、Vite 製の Storybook、将来の別アプリ）でも動く状態を保ちます。

### 6.1 ディレクトリ構成

```
packages/
├─ tokens/
│  ├─ src/
│  │  ├─ primitive/              # color.json, typography.json, spacing.json, radius.json
│  │  └─ semantic/
│  │     ├─ product/             # UI用：surface, text-primary など
│  │     └─ expressive/          # 表現用：display系文字サイズ、ブランドアクセント
│  ├─ dist/                      # 生成物（git管理外）
│  ├─ style-dictionary.config.mjs
│  ├─ package.json
│  └─ README.md
│
├─ brand/
│  ├─ assets/
│  │  ├─ logo/                   # SVG：横組・縦組・単色・反転
│  │  ├─ fonts/
│  │  ├─ illustrations/
│  │  └─ photography/
│  ├─ guidelines/
│  │  ├─ logo.mdx
│  │  ├─ color-expression.mdx
│  │  ├─ typography-display.mdx
│  │  └─ imagery.mdx
│  ├─ package.json
│  └─ README.md
│
├─ design-system/
│  ├─ src/
│  │  ├─ components/
│  │  │  └─ Button/
│  │  │     ├─ Button.tsx
│  │  │     ├─ Button.stories.tsx
│  │  │     ├─ Button.test.tsx
│  │  │     ├─ Button.guidelines.mdx
│  │  │     └─ index.ts
│  │  ├─ styles.css              # スタイルのエントリ（6.3）
│  │  └─ index.ts
│  ├─ package.json
│  └─ README.md
│
├─ communication/
│  ├─ src/
│  │  ├─ slides/
│  │  │  ├─ layouts/             # TitleSlide, Section, BigNumber など
│  │  │  ├─ slides.guidelines.mdx
│  │  │  └─ examples/
│  │  ├─ banners/
│  │  │  ├─ formats.json         # 媒体別サイズとセーフエリア
│  │  │  ├─ components/          # BannerFrame, Headline, CTA, LogoLockup
│  │  │  ├─ banners.guidelines.mdx
│  │  │  └─ examples/
│  │  ├─ styles.css
│  │  └─ index.ts
│  ├─ package.json
│  └─ README.md
│
└─ guidelines/
   ├─ principles/
   ├─ foundations/               # color, typography, spacing, elevation, motion, iconography
   ├─ patterns/                  # collection-view, single-view, form, empty-state
   ├─ content/                   # voice-and-tone, terminology
   ├─ accessibility/
   ├─ contributing/              # 部品の提案方法、status の定義
   ├─ package.json
   └─ README.md
```

### 6.2 tokens（`{{SCOPE}}/tokens`）

- 値の正は、このパッケージの DTCG 形式 JSON とする。Figma などのデザインツールは、ここから生成した値を受け取る側として扱う。
- 3層で定義する：`primitive`（素の値）→ `semantic/product`、`semantic/expressive`（意味づけ）。semantic は primitive の参照のみで定義し、直値を書かない。
- Style Dictionary で次を生成する。
  - CSS カスタムプロパティ（`dist/css/variables.product.css`、`variables.expressive.css`）
  - TypeScript 定数（`dist/ts/`、型付き）
  - Figma Variables 取り込み用 JSON（`dist/figma/`）
  - `{{STYLING}}` に応じたテーマ（6.3）
- `product` と `expressive` は別ファイルで出力する。名前が衝突しないよう expressive には `display`、`brand` などの接頭辞を付け、両方を同時に読み込んでも問題ない状態にする。
- `exports` で生成物の公開範囲を明示する。
- tokens はビルドが必要なパッケージなので、ルートの `dev`・`build`・`storybook` の前にビルドが走るようにする。
- サンプル値：primitive に色10段階程度・文字サイズ・余白スケール・角丸、expressive に display 系の文字サイズ（48px 以上）とブランドアクセント2色。既存アプリにトークンやテーマ設定があれば、その値を使う。

### 6.3 スタイリング方式ごとの要件

| `{{STYLING}}` | tokens が生成するもの | 部品の書き方 | 利用側での読み込み |
| --- | --- | --- | --- |
| `tailwind-v4` | `dist/tailwind/theme.product.css`、`theme.expressive.css`（`@theme`）。Tailwind の名前空間（`--color-*`、`--text-*`、`--spacing-*`、`--radius-*`）に合わせ、既定テーマは `--color-*: initial` などでリセットする | ユーティリティクラス。任意値（`bg-[#fff]` など）は禁止 | 各パッケージの `src/styles.css` に `@source "./";` を書き、利用側はこの CSS を import するだけでクラスが検出されるようにする |
| `tailwind-v3` | Tailwind のプリセット（`dist/tailwind/preset.cjs`）。既定テーマは使わない設定にする | ユーティリティクラス。任意値は禁止 | 利用側の Tailwind 設定でプリセットを読み込み、`content` にパッケージのソースを含める |
| `css`／`css-in-js` | CSS カスタムプロパティのみ | CSS Modules。値は `var(--...)` でのみ参照する | `src/styles.css` で変数の CSS を読み込み、利用側はこれを import する |

いずれの方式でも、利用側の設定にパッケージへの相対パスを直接書く方法は避けてください（切り出し時に壊れるため）。避けられない場合は理由を完了レポートに記載します。

### 6.4 brand（`{{SCOPE}}/brand`）

- 媒体を問わないブランドの核を持つ。React コンポーネントは持たない。
- `assets/` はファイルをそのまま `exports` で公開する。フォントは、利用側のフレームワークの仕組み（Next.js なら `next/font/local`）でも、`@font-face` でも読み込める形にする。
- `imagery.mdx` には写真・イラストのトーンを言語化した語彙（光、色温度、構図、被写体との距離）を書く欄を設け、画像生成のプロンプトにも転用できる形にする。
- 今回は MDX の見出し構成とプレースホルダ文のみ作成する。ロゴはダミーの SVG でよい。

### 6.5 design-system（`{{SCOPE}}/design-system`）

- プロダクトUI用の React コンポーネントライブラリ。Claude Design の「Product UI」デザインシステムの同期対象。
- スタイルは tokens の product 系のみを使う。
- コンポーネントは1ディレクトリに「実装・ストーリー・テスト・ガイドライン・index」の5ファイルを揃える。
- props は TypeScript で型定義し、バリアントはユニオン型で表す。AI が型定義から使い方を引けるようにするため、props には JSDoc で用途を書く。
- ストーリーには代表例だけでなく、全バリアント・全状態（disabled、loading、長い文字列、空など）を含める。
- リンクや画像を扱う部品には、描画する要素を差し替えられる props（`as` や `asChild`）を持たせ、利用側がフレームワーク固有のコンポーネントを渡せるようにする。
- ビルドはせず、TypeScript のソースを直接公開する（`exports` が `src/` を指す）。React は `peerDependencies` に `{{REACT_VERSION}}` 互換の範囲で指定する。
- サンプル実装：Button、TextField、Card の3つ。

### 6.6 フレームワーク別の追加要件（design-system・communication 共通）

| `{{FRAMEWORK}}` | 追加要件 |
| --- | --- |
| `next-app` | フックやイベントハンドラを使うコンポーネントはファイル先頭に `"use client"` を書く。状態を持たない表示専用の部品には書かず、Server Components から使えるようにする。`apps/website` の Next.js 設定の `transpilePackages` に `{{SCOPE}}/*` のパッケージを追加する |
| `next-pages` | `transpilePackages` の追加のみ |
| `vite-react` | 追加要件なし（Vite はワークスペースの TypeScript ソースをそのまま扱える） |
| `other-react` | ワークスペースの TypeScript ソースを変換できるかを確認し、必要な設定を調査レポートと完了レポートに記載する |

どのフレームワークでも、packages からフレームワーク固有のモジュール（`next/*` など）を import することは禁止します（8.1）。

### 6.7 communication（`{{SCOPE}}/communication`）

- スライドと広告バナーの「型」を React コンポーネントとして持つ。Claude Design の「Brand & Communication」デザインシステムの同期対象。
- スタイルは tokens の expressive 系と `{{SCOPE}}/brand` のアセットを使う。`{{SCOPE}}/design-system` には依存しない。
- **slides**：16:9 を基準とし、レイアウトごとに受け取る内容を props で固定する（例：BigNumber は `value`、`label`、`note`）。サンプル実装は TitleSlide、Section、BigNumber の3つ。
- **banners**：`formats.json` に媒体名・幅・高さ・セーフエリア（上下左右の px）を持たせ、`BannerFrame` が `format` を受け取ってサイズとセーフエリアを決める。サンプルとして 1200×628、1080×1080、300×250、728×90 の4形式を定義する。
- `BannerFrame` のストーリーでは、同じ内容を全形式で一覧表示し、セーフエリアを可視化する。
- 6.5 のビルドなし公開、6.6 のフレームワーク別要件を同様に満たす。

### 6.8 guidelines（`{{SCOPE}}/guidelines`）

- コンポーネントをまたぐルールを MDX で持つ。コードは持たない。
- `patterns/` は画面の型（コレクションビュー、シングルビューなど）を扱い、各パターンに「構造・配置・状態・使うコンポーネント」の見出しを設ける。
- `contributing/` には status（draft／beta／stable／deprecated）の定義と、部品追加の提案手順の雛形を置く。
- 今回は各ディレクトリに1ファイルずつ、見出し構成とプレースホルダ文のみ作成する。

### 6.9 ドキュメント記述規約

すべてのガイドライン MDX は、共通のフロントマターと、種類ごとに固定した見出し構成を持ちます。人は拾い読みしやすく、AI は必要なセクションだけを引けるようにするためです。

**フロントマター（必須項目）**

```yaml
---
title: Button
kind: component          # component / foundation / pattern / content / brand / communication
status: draft            # draft / beta / stable / deprecated
category: actions
related: [IconButton, Link]
figma: ""                # 任意
updated: YYYY-MM-DD
---
```

**見出し構成（kind ごとに、この順で固定）**

| kind | 見出し |
| --- | --- |
| component | 概要／いつ使うか・使わないか／構成（anatomy）／バリアント／状態と振る舞い／文言／アクセシビリティ／Do・Don't |
| foundation | 概要／原則／値と使い分け／Do・Don't |
| pattern | 概要／構造／配置／状態／使うコンポーネント／Do・Don't |
| brand | 概要／ルール／使用例／NG例 |
| communication | 概要／型の一覧／情報量の上限／文言／Do・Don't |
| content | 概要／ルール／用語と表記／例 |

### 6.10 受け入れ基準

- [ ] 6.1 の構成どおりにディレクトリとファイルが存在する
- [ ] tokens のビルドで、CSS カスタムプロパティ、TS 定数、Figma 用 JSON、`{{STYLING}}` に応じたテーマが product／expressive 別に生成される
- [ ] Button、TextField、Card が product 系トークンのみでスタイルされ、全バリアント・全状態のストーリーがある
- [ ] TitleSlide、Section、BigNumber、BannerFrame が expressive 系トークンでスタイルされている
- [ ] `apps/website` から design-system のコンポーネントを import して、ビルドが通る（`next-app` の場合は Server Component のページから import する）
- [ ] すべての MDX が 6.9 の規約に従っている
- [ ] 各パッケージの README に、責務・属するデザインシステム（9.3）・利用側での読み込み方が書かれている

---

## 7. フェーズ3：apps の作成

デザインシステム用の Storybook と、docs・harness の枠を作ります。

### 7.1 apps/storybook（`{{SCOPE}}/storybook`）

- フレームワークは `@storybook/react-vite` とする。既存アプリが Next.js でも、packages がフレームワークに依存していないことを保証するため、Next.js 用のフレームワークは使わない。
- 既存アプリに Storybook がある場合、そのメジャーバージョンに揃える。既存のアプリ用 Storybook は `apps/website` に残し、統合しない。
- `packages/design-system` と `packages/communication` のストーリー、`packages/guidelines` と `packages/brand/guidelines` の MDX を読み込む。
- プレビューで tokens の CSS と各パッケージの `styles.css` を読み込む。`tailwind-v4` の場合は Vite 用の Tailwind プラグインを使う。
- アドオン：docs（MDX 表示）、a11y（アクセシビリティ検査）。
- サイドバーの構成：`Foundations`、`Patterns`、`Brand`、`Components`、`Communication/Slides`、`Communication/Banners`、`Contributing`。
- ビジュアルテスト：既存に Playwright があれば、ビルドした Storybook の全ストーリーのスクリーンショット比較を `test:visual` として用意する。Playwright がない場合は、追加するかどうかを完了レポートで確認する。

### 7.2 apps/docs（枠のみ）

- `package.json`（`{{SCOPE}}/docs`、private）と `README.md` のみを作る。
- README には、将来の構想として次を書く：packages の MDX と `guidelines-index.json`（8.2）を読み込み、人向けのドキュメントサイトを生成する。当面は apps/storybook が人向けドキュメントを兼ねる。

### 7.3 apps/harness（枠）

デザインハーネスは、AI にデザインの文脈と制約を渡し、生成した UI を検査・レビュー・記録して、ハーネス自身やデザインシステムの改善につなげる仕組みです。プロダクトに影響を与えずに試行錯誤できるよう、`apps/website` から切り離した実験場として置きます。今回は構造と最小限の検査のみを作り、生成やレビューのロジックは実装しません。

```
apps/harness/
├─ README.md                 # 目的、ループの説明、各ディレクトリの役割
├─ package.json              # {{SCOPE}}/harness。design-system, communication, tokens, guidelines に依存
├─ knowledge/
│  ├─ index.md               # 要件 → 使う部品の索引のみ。使い方の詳細は型定義とガイドラインを正として引かせる
│  └─ patterns.md            # 画面の型の一覧。本文は packages/guidelines/patterns を参照
├─ skills/
│  ├─ generate.md            # 作る：入力の下限、引いた使い方のみ使用、足りない部品は作らず記録
│  ├─ review.md              # レビュー：観点（部品／値／モデル／情報／配置）と直す先
│  └─ record.md              # 記録：ずれの書き方と振り分け先
├─ sandbox/                  # 生成した画面を置き、表示する場所（Vite + React）
│  └─ screens/
│     └─ example/            # サンプル画面1つ（design-system の部品のみで構成）
├─ checks/
│  ├─ typecheck              # sandbox の型チェック
│  └─ compliance             # 準拠チェック（7.3.1）
├─ records/
│  └─ TEMPLATE.md            # ずれの記録の雛形
└─ eval/
   ├─ README.md              # 改善用と測定用の画面を分ける方針
   ├─ dev/                   # 改善に使う依頼
   └─ holdout/               # 効果の測定にのみ使う依頼
```

#### 7.3.1 最小限の検査

`checks/` には、次の2つを動く状態で用意します。ほかの検査は README に今後の候補として列挙するに留めます。

1. **型チェック**：`sandbox/` 配下を TypeScript で検査する。存在しない props を使うと落ちる。
2. **準拠チェック**：`sandbox/` 配下で次を検出すると落ちる。
   - UI 部品を `{{SCOPE}}/design-system` 以外から import している
   - 生の操作要素（`<button>`、`<input>`、`<select>`、`<a>` など）を直接使っている
   - 直値（色コード、px 値、Tailwind の任意値）を使っている

#### 7.3.2 雛形の中身

- `skills/*.md` は、見出しと、各見出しに書くべき内容の説明のみ。
- `records/TEMPLATE.md` の項目：日付、依頼の内容、観点（部品／値／モデル／情報／配置）、ずれの内容、AI が推測で決めたことと根拠、直す先（ハーネスの知識・検査／ガイドライン／デザインシステムの部品）、対応状況。
- `eval/README.md` には「改善に使った依頼では効果を測らない」方針と、測定の手順（変更前に効果を予測する、同じ依頼を複数回生成する、二択で判定する）を書く。

### 7.4 受け入れ基準

- [ ] ルートから `pnpm storybook` でデザインシステム用 Storybook が起動し、7.1 のサイドバー構成でストーリーと MDX が閲覧できる
- [ ] apps/storybook の依存に、フレームワーク固有のパッケージ（`next` など）が含まれていない
- [ ] a11y アドオンで、サンプルのコンポーネントに重大な違反がない
- [ ] apps/harness の `sandbox/screens/example` が表示でき、型チェックと準拠チェックが通る
- [ ] 準拠チェックが、わざと違反させたサンプル（テスト用の別ファイル）を検出して落ちる
- [ ] apps/docs と apps/harness の README に、目的と各ディレクトリの役割が書かれている

---

## 8. フェーズ4：境界ルール・検査・CI

### 8.1 依存の向き

依存は下表の向きのみ許可し、それ以外は lint で禁止します。後から専用リポジトリへ切り出すための最重要の制約です。

| パッケージ | 依存してよい先 | 依存してはいけない先 |
| --- | --- | --- |
| tokens | なし | すべて |
| brand | tokens | design-system, communication, apps, フレームワーク |
| design-system | tokens | brand, communication, apps, フレームワーク |
| communication | tokens, brand | design-system, apps, フレームワーク |
| guidelines | なし（MDX でストーリーを埋め込む場合のみ例外） | apps |
| apps/website | packages/* | 他の apps |
| apps/storybook | packages/* | 他の apps, フレームワーク |
| apps/harness | packages/* | 他の apps, フレームワーク |

**ルール**

1. パッケージ間の参照は必ずパッケージ名で行う（`{{SCOPE}}/tokens` など）。`../../packages/...` のような相対パスでの参照は禁止。
2. 利用側は `workspace:*` で依存を宣言する。
3. 各パッケージは `package.json` の `exports` で公開範囲を明示する。`exports` にないファイルの import は禁止。
4. packages、apps/storybook、apps/harness からのフレームワーク固有モジュール（`next`、`next/*` など）の import は禁止。
5. 個別のビルド・tsconfig・lint 設定は各パッケージ内に置く。ルートの共通設定は最小限にする。
6. 上記を `{{LINT_CONFIG}}` 形式の ESLint 設定で、`eslint-plugin-boundaries` または `no-restricted-imports` を使って検査する。

### 8.2 ドキュメント検査

`pnpm check:docs` として次を実装します。

- すべてのガイドライン MDX について、6.9 のフロントマター必須項目と値の妥当性を検査する。
- 見出し構成が `kind` の定義と一致するかを検査する。
- 全 MDX のフロントマターを集約した索引 `guidelines-index.json` を生成する。docs とハーネスは、この索引から参照先を引く。

### 8.3 直値の検査

- design-system と communication で、色コード、px 値、Tailwind の任意値を使うと落ちる検査を用意する（`{{STYLING}}` に合わせて ESLint、Stylelint、独自スクリプトのいずれかで実装）。
- 検査の対象外にしたい箇所（トークンを生成するコードなど）は、明示的な除外設定で指定する。

### 8.4 検査が正しく落ちることの確認

8.1〜8.3 の各検査について、わざと違反させたファイル（`__fixtures__/` などに置き、通常の lint 対象からは除外）を用意し、検査がそれを検出して失敗することをテストで確認します。

### 8.5 CI

- `.github/workflows/` があるか、GitHub のリポジトリであれば、GitHub Actions のワークフローを追加する。それ以外の CI の場合は、追加すべき内容を完了レポートに記載する。
- プルリクエストで次を実行する：lint、型チェック、テスト、`check:docs`、`apps/website` のビルド、apps/storybook のビルド、apps/harness の検査。
- 既存の CI ワークフローは削除せず、パスの修正のみ行う。

### 8.6 受け入れ基準

- [ ] 8.1 の禁止された import（相対パス参照、逆向きの依存、フレームワーク固有モジュール）を書くと lint が落ちる
- [ ] 8.2 の検査が違反を検出し、`guidelines-index.json` を生成する
- [ ] 8.3 の検査が直値を検出する
- [ ] 8.4 のテストがすべて通る
- [ ] CI でプルリクエスト時に 8.5 の項目が実行される

---

## 9. フェーズ5：最終確認と手動作業の手順書

### 9.1 最終確認

クリーンな状態（`node_modules` と生成物を削除した状態）から、次をすべて実行して結果を報告します。

- `pnpm install`
- `pnpm build`（tokens → apps/website）
- `pnpm lint`、`pnpm typecheck`、`pnpm test`、`pnpm check:docs`
- apps/storybook のビルド
- apps/harness の検査
- 5.2 で控えた移設前の結果との比較

### 9.2 手動作業の手順書

エージェントが実施しなかった、人が行う作業を手順書として出力します。少なくとも次を含めます。

- デプロイ先の設定変更（4.5 の判定に応じた内容）。画面上の操作手順と、変更後に確認すべきこと。
- ブランチのマージ手順と、マージ後に確認すべきこと。
- Claude Design への同期の進め方（9.3）。

### 9.3 Claude Design への同期の想定

構築後、Claude Code の `/design-sync` で、2つのデザインシステムとして取り込むことを想定しています。同期の実行は本書の範囲外です。同期対象をどの粒度で指定できるかは、実際に試して確認してください。

| デザインシステム | 含めるもの | 主な用途 |
| --- | --- | --- |
| Product UI | tokens（product）、design-system、guidelines | アプリ画面、管理画面、プロトタイプ |
| Brand & Communication | tokens（expressive）、brand、communication、guidelines の content と principles | 資料スライド、広告バナー |

### 9.4 受け入れ基準

- [ ] 9.1 のすべてのコマンドが成功し、移設前と比べて既存アプリの挙動に差がない
- [ ] 9.2 の手順書が出力されている
- [ ] 各フェーズの完了レポートとコミットがそろっている

---

## 10. よくある問題と対処

| 症状 | 主な原因 | 対処 |
| --- | --- | --- |
| パッケージ内の Tailwind クラスにスタイルが当たらない | Tailwind がパッケージのソースをスキャンしていない | `tailwind-v4` は `src/styles.css` の `@source` と、利用側での import を確認。`tailwind-v3` は利用側の `content` にパッケージのソースが含まれているか確認 |
| Next.js で「フックは Client Component でのみ使える」旨のエラー | `"use client"` の付け忘れ | フックやイベントハンドラを使う部品のファイル先頭に `"use client"` を追加 |
| Next.js でパッケージの TypeScript が読み込めない | 変換対象に含まれていない | `transpilePackages` に `{{SCOPE}}/*` のパッケージを追加 |
| React が二重に読み込まれる、フックのエラーが出る | packages が React を dependencies に持っている | packages では React を `peerDependencies` にのみ置く |
| 移設後にスクリプトや画像が見つからない | ルート基準のパスが残っている | 調査レポートのパス依存一覧と照合し、`apps/website` 基準に修正 |
| `pnpm install` 後にネイティブ依存が動かない | ビルドが許可されていない | ルートの `onlyBuiltDependencies` などの設定が移設で失われていないか確認 |
