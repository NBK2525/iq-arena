# IQ ARENA

5つの頭脳ステージ（数字ルート・MAKE NUMBER・何が変わった？・シュルテ表・図形マトリックス）を通しでクリアし、合計タイムを競うブラウザゲーム。

## ファイル

| ファイル | 役割 |
|---|---|
| `index.html` | ゲーム本体（これ1つで動く） |
| `config.js` | Supabase の接続先。ここだけ書き換える |
| `supabase.sql` | ランキング用のデータベース設定。Supabase で1回実行する |

## 公開の手順

### 1. Supabase：ランキングの保存先を作る

1. Supabase で新しいプロジェクトを作る（既存のプロジェクトを使ってもよい）。
2. 左メニューの **SQL Editor** を開き、`supabase.sql` の中身を全部貼り付けて **Run** を押す。
   - 「Success. No rows returned」と出れば完了。
3. **Project Settings → API**（画面によっては **Data API** / **API Keys**）を開き、次の2つをコピーする。
   - **Project URL**（`https://xxxx.supabase.co`）
   - **anon public** キー（新しい画面では **Publishable key**）
   - ※ `service_role` / `Secret key` は絶対に使わない。

### 2. config.js を書き換える

```js
window.IQA_CONFIG = {
  supabaseUrl: "https://xxxx.supabase.co",
  supabaseAnonKey: "コピーしたキー"
};
```

anon（Publishable）キーは公開して問題ない値。記録の書き込みは `supabase.sql` の関数を通したものだけが通る。

### 3. GitHub：リポジトリを作ってファイルを置く

1. GitHub で新しいリポジトリを作る（例：`iq-arena`、Public でも Private でもよい）。
2. **Add file → Upload files** で `index.html`・`config.js`・`supabase.sql`・`README.md` をドラッグして **Commit changes**。

### 4. Cloudflare Pages：サイトとして公開する

1. Cloudflare ダッシュボード → **Workers & Pages** → **Create** → **Pages** → **Connect to Git**。
2. さっきのリポジトリを選ぶ。
3. ビルド設定：
   - Framework preset：**None**
   - Build command：**空欄**
   - Build output directory：**/**（空欄でも可）
4. **Save and Deploy**。数十秒で `https://iq-arena.pages.dev` のようなURLが発行される。

以降は GitHub のファイルを更新するたびに、自動でサイトも更新される。

## ランキングの仕組み

- 5ステージをパスなしでクリアした記録だけ登録できる。
- 1人1行（そのブラウザの自己ベスト）で並ぶ。難易度ごとに別のランキング。
- プレイヤーの見分けはブラウザごとのランダムなID。ログインは不要。
- サーバー側で次の記録を拒否する：ニックネームが1〜12文字でない／ステージ数が5でない／1ステージ2秒未満または30分超／同じプレイヤーから20秒以内の連続登録。

## 管理

- **不適切なニックネームや記録の削除**：Supabase の **Table Editor → iqa_scores** で該当の行を削除する。
- **全消去**：SQL Editor で `delete from public.iqa_scores;`
- Supabase の無料プランは、1週間アクセスがないとプロジェクトが一時停止する。停止したらダッシュボードから再開する。

## 既知の制限

タイムはプレイヤーのブラウザで計っているので、通信内容を書き換えれば偽の記録を送れてしまう。サーバー側の数値チェックで明らかにおかしいものは弾くが、完全には防げない。本格的に防ぐには、問題コードと解答手順をサーバーに送り、サーバー側で答え合わせとタイム計測をする方式（仕様書 8章）に移行する。
