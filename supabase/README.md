# 対人レートの設定手順

友達対戦をレート戦にするための準備です。Supabase（無料のデータベース）と Google ログインを使います。
設定が終わるまでは、ゲーム画面にランク機能は表示されません（ほかの機能はそのまま遊べます）。

## 1. Supabase のプロジェクトを作る

1. https://supabase.com にGoogleアカウントで登録し、「New project」を押す
2. 名前は `shinzou-jinrou`、Region は `Northeast Asia (Tokyo)`、データベースのパスワードは自動生成でOK（控えておく）

## 2. データベースを用意する

1. 左メニューの「SQL Editor」を開く
2. このフォルダの `setup.sql` の中身を全部貼り付けて「Run」
   - 何度実行しても大丈夫です

## 3. Google ログインを用意する

**Google Cloud 側**

1. https://console.cloud.google.com で新しいプロジェクトを作る（名前は `shinzou-jinrou` など）
2. 「APIとサービス」→「OAuth 同意画面」で、アプリ名「心臓人狼」、サポートメールを入れて作成（ユーザーの種類は「外部」）
3. 「認証情報」→「認証情報を作成」→「OAuth クライアント ID」→ 種類は「ウェブ アプリケーション」
   - 承認済みの JavaScript 生成元：`https://pteratakahashi.github.io`
   - 承認済みのリダイレクト URI：Supabase の Google 設定画面（下の手順）に出ている Callback URL（`https://xxxx.supabase.co/auth/v1/callback` の形）
4. できた「クライアント ID」と「クライアント シークレット」を控える
5. 「OAuth 同意画面」で「アプリを公開」を押す（押さないと、自分が登録したテストユーザーしかログインできません）

**Supabase 側**

1. 「Authentication」→「Sign In / Providers」→「Google」を有効にして、クライアント ID とシークレットを貼って保存
2. 「Authentication」→「URL Configuration」
   - Site URL：`https://pteratakahashi.github.io/shinzou-jinrou/`
   - Redirect URLs に同じURLを追加

## 4. ゲームにつなぐ

「Project Settings」→「API」（「API Keys」）にある次の2つを、`index.html` の `const RANK_CFG={url:'',key:''};` に入れます。

- Project URL（`https://xxxx.supabase.co`）→ `url`
- anon / publishable key → `key`

この2つはページに公開されても大丈夫な値です（データの書き換えはサーバー側の関数でしかできないようにしてあります）。
service_role / secret key は絶対に入れないでください。

## しくみ

- ログインはGoogle。ランキングに出る名前は、ゲーム内で入れた名前（Googleの名前は出ません）
- 友達対戦で、おたがいがログインしているときだけレート戦になります
- 対戦開始時に両方のブラウザが試合を登録し、終了時に両方が勝者を報告します
  - 報告が一致 → レートに反映（イロレーティング、K=32、初期値1500）
  - 食い違い → 無効（レートは動かない）
  - 片方しか報告しない（相手がページを閉じた等）→ 10分後に報告どおり確定
- ランク：ランクポイント(pt)で ブロンズ→シルバー→ゴールド→プラチナ→ダイヤ→マスター と上がる（各100pt、ランク内は III→II→I）。勝つと約12〜40pt増え、負けると4〜26pt減る（相手との実力差で変わる）
- 500ptでマスター。マスターになると、裏で計算している内部レート（イロレーティング）が「マスターレート」として表示される
- ランクマッチ：待機列（queue テーブル）に入り、先に待っている人の中から内部レートが近い人とつながる。だれもいなければ自分が部屋を作って待つ

## SQLを更新したとき

`setup.sql` が変わったら、もう一度 SQL Editor に全部貼って「Run」してください。今までのデータは消えません。
