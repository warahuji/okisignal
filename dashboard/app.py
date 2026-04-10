import streamlit as st
import pandas as pd
import plotly.graph_objects as go
import plotly.express as px
import os

st.set_page_config(page_title="SMC_FVG Dashboard", page_icon="📊", layout="wide")

def check_password():
    """Simple password protection."""
    if "authenticated" not in st.session_state:
        st.session_state.authenticated = False
    if st.session_state.authenticated:
        return True
    password = st.text_input("パスワードを入力してください", type="password")
    if password == st.secrets.get("password", "okisignal2026"):
        st.session_state.authenticated = True
        st.rerun()
    elif password:
        st.error("パスワードが違います")
    return False

RESULTS_DIR = os.path.join(os.path.dirname(__file__), "..", "results")

@st.cache_data(ttl=300)
def load_trades():
    path = os.path.join(RESULTS_DIR, "trades_ALL.csv")
    if not os.path.exists(path):
        return pd.DataFrame()
    df = pd.read_csv(path)
    df["EntryTime"] = pd.to_datetime(df["EntryTime"], format="%Y.%m.%d %H:%M:%S")
    df["ExitTime"] = pd.to_datetime(df["ExitTime"], format="%Y.%m.%d %H:%M:%S")
    df["ProfitJPY"] = pd.to_numeric(df["ProfitJPY"], errors="coerce").fillna(0).astype(int)
    df["Balance"] = pd.to_numeric(df["Balance"], errors="coerce").fillna(0)
    df["Volume"] = pd.to_numeric(df["Volume"], errors="coerce").fillna(0)
    return df


def render_header():
    st.title("📊 SMC_FVG シグナル配信ダッシュボード")
    st.caption("Structure Break + Fair Value Gap | XM KIWAMI | バックテスト 2025.01 - 2026.04")


def render_summary(df):
    st.header("📈 全体サマリー")
    total_trades = len(df)
    wins = len(df[df["ProfitJPY"] > 0])
    losses = len(df[df["ProfitJPY"] < 0])
    winrate = wins / total_trades * 100 if total_trades > 0 else 0
    gross_p = df[df["ProfitJPY"] > 0]["ProfitJPY"].sum()
    gross_l = abs(df[df["ProfitJPY"] < 0]["ProfitJPY"].sum())
    pf = gross_p / gross_l if gross_l > 0 else 0
    pairs = df["Symbol"].nunique()

    c1, c2, c3, c4 = st.columns(4)
    c1.metric("取引数", f"{total_trades:,}")
    c2.metric("勝率", f"{winrate:.1f}%")
    c3.metric("PF（利益÷損失）", f"{pf:.2f}")
    c4.metric("通貨ペア数", f"{pairs}")

    st.info("💡 **PF（プロフィットファクター）** = 総利益 ÷ 総損失。1.0より大きければ黒字。全ペア1.0以上です。")
    st.warning("⚠️ これは**複利運用**（残高が増えるとロットも増える）のバックテスト結果です。金額は参考値としてご覧ください。")


def render_pair_table(df):
    st.header("💱 通貨ペア別パフォーマンス")

    pair_stats = []
    for sym in sorted(df["Symbol"].unique()):
        sdf = df[df["Symbol"] == sym]
        trades = len(sdf)
        w = len(sdf[sdf["ProfitJPY"] > 0])
        l = len(sdf[sdf["ProfitJPY"] < 0])
        wr = w / trades * 100 if trades > 0 else 0
        gross_p = sdf[sdf["ProfitJPY"] > 0]["ProfitJPY"].sum()
        gross_l = abs(sdf[sdf["ProfitJPY"] < 0]["ProfitJPY"].sum())
        pf = gross_p / gross_l if gross_l > 0 else 0
        tp_count = len(sdf[sdf["Result"] == "TP"])
        sl_count = len(sdf[sdf["Result"] == "SL"])
        per_day = trades / 450
        pair_stats.append({
            "通貨ペア": sym,
            "取引数": trades,
            "1日平均": f"{per_day:.1f}回",
            "勝/敗": f"{w}W / {l}L",
            "勝率": f"{wr:.1f}%",
            "PF": f"{pf:.2f}",
            "TP決済": tp_count,
            "SL決済": sl_count,
        })

    st.dataframe(
        pd.DataFrame(pair_stats),
        use_container_width=True,
        hide_index=True,
    )


