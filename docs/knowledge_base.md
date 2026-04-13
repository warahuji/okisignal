# SMC_FVG EA 完全知識ベース

このドキュメントはSMC_FVG EA（FXシグナル配信EA）に関するすべての情報を網羅しています。
AIアシスタントがこのEAに関するあらゆる質問に回答するための知識ベースです。

---

## 1. システム概要

### EA名
- 正式名称: SMC_FVG_Standalone
- ファイル: `SMC_FVG_Standalone.mq5`（外部include不要の単一ファイル）
- バージョン: 1.00

### 何をするEAか
- 8通貨ペアを同時に自動トレードし、エントリー/決済のシグナルをDiscordに配信する
- 1つのチャートに貼るだけで全ペアをカバー（マルチペア対応）
- Smart Money Concepts（SMC）の手法をベースにしたアルゴリズム

### 対象通貨ペア（8ペア）
USDJPY#, EURUSD#, GBPUSD#, AUDUSD#, GBPJPY#, EURJPY#, AUDJPY#, GOLD#

### 動作環境
- プラットフォーム: MetaTrader 5（MT5）
- ブローカー: XM Trading（KIWAMI口座必須）
- 口座番号: 75443293（デモ）
- 口座通貨: JPY
- サーバー: XMTrading-MT5 3
- VPS: 24時間稼働必須
- XM KIWAMIのゴールドシンボル名は「GOLD#」（XAUUSD#ではない）

---

## 2. トレードロジック（初心者向け）

### 一言で説明
「相場の流れが変わった瞬間を見つけて、価格が一瞬戻ったところでエントリーする」

### 3ステップの詳細

#### ステップ1: 相場の「山」と「谷」を見つける（Swing Point）
- チャート上で「一番高い場所（山のてっぺん）」と「一番低い場所（谷の底）」を自動検出
- 15分足（M15）のローソク足を使用
- ペアごとに「何本の足で確認するか」が異なる（SwingLenパラメータ: 3〜8本）
- 確定した足のみ使用（未確定の足は無視）

#### ステップ2: 「壁を突き破った」を検知する（BOS = Break of Structure）
- 価格が「山のてっぺん」を上に突き抜けたら → 上昇トレンド開始と判断
- 価格が「谷の底」を下に突き抜けたら → 下降トレンド開始と判断
- 終値ベースで判定（ヒゲだけの突破は無視）
- これにより「相場の方向」が決まる

#### ステップ3: 「価格のすき間」で乗る（FVG = Fair Value Gap）
- トレンドが変わった後、価格が一気に動いた場所にできる「すき間」を探す
- 3本の連続するローソク足で、1本目のhighと3本目のlowの間に隙間がある場合 = FVG
- この隙間に価格が戻ってきたタイミングでエントリー
- なぜ機能するか: 大口投資家（銀行など）が急いで大量注文した痕跡であり、残りの注文が同じ方向に価格を押すため

### エントリー後の管理（4段階）
1. **エントリー**: 損切り（SL）と利確目標（TP1）を自動設定して発注
2. **TP1到達**: ロットの50%を利確して利益を確保
3. **SL移動**: SLをエントリー価格に移動（= ブレイクイーブン、以降損失ゼロ保証）
4. **TP2狙い**: 残り50%でさらに大きな利益を狙う

### フィルター（3つの安全装置）
1. **セッションフィルター**: 各通貨ペアが最も動きやすい時間帯のみトレード（GMT時間）
2. **ADRフィルター**: その日すでに平均的な値幅以上に動いた場合はトレードしない
3. **1ペア1ポジション制限**: 同じ通貨ペアで複数ポジションを持たない

---

## 3. SL・TP・ロットの計算ロジック

