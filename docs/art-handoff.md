# 心臓人狼：新カード30種のイラストを作って反映する（Claude Code 向けの指示書）

リポジトリ: https://github.com/pteratakahashi/shinzou-jinrou
本番は `main` ブランチ（GitHub Pages）。カードの絵は `art/<key>.png`（252×252、背景透過のPNG）。
絵がないカードは、今はカード名の漢字1文字が色付きのタイルで表示されている。絵を置けば自動でそちらが表示される（`index.html` の変更は不要）。

## ゴール
1. 下の表の30種について、Gemini の画像生成で、既存のカードと同じ画風のドット絵を作る
2. 背景を透過し、顔の大きさと位置を名探偵（`art/greatdet.png`）に合わせて切り出し、`art/<key>.png`（252×252）として保存する
3. 既存の52枚と並べた一覧画像で確認してから、`main` に push する

## 進め方
- Gemini API（AI Studio の murakage プロジェクト。前払いのクレジットあり）で生成する。APIキーはユーザーに聞くこと。コードやリポジトリには絶対に書かない（環境変数で渡す）
- モデル：Nano Banana 2.1（`gemini-nano-banana-2.1`）。出力は画像のみ、縦横比 1:1
- 1枚ずつ作ってその場で目で確認し、だめなら作り直す（数値だけで判断しない）

## 画風の見本の作り方
既存の絵から見本を4枚選んで、1枚の参照画像にまとめて毎回添付する。
- 見本：`art/greatdet.png`（名探偵）、`art/bard.png`（吟遊詩人）、`art/detective.png`（探偵）、`art/saint.png`（聖女）
- 2×2 に並べた 1024×1024 の画像にする（背景は #A99B76）

## プロンプト（共通部分）
```
Create a new pixel art character portrait in exactly the same style as the four reference portraits in the attached image: clean thick dark outlines, flat cel shading, limited palette, simple anime-style face, the same chunky pixel size, dark-fantasy medieval werewolf village setting. Character: {説明}. FRAMING: a wide waist-up shot. Show the whole head (and hat, if any) with empty space above it, both shoulders and arms inside the frame, body down to the waist at the bottom edge. The face is about one sixth of the image height and the top of the head is at about 20 percent from the top. Centered, facing the viewer. Background: one flat solid color #A99B76 only, no gradient, no shadow, no scenery, no text, no border.
```
動物・魔物のキャラ（鼠男・遠吠えなど）は「face」を「head」と読み替えてよい。