def render_equity_curve(df):
    st.header("📉 エクイティカーブ（資産推移）")

    tab1, tab2 = st.tabs(["全ペア統合", "ペア別"])

    with tab1:
        df_sorted = df.sort_values("ExitTime")
        df_sorted["CumPnL"] = df_sorted["ProfitJPY"].cumsum()
        fig = go.Figure()
        fig.add_trace(go.Scatter(
            x=df_sorted["ExitTime"],
            y=df_sorted["CumPnL"],
            mode="lines",
            name="累積損益",
            line=dict(color="#2ECC71", width=2),
            fill="tozeroy",
            fillcolor="rgba(46,204,113,0.1)",
        ))
        fig.update_layout(
            yaxis_title="累積損益 (JPY)",
            xaxis_title="",
            template="plotly_dark",
            height=400,
        )
        st.plotly_chart(fig, use_container_width=True)

    with tab2:
        symbols = sorted(df["Symbol"].unique())
        fig = go.Figure()
        colors = px.colors.qualitative.Set2
        for i, sym in enumerate(symbols):
            sdf = df[df["Symbol"] == sym].sort_values("ExitTime")
            sdf["CumPnL"] = sdf["ProfitJPY"].cumsum()
            fig.add_trace(go.Scatter(
                x=sdf["ExitTime"],
                y=sdf["CumPnL"],
                mode="lines",
                name=sym,
                line=dict(color=colors[i % len(colors)], width=1.5),
            ))
        fig.update_layout(
            yaxis_title="累積損益 (JPY)",
            xaxis_title="",
            template="plotly_dark",
            height=400,
            legend=dict(orientation="h", y=-0.15),
        )
        st.plotly_chart(fig, use_container_width=True)


def render_monthly(df):
    st.header("📅 月別損益")
    df_m = df.copy()
    df_m["Month"] = df_m["ExitTime"].dt.to_period("M").astype(str)
    monthly = df_m.groupby("Month")["ProfitJPY"].agg(["sum", "count"]).reset_index()
    monthly.columns = ["月", "損益", "取引数"]

    fig = go.Figure()
    colors = ["#2ECC71" if v >= 0 else "#E74C3C" for v in monthly["損益"]]
    fig.add_trace(go.Bar(
        x=monthly["月"],
        y=monthly["損益"],
        marker_color=colors,
        text=[f"¥{v:+,.0f}" for v in monthly["損益"]],
        textposition="outside",
    ))
    fig.update_layout(
        yaxis_title="損益 (JPY)",
        template="plotly_dark",
        height=350,
    )
    st.plotly_chart(fig, use_container_width=True)


def render_winloss(df):
    st.header("🎯 勝敗分布")
    c1, c2 = st.columns(2)

    with c1:
        result_counts = df["Result"].value_counts()
        fig = go.Figure(data=[go.Pie(
            labels=result_counts.index,
            values=result_counts.values,
            marker_colors=["#2ECC71", "#E74C3C", "#3498DB"],
            hole=0.4,
        )])
        fig.update_layout(
            title="決済理由（TP=利確 / SL=損切り）",
            template="plotly_dark",
            height=300,
        )
        st.plotly_chart(fig, use_container_width=True)

    with c2:
        fig = go.Figure()
        fig.add_trace(go.Histogram(
            x=df[df["ProfitJPY"].abs() < 100000]["ProfitJPY"],
            nbinsx=50,
            marker_color="#3498DB",
        ))
        fig.update_layout(
            title="1トレードあたりの損益分布",
            xaxis_title="損益 (JPY)",
            yaxis_title="件数",
            template="plotly_dark",
            height=300,
        )
        st.plotly_chart(fig, use_container_width=True)