### SL（損切り）の決め方
- **ATR（平均的な値動き幅）× SLMult倍** でエントリー価格から逆方向に設定
- ATRは直前14本のM15足の平均値動き幅（InpATRPeriod=14）
- 例: USDJPY#でATR=0.30円、SLMult=0.75の場合
  - 買いエントリー: SL = エントリー価格 - (0.30 × 0.75) = エントリー価格 - 0.225円
  - 売りエントリー: SL = エントリー価格 + 0.225円
- SLMultはペアごとに0.75〜2.50で最適化済み（狭い=損小利大型、広い=ノイズ耐性型）

### TP1（第1利確目標）の決め方
- **ATR × TP1Mult倍** でエントリー価格から順方向に設定
- 例: ATR=0.30円、TP1Mult=2.50の場合
  - 買いエントリー: TP1 = エントリー価格 + (0.30 × 2.50) = エントリー価格 + 0.75円
- TP1到達時にロットの50%を決済し、SLをエントリー価格に移動（BE化）

### TP2（第2利確目標）の決め方
- **ATR × TP2Mult倍** でエントリー価格から順方向に設定
- TP1で半分決済後、残りの50%がTP2を狙う
- TP2Multはペアごとに2.5〜5.0で最適化済み

### ロットサイズの計算
- `OrderCalcProfit()`（MQL5公式関数）を使用
- 計算式: 「SLに到達した場合の1ロットあたりの損失額」を算出し、「許容リスク額 ÷ 損失額」でロットを決定
- 許容リスク額 = 口座残高 × InpRiskPercent(1.0) ÷ 100
- 例: 残高100,000円、リスク1%の場合 → 許容損失 = 1,000円
  - 1ロットでSLまでの損失が10,000円なら → ロット = 1,000 ÷ 10,000 = 0.1ロット
- 安全策: 計算結果に関係なく**最大5ロット**の上限あり
- OrderCalcProfitは通貨変換（GOLD→JPY等）を自動で処理する

### SL/TP/ロット計算の具体例（USDJPY#）
```
残高: 100,000 JPY
ATR(14): 0.30円
SLMult: 0.75 → SL距離 = 0.30 × 0.75 = 0.225円（22.5pips）
TP1Mult: 2.50 → TP1距離 = 0.30 × 2.50 = 0.75円（75pips）
TP2Mult: 3.50 → TP2距離 = 0.30 × 3.50 = 1.05円（105pips）
リスク: 100,000 × 1% = 1,000円
1ロットで22.5pips負け = 約22,500円
ロット: 1,000 ÷ 22,500 = 0.04ロット

→ SL -22.5pips / TP1 +75pips / TP2 +105pips
→ リスクリワード比 = 1:3.3（TP1）〜 1:4.7（TP2）
```

---

## 4. 通貨ペア別パラメータ（最適化済み）

バックテスト期間: 2025.01.01 - 2026.04.01（15ヶ月）
口座: XM KIWAMI デモ、初期資金100,000 JPY、複利運用（残高1%リスク）

### USDJPY# ★エース
- SwingLen: 4 / SLMult: 0.75 / TP1Mult: 2.50 / TP2Mult: 3.5
- ADRMaxRatio: 0.5 / Session: 6-18 GMT（東京〜ロンドン）
- 結果: +261,164 JPY / PF 1.20 / DD 16.4% / 691回（1.5回/日）
- Recovery Factor: 4.09 / Sharpe Ratio: 7.02
- 特徴: SLが狭く（0.75xATR）TPが広い。損小利大の典型。勝率は低いが1勝の利益が大きい

### EURUSD#
- SwingLen: 8 / SLMult: 2.50 / TP1Mult: 2.25 / TP2Mult: 4.5
- ADRMaxRatio: 0.7 / Session: 14-19 GMT（NY集中）
- 結果: +15,328 JPY / PF 1.10 / DD 8.6% / 371回（0.8回/日）
- Recovery Factor: 1.73 / Sharpe Ratio: 1.85
- 特徴: DDが最も低い（8.6%）。安定型