## 作るカード（30種）
| key | 名前 | 系統 | キャラの説明（{説明} に英語で入れる） |
|---|---|---|---|
| fortune | 易者 | 情報 | an old East-Asian-style fortune teller in a dark robe and round hat, holding divination sticks |
| listener | 聞き耳 | 情報 | a sly young eavesdropper with a hood, cupping one hand behind a large ear, grinning |
| diviner | 祈祷師 | 情報 | a shaman woman with a feathered headdress and beads, holding a smoking incense bowl |
| tracker | 追跡者 | 情報 | a rugged tracker with a fur collar and short cloak, crouching slightly, holding a lantern and studying footprints |
| confessor | 告解師 | 情報 | a calm priest in a black cassock with a purple stole, half-hidden behind a lattice screen |
| stargazer | 星読み | 情報 | a young astronomer girl with a star-patterned scarf, holding a small brass telescope |
| clairvoy | 千里眼 | 情報 | a blindfolded seer with a glowing third eye mark on the forehead, hands raised |
| berserker | 猛り狼 | 攻撃 | a huge snarling werewolf with torn armor pieces and wild mane, claws raised |
| ghoul | 屍鬼 | 攻撃 | a gaunt pale ghoul with sunken glowing eyes and tattered burial clothes |
| kidnapper | 人さらい | 攻撃 | a masked kidnapper with a big empty sack over one shoulder and a rope |
| howler | 遠吠え | 攻撃 | a grey wolf-man howling upward, head tilted back, moonlight on the fur |
| nightmare | 夢魔 | 攻撃 | a seductive dream demon with small bat wings and curled horns, purple haze around the hands |
| wererat | 鼠男 | 攻撃 | a hunched rat-man with whiskers and a long tail, holding a stolen bundle of cards |
| witch | 魔女 | 攻撃 | a witch with a tall crooked pointed hat, green-tinted skin, holding a bubbling potion |
| alpha | 狼王 | 攻撃 | a regal black werewolf king wearing a bone crown and a red cape |
| knight | 騎士 | 防御 | a young knight in polished plate armor with a kite shield and a sword |
| nun | 修道女 | 防御 | a strict nun in a black-and-white habit holding a rosary and a ruler |
| watchman | 夜警 | 防御 | a night watchman with a lantern on a pole and a whistle, wearing a long coat |
| shieldbearer | 盾持ち | 防御 | a stocky soldier holding a huge wooden round shield in front of the chest |
| lookout | 物見 | 防御 | a lookout scout with a spyglass and a feather cap, shading the eyes with one hand |
| cleric | 癒し手 | 防御 | a gentle healer woman with herb pouches, hands glowing softly with green light |
| exorcist | 祓い師 | 防御 | an exorcist monk holding paper talismans and a sacred staff with bells |
| banker | 両替商 | 補助 | a plump money changer with spectacles, a coin purse and an abacus |
| gravedigger | 墓守 | 補助 | a tired gravedigger with a shovel over the shoulder and a dirty apron |
| messenger | 伝令 | 補助 | a young messenger boy with a satchel full of letters and a horn |
| tactician | 参謀 | 補助 | a cool strategist in a dark coat holding a folded map and a chess piece |
| innkeeper | 宿屋 | 補助 | a cheerful innkeeper woman with an apron holding a tray with a mug of ale |
| drummer | 鼓手 | 補助 | a village drummer with a small war drum at the hip and drumsticks raised |
| gambler | 博徒 | 補助 | a grinning gambler with a scar, rolling dice in one hand, coins at the belt |
| moonqueen | 月の女王 | シングル | a majestic queen with silver hair, a crescent moon crown and a starry gown (single legendary card, make it especially elegant) |

## 切り出しのルール（いちばん大事）
1. 背景（#A99B76 付近の色）を、四辺からの塗りつぶしで透過にする。キャラの内側の同系色は消さない
2. 各絵で「顔の横幅」「目の高さ」「あごの高さ」を測る（動物は鼻先まで）
3. 名探偵の切り出し結果が基準：252×252 の中で、顔の横幅 約66px、目の高さ 約96px、あご 約150px、顔の中心が横126px
4. その基準に合うように拡大縮小・位置合わせして 252×252 で書き出す。下が足りないときは透過のままでよい（カード側で下端をふんわり消している）
5. ドット感を保つため、縮小は最後に1回だけ（NEAREST か LANCZOS で見比べて、くっきりする方）
6. 参考：前に使った切り出しスクリプトが `preview-art` ブランチの `genref/norm_old.py` にある

## 確認
- 新しい30枚と既存の52枚を同じ大きさで並べた一覧画像を作る。名探偵の顔の枠（上の数値）を全カードに重ねて、大きさと位置がそろっているか1枚ずつ目で確認する
- ゲームの中でも確認する：`index.html` を開いて、コンソールで次を実行するとカード枠込みで並ぶ
  `document.getElementById('app').innerHTML='<div style="display:flex;flex-wrap:wrap;gap:6px">'+CARDS.map(c=>cardHTML(c.k,'m')).join('')+'</div>'`
- 画風が浮いている・顔の大きさが合わない絵は作り直す

## 反映
- `art/<key>.png` を30枚追加して `main` に commit・push（GitHub Pages に数分で反映）
- コミットメッセージは日本語で「新カード30種のイラストを追加」など
- 終わったら一覧画像をユーザーに見せる

## 余力があれば（任意）
既存52枚の「腰上で描き直し」が途中で止まっている（`preview-art` ブランチの `genraw/` に30枚まで）。同じ手順でそろえると全体の画風が統一できる。こちらはユーザーに確認してから進めること。