def render_strategy():
    st.header("📖 トレード手法のしくみ")
    st.markdown("""
### どうやってエントリーポイントを見つけるの？

この手法は**3つのステップ**で「ここで買う（売る）」を判断します。

---

#### ステップ1: 相場の「山」と「谷」を見つける

チャートの中で、**一番高い場所（山のてっぺん）** と **一番低い場所（谷の底）** を自動で検出します。
これが相場の「現在の範囲」を示します。

---

#### ステップ2: 「壁を突き破った！」を検知する（= トレンド転換）

価格が **山のてっぺんを上に突き抜けたら → 上昇トレンド開始** と判断。
逆に **谷の底を下に突き抜けたら → 下降トレンド開始** と判断。

これを「**ブレイク・オブ・ストラクチャー（BOS）**」と呼びます。
つまり「相場の流れが変わった瞬間」を捉えます。

---

#### ステップ3: 「押し目」で乗る（= FVGエントリー）

トレンドが変わった後、価格が**一気に動いた場所**にできる「**すき間**」を探します。

例えば急上昇した後、チャートの足と足の間に**価格が飛んでいる部分**（= すき間）があります。
この部分を「**フェアバリューギャップ（FVG）**」と言います。

**価格がこの「すき間」に戻ってきたタイミングでエントリー！**

なぜ？ → 大口の投資家（銀行など）が急いで大量注文した痕跡なので、
もう一度同じ場所に来ると、残りの注文が入って再び同じ方向に動きやすいからです。

---

### エントリー後の管理

| 段階 | やること |
|------|---------|
| ① エントリー | 損切り（SL）と利確目標（TP）を自動で設定 |
| ② 第1目標に到達 | **半分を利確**して利益を確保 |
| ③ 損切りを移動 | SLをエントリー価格に移動 → **損失ゼロを保証** |
| ④ 第2目標を狙う | 残り半分でさらに大きな利益を狙う |

---

### 安全のためのフィルター

- **時間帯フィルター**: 各通貨ペアが最も動きやすい時間帯だけトレード
- **値幅フィルター**: その日すでに大きく動いた場合はトレードしない（反転リスク回避）
- **1ペア1ポジション**: 同じ通貨ペアでは1つしかポジションを持たない
""")


def render_trades(df):
    st.header("📋 全トレード履歴")
    c1, c2 = st.columns(2)
    with c1:
        sym_filter = st.multiselect("通貨ペア", sorted(df["Symbol"].unique()), default=sorted(df["Symbol"].unique()))
    with c2:
        result_filter = st.multiselect("結果", ["TP", "SL", "Other"], default=["TP", "SL", "Other"])

    filtered = df[(df["Symbol"].isin(sym_filter)) & (df["Result"].isin(result_filter))]
    filtered_display = filtered[["EntryTime", "ExitTime", "Symbol", "Direction", "Volume",
                                  "EntryPrice", "ExitPrice", "Result", "ProfitJPY", "Duration"]].copy()
    filtered_display.columns = ["エントリー", "決済", "通貨ペア", "方向", "ロット",
                                 "エントリー価格", "決済価格", "結果", "損益(JPY)", "保有時間"]
    filtered_display = filtered_display.sort_values("エントリー", ascending=False)

    st.dataframe(
        filtered_display,
        use_container_width=True,
        hide_index=True,
        height=400,
    )
    st.caption(f"表示: {len(filtered_display):,} / {len(df):,} 件")


def main():
    if not check_password():
        return
    render_header()
    df = load_trades()

    if df.empty:
        st.error("トレードデータが見つかりません。results/trades_ALL.csv を確認してください。")
        return

    render_summary(df)
    st.divider()
    render_pair_table(df)
    st.divider()
    render_equity_curve(df)
    st.divider()
    render_monthly(df)
    st.divider()
    render_winloss(df)
    st.divider()
    render_strategy()
    st.divider()
    render_trades(df)

    st.divider()
    st.caption("SMC_FVG Signal System | Backtest: 2025.01 - 2026.04 | XM KIWAMI Demo")


if __name__ == "__main__":
    main()