### GBPUSD#
- SwingLen: 6 / SLMult: 1.00 / TP1Mult: 2.50 / TP2Mult: 2.5
- ADRMaxRatio: 0.6 / Session: 14-19 GMT（NY集中）
- 結果: +12,434 JPY / PF 1.06 / DD 22.7% / 348回（0.8回/日）
- Recovery Factor: 0.48 / Sharpe Ratio: 1.50
- 特徴: DDが最も高い（22.7%）。要注意ペア

### AUDUSD# ★高効率
- SwingLen: 7 / SLMult: 2.25 / TP1Mult: 1.75 / TP2Mult: 5.0
- ADRMaxRatio: 0.5 / Session: 14-22 GMT（NY〜深夜）
- 結果: +13,371 JPY / PF 1.27 / DD 10.1% / 128回（0.3回/日）
- Recovery Factor: 1.12 / Sharpe Ratio: 6.55
- 特徴: PFが最も高い（1.27）。取引数は少ないが効率的

### GBPJPY#
- SwingLen: 7 / SLMult: 2.50 / TP1Mult: 2.00 / TP2Mult: 5.0
- ADRMaxRatio: 0.6 / Session: 10-16 GMT（ロンドン）
- 結果: +12,825 JPY / PF 1.10 / DD 11.0% / 342回（0.8回/日）
- Recovery Factor: 1.12 / Sharpe Ratio: 1.97
- 特徴: バランス型

### EURJPY# ★準エース
- SwingLen: 5 / SLMult: 2.00 / TP1Mult: 2.50 / TP2Mult: 4.0
- ADRMaxRatio: 0.9 / Session: 10-17 GMT（ロンドン）
- 結果: +49,592 JPY / PF 1.11 / DD 14.5% / 672回（1.5回/日）
- Recovery Factor: 2.18 / Sharpe Ratio: 2.52
- 特徴: USDJPY#に次ぐ利益。取引数も多い

### AUDJPY#
- SwingLen: 7 / SLMult: 2.50 / TP1Mult: 2.25 / TP2Mult: 3.0
- ADRMaxRatio: 0.6 / Session: 6-17 GMT（東京〜ロンドン）
- 結果: +6,707 JPY / PF 1.03 / DD 9.8% / 480回（1.1回/日）
- Recovery Factor: 0.62 / Sharpe Ratio: 0.66
- 特徴: PFがギリギリ（1.03）。改善余地あり

### GOLD#
- SwingLen: 5 / SLMult: 1.25 / TP1Mult: 0.75 / TP2Mult: 3.5
- ADRMaxRatio: 1.0 / Session: 4-19 GMT（朝〜NY）
- 結果: PF 1.20 / DD 13.2% / 3,658回（8回/日）
- 特徴: 取引頻度が圧倒的に高い。利益額はバックテストでは複利で爆発するため参考値

### 共通パラメータ
- RiskPercent: 1.0（残高の1%をリスク）
- TP1ClosePct: 50.0（TP1で半分決済）
- ATRPeriod: 14
- MagicBase: 106（ペアごとに106+index）
- 時間足: M15

---

## 4. EA設定方法

### 入力パラメータ
EAはカンマ区切りの文字列でペアごとのパラメータを受け取る。デフォルト値は最適化済み。

```
InpWebhookUrl    = ""  ← Discord Webhook URL（必須）
InpRiskPercent   = 1.0
InpTP1ClosePct   = 50.0
InpATRPeriod     = 14
InpMagicBase     = 106
InpTradeEnabled  = true ← falseにするとシグナル配信のみ（トレードしない）
InpSymbols       = "USDJPY#,EURUSD#,GBPUSD#,AUDUSD#,GBPJPY#,EURJPY#,AUDJPY#,GOLD#"
InpSwingLens     = "4,8,6,7,7,5,7,5"
InpSLMults       = "0.75,2.50,1.00,2.25,2.50,2.00,2.50,1.25"
InpTP1Mults      = "2.50,2.25,2.50,1.75,2.00,2.50,2.25,0.75"
InpTP2Mults      = "3.5,4.5,2.5,5.0,5.0,4.0,3.0,3.5"
InpADRMaxRatios  = "0.5,0.7,0.6,0.5,0.6,0.9,0.6,1.0"
InpSessionStarts = "6,14,14,14,10,10,6,4"
InpSessionEnds   = "18,19,19,22,16,17,17,19"
```

