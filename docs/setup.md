# OkiSignal セットアップ手順

## 1. MT5にファイルを配置

```
MT5データフォルダ/
├── MQL5/Experts/OkiSignal/
│   ├── EMA_ADR.mq5
│   ├── SessionBreakout.mq5
│   ├── MTFStructure.mq5
│   ├── OBRetest.mq5
│   ├── RSIDivergence.mq5
│   └── OkiLogger.mq5
├── MQL5/Include/OkiSignal/
│   ├── CommonDefs.mqh
│   ├── ATRUtils.mqh
│   ├── DiscordWebhook.mqh
│   ├── SignalFormat.mqh
│   ├── SheetsLogger.mqh
│   └── ReportGenerator.mqh
```

MT5データフォルダ: ファイル > データフォルダを開く

## 2. コンパイル

MetaEditorで各.mq5ファイルを開いてコンパイル（F7）。
includeフォルダのパスが正しいことを確認。

## 3. WebRequest許可

ツール > オプション > エキスパートアドバイザー:
- [x] DLLの使用を許可する
- [x] 以下のURLへのWebRequestを許可する:
  - `https://discord.com`
  - `https://script.google.com`

## 4. Discord Webhook作成

1. Discordサーバーで配信チャンネルを作成
2. チャンネル設定 > 連携サービス > ウェブフック > 新しいウェブフック
3. URLをコピー（OkiLoggerの入力パラメータに設定）
4. 必要に応じてレポート用の別チャンネル+Webhookも作成

## 5. Google Sheets設定

1. 新しいGoogleスプレッドシートを作成
2. 拡張機能 > Apps Script
3. `apps-script/Code.gs` の内容を貼り付け
4. デプロイ > 新しいデプロイ > ウェブアプリ
   - 実行者: 自分
   - アクセス: 全員
5. デプロイURLをコピー（OkiLoggerの入力パラメータに設定）

## 6. EA配置（バックテスト）

各戦略EAを個別にテスト:
1. ストラテジーテスター（Ctrl+R）
2. 設定:
   - モデル: すべてのティック（実ティック基準）
   - 期間: M15
   - 日付: 2024.01.01 〜 2026.04.01
   - 初期証拠金: $10,000
   - 遅延: ランダム遅延
3. 8ペアそれぞれで実行

## 7. EA配置（ライブ/デモ）

### 戦略EA（各ペアのM15チャートに1つずつ）
- USDJPY M15 → EMA_ADR, SessionBreakout, MTFStructure, OBRetest, RSIDivergence
- 各EAは同一チャートに複数配置不可 → チャートを分けるか、1チャート1EA

### OkiLogger（任意の1チャートに配置）
- 入力パラメータにWebhook URLを設定
- 全ペア・全戦略のトレードを自動監視

## Magic番号一覧

| EA | Magic |
|----|-------|
| SessionBreakout | 101 |
| MTFStructure | 102 |
| RSIDivergence | 103 |
| EMA_ADR | 104 |
| OBRetest | 105 |
| OkiLogger | 999 |