### VPS設置手順
1. `SMC_FVG_Standalone.mq5`をVPSのMT5 Expertsフォルダにコピー
2. MT5でコンパイル（右クリック → コンパイル）
3. MT5オプション → エキスパートアドバイザ → WebRequest許可URLに `https://discord.com` を追加
4. KIWAMI口座(75443293)にログイン
5. 任意のチャートを1つ開く（通貨ペア・時間足は何でもOK）
6. EAをチャートにドラッグ＆ドロップ
7. Discord Webhook URLを入力 → OK
8. Market WatchにUSJDPY#が表示されていることを確認（GOLD#の通貨変換に必要）

### 動作確認
- エキスパートタブに「SMC_FVG_Multi initialized: 8 symbols (warm-up done)」が表示される
- 各ペアの「WarmUp: SH=xxx SL=xxx BOS=Bull/Bear FVG=Bull/Bear」が表示される
- LotCalcログでロットサイズが妥当か確認（残高10万円で0.01〜0.3ロット程度が正常）

---

## 5. Discord配信

### エントリー通知の内容
- SIGNAL --- SMC_FVG
- 通貨ペア / 売買方向（BUY/SELL）
- エントリー価格
- SL価格（pipsも表示）
- TP1価格（pipsも表示）/ TP2価格（pipsも表示）
- ロットサイズ
- 買い=緑色 / 売り=赤色のEmbed

### 決済通知の内容
- CLOSED --- SMC_FVG (決済理由)
- 通貨ペア / 結果（損益pips / 損益金額）
- 保有時間
- エントリー価格 / 決済価格
- 利益=緑色 / 損失=赤色のEmbed

### 決済理由の種類
- TP1: 第1利確目標で部分決済（50%）
- TP2: 第2利確目標で全決済
- SL: 損切り
- BE: ブレイクイーブン（建値決済、損益ゼロ）
- Manual: 手動決済

---

## 6. 技術的な仕組み

### マルチペア動作
- OnTimer()で1秒ごとに全8ペアを巡回（チャートシンボルに依存しない）
- OnTick()ではTP1管理のみ実行（高頻度が必要なため）
- ペアごとにSymbolState構造体で状態を管理

### WarmUp機能（起動時の即時初期化）
- EA起動時に過去100本のM15足をスキャンしてSwing/BOS/FVGを構築
- 再起動後すぐにトレード可能（データ蓄積待ち不要）

### ロットサイズ計算（OrderCalcProfit方式）
- MQL5公式関数 `OrderCalcProfit()` を使用
- GOLD等のクロス通貨でも正しい通貨変換が自動適用される
- 安全策: 計算結果に関係なく最大5ロットの上限あり
- OrderCalcProfitが0を返した場合はトレードしない（Market Watchに変換ペアがない場合に発生）

### 過去のバグと修正履歴
1. **CalcLotSizeのGOLDバグ（致命的・修正済み）**: SYMBOL_TRADE_TICK_VALUEがJPY口座で小さい値を返し、ロットが100倍以上に膨張。29ロットでGOLD取引して口座破綻。OrderCalcProfit()に全面書き換えで修正
2. **MQL5の`color`予約語**: 変数名`color`はMQL5で型名のため使用不可。`clr`に変更済み
3. **暗黙の文字列連結**: MQL5ではC言語の`"a" "b"`連結が使えない。`+`で明示連結に修正
4. **IsNewBar()のマルチシンボル対応**: static変数では1シンボルしか管理できない。SymbolState.lastBarTimeで個別管理

---

## 7. ブローカー別の注意事項

### XM KIWAMI（推奨）
- スプレッドが狭く、最適化結果が最も良い
- シンボル名に `#` サフィックス（USDJPY#, GOLD#など）
- ゴールドは `GOLD#`（XAUUSD#ではない）

### XM スタンダード（非推奨）
- スプレッドが広く、全ペアで大幅損失
- 同じパラメータでもPF 0.67〜0.88（全ペア赤字）

### Axiory（参考）
- スプレッドが狭く好成績だが、KIWAMI向けに最適化したため未使用
- シンボル名に `#` なし（USDJPY, EURUSDなど）

---

## 8. バックテスト成績まとめ

### 全体（GOLD除く7ペア合計）
- 合計利益: +371,421 JPY（+371%）
- 合計取引: 3,032回（約6.7回/日）
- 平均PF: 1.13
- 最大DD: 22.7%（GBPUSD#が最悪）

### GOLDを含む全8ペア
- 合計取引: 6,690回（約14.9回/日）
- 全ペア黒字（PF 1.0以上）

### 重要な注意
- バックテストは**複利運用**（残高増加に伴いロット増加）
- 金額は複利効果を含むため参考値。特にGOLDは利益額が天文学的数字になるが、PF/DDの方が重要
- バックテスト ≠ 実運用。スリッページ・スプレッド拡大・約定拒否等の影響は含まれていない

---

## 9. よくある質問（FAQ）

### Q: 1日何回くらいトレードしますか？
A: 全8ペア合計で約15回/日（GOLD 8回 + 他7ペア合計7回）

### Q: 勝率が低いペア（USDJPY 28%等）があるが大丈夫か？
A: SLが狭くTPが広い設定なので勝率は低いが、1勝の利益が大きい。PF（プロフィットファクター）が1.0以上なら黒字

### Q: どのチャートに貼ればいいですか？
A: どのチャートでもOK。EAはOnTimer()で全ペアを巡回するため、チャートの通貨ペアと時間足は無関係

### Q: EA再起動するとデータがリセットされますか？
A: WarmUp機能で過去100本の足を自動スキャンするため、即座にトレード可能状態になる

### Q: KIWAMI口座以外で使えますか？
A: スタンダード口座では全ペア赤字。KIWAMI口座のスプレッドを前提に最適化しているため、必ずKIWAMI口座で使用すること

### Q: ロットサイズが異常に大きくなることはありますか？
A: 安全策として最大5ロットの上限を設けている。また、OrderCalcProfit()による正確な通貨変換を使用。過去にGOLDで29ロットのバグがあったが修正済み

### Q: VPSが落ちたらどうなりますか？
A: EAが停止するためトレードは行われない。オープンポジションはSL/TPが設定済みなので自動決済される。VPS復旧後にEAを再起動すればWarmUpで即復帰

### Q: Discord通知が来ない場合は？
A: MT5のオプション → エキスパートアドバイザ → WebRequest許可URLに `https://discord.com` が追加されているか確認。エキスパートタブに「Webhook failed: HTTP -1」が出ている場合はこれが原因

### Q: 特定のペアだけ除外したい場合は？
A: InpSymbolsと各パラメータ文字列から該当ペアのカンマ区切り項目を削除する。例: GOLD#を除外するなら各パラメータの末尾のカンマ以降を削除

### Q: 複利と単利どちらですか？
A: 複利。InpRiskPercent=1.0は「残高の1%をリスクにする」設定。残高が増えるとロットも自動で増える

### Q: バックテストの利益額が現実的でない（特にGOLD）のはなぜ？
A: 複利運用のため、後半になるとロットが巨大化し利益額が指数関数的に増加する。実運用ではこのような結果にはならない。PFとDDの方が戦略の実力を正しく示す

### Q: InpTradeEnabled=falseにすると何が起きますか？
A: トレードは行わずDiscord通知のみ配信される。シグナル配信専用モード

### Q: Magic番号はどうなっていますか？
A: MagicBase(106) + ペアのindex。USDJPY#=106, EURUSD#=107, GBPUSD#=108, AUDUSD#=109, GBPJPY#=110, EURJPY#=111, AUDJPY#=112, GOLD#=113

### Q: Market WatchにUSJDPY#が必要な理由は？
A: GOLD#の利益計算にUSD→JPY変換が必要。OrderCalcProfit()がUSJDPY#のレートを参照するため

---

## 10. 用語集

| 用語 | 意味 |
|------|------|
| SMC | Smart Money Concepts。大口投資家の動きを分析する手法 |
| BOS | Break of Structure。相場の構造転換（トレンドが変わった瞬間） |
| FVG | Fair Value Gap。価格の隙間（大口の注文痕跡） |
| ATR | Average True Range。一定期間の平均的な値動き幅 |
| ADR | Average Daily Range。1日の平均値幅 |
| PF | Profit Factor。総利益÷総損失。1.0以上で黒字 |
| DD | Drawdown。資産の最大減少率 |
| BE | Breakeven。エントリー価格での決済（損益ゼロ） |
| TP1/TP2 | Take Profit 1/2。利確目標の第1/第2段階 |
| SL | Stop Loss。損切り価格 |
| WarmUp | EA起動時に過去データをスキャンして即トレード可能にする機能 |
| KIWAMI | XMの低スプレッド口座タイプ |
| Swing High/Low | チャート上の山の頂点/谷の底 |
| Magic Number | EAがトレードを識別するための固有番号 |
| Lot | 取引量の単位。1 lot = 100,000通貨（GOLDは100オンス） |
| pip | 価格変動の最小単位。FXでは0.0001（JPYペアは0.01） |

---

## 11. ファイル構成

```
okisignal/
├── ea/
│   ├── SMC_FVG_Standalone.mq5  ← 本番用（単一ファイル、VPSに設置）
│   ├── SMC_FVG_Multi.mq5       ← マルチペアEA（include必要）
│   └── SMC_FVG.mq5             ← 単一ペアEA（バックテスト用）
├── include/                     ← 共有ライブラリ
│   ├── CommonDefs.mqh
│   ├── ATRUtils.mqh
│   ├── DiscordWebhook.mqh
│   └── SignalFormat.mqh
├── dashboard/
│   └── app.py                   ← Streamlitダッシュボード
├── results/
│   ├── trades_ALL.csv           ← 全ペア統合トレード履歴
│   └── trades_[PAIR].csv        ← ペア別トレード履歴
├── optimizer/                   ← バックテスト・最適化スクリプト
├── docs/
│   ├── knowledge_base.md        ← このファイル
│   ├── strategy_guide.md        ← 運営者向けガイド
│   └── backtest_report.md       ← バックテスト詳細レポート
└── deploy/
    └── SMC_FVG_Standalone.mq5   ← VPSデプロイ用コピー
```

---

## 12. 更新履歴

| 日付 | 内容 |
|------|------|
| 2026-04-09 | EA初版作成（Structure Break + FVG） |
| 2026-04-09 | セッションフィルター追加、全8ペア最適化完了 |
| 2026-04-09 | マルチペアEA（SMC_FVG_Multi）作成 |
| 2026-04-09 | スタンドアロン版作成（外部include不要） |
| 2026-04-09 | WarmUp機能追加（起動時即初期化） |
| 2026-04-09 | VPSデプロイ開始（XM KIWAMI デモ） |
| 2026-04-10 | Streamlitダッシュボード作成 |
| 2026-04-12 | GOLDロットバグ修正（OrderCalcProfit方式に変更） |
| 2026-04-12 | 5ロット上限の安全策追加 |
