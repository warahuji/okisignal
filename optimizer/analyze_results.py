"""
OkiSignal Results Analyzer
===========================
MT5で手動最適化した結果XMLを自動解析してランキング化。

使い方:
1. MT5で最適化を実行
2. 結果タブ右クリック → XMLでエクスポート → D:\claudecode\okisignal\optimizer\results\ に保存
   ファイル名規則: {EA名}_{通貨ペア}.xml  (例: EMA_ADR_USDJPY.xml)
3. python analyze_results.py を実行

または:
  python analyze_results.py --watch   # resultsフォルダを監視、新ファイル追加で自動解析
  python analyze_results.py --file C:\path\to\report.xml  # 単一ファイル解析
"""

import os
import sys
import time
import xml.etree.ElementTree as ET
import json
from pathlib import Path
from datetime import datetime

RESULTS_DIR = r"D:\claudecode\okisignal\optimizer\results"


def parse_optimization_xml(xml_path):
    """Parse MT5 optimization result XML."""
    try:
        tree = ET.parse(xml_path)
    except ET.ParseError as e:
        print(f"  Parse error: {e}")
        return []

    root = tree.getroot()
    ns = {"ss": "urn:schemas-microsoft-com:office:spreadsheet"}
    rows = root.findall(".//ss:Worksheet/ss:Table/ss:Row", ns)

    if len(rows) < 2:
        return []

    # Parse header
    header_cells = rows[0].findall("ss:Cell/ss:Data", ns)
    headers = [c.text for c in header_cells]

    results = []
    for row in rows[1:]:
        cells = row.findall("ss:Cell/ss:Data", ns)
        if len(cells) < len(headers):
            continue
        entry = {}
        for i, h in enumerate(headers):
            try:
                entry[h] = float(cells[i].text)
            except (ValueError, TypeError):
                entry[h] = cells[i].text
        results.append(entry)

    return results


def analyze_single(xml_path, verbose=True):
    """Analyze a single optimization XML file."""
    filename = os.path.basename(xml_path).replace(".xml", "")
    # Known EA names (may contain underscores)
    known_eas = ["EMA_ADR", "SessionBreakout", "MTFStructure", "RSIDivergence", "OBRetest"]

    ea_name = "Unknown"
    symbol = "Unknown"
    for ea in known_eas:
        if filename.startswith(ea + "_"):
            ea_name = ea
            symbol = filename[len(ea) + 1:]
            break

    if ea_name == "Unknown":
        parts = filename.rsplit("_", 1)
        if len(parts) >= 2:
            ea_name = parts[0]
            symbol = parts[1]

    results = parse_optimization_xml(xml_path)
    if not results:
        if verbose:
            print(f"[{ea_name} x {symbol}] No results found")
        return None

    # Sort by profit
    results.sort(key=lambda x: x.get("Profit", 0), reverse=True)

    best = results[0]
    profitable = [r for r in results if r.get("Profit", 0) > 0]
    total = len(results)

    # Extract param values from best result
    param_vals = {}
    for k, v in best.items():
        if k.startswith("Inp"):
            param_vals[k] = v

    summary = {
        "ea": ea_name,
        "symbol": symbol,
        "file": xml_path,
        "total_combinations": total,
        "profitable_count": len(profitable),
        "best": {
            "profit": best.get("Profit", 0),
            "pf": best.get("Profit Factor", 0),
            "dd_pct": best.get("Equity DD %", 0),
            "trades": int(best.get("Trades", 0)),
            "sharpe": best.get("Sharpe Ratio", 0),
            "recovery": best.get("Recovery Factor", 0),
            "expected_payoff": best.get("Expected Payoff", 0),
            "params": param_vals,
        }
    }

    if verbose:
        profit = summary["best"]["profit"]
        status = "PROFITABLE" if profit > 0 else "LOSS"
        print(f"\n[{ea_name} x {symbol}] {status}")
        print(f"  Combinations: {total} total, {len(profitable)} profitable ({len(profitable)/total*100:.0f}%)")
        print(f"  Best: Profit={profit:.0f}  PF={summary['best']['pf']:.2f}  "
              f"DD={summary['best']['dd_pct']:.1f}%  Trades={summary['best']['trades']}  "
              f"Sharpe={summary['best']['sharpe']:.2f}  Recovery={summary['best']['recovery']:.2f}")
        print(f"  Params: ", end="")
        for k, v in param_vals.items():
            print(f"{k}={v}  ", end="")
        print()

        # Top 5
        if len(profitable) > 0:
            print(f"\n  Top 5 profitable:")
            print(f"  {'Profit':>8} {'PF':>6} {'DD%':>6} {'Trades':>6} {'Sharpe':>7} | Params")
            print(f"  {'-'*70}")
            for r in results[:5]:
                p = r.get("Profit", 0)
                if p <= 0:
                    break
                params_str = "  ".join(f"{k}={v}" for k, v in r.items() if k.startswith("Inp"))
                print(f"  {p:8.0f} {r.get('Profit Factor',0):6.2f} "
                      f"{r.get('Equity DD %',0):6.1f} {int(r.get('Trades',0)):6d} "
                      f"{r.get('Sharpe Ratio',0):7.2f} | {params_str}")

    return summary


def analyze_all(results_dir=RESULTS_DIR):
    """Analyze all XML files in results directory."""
    print("=" * 80)
    print(f"OKISIGNAL OPTIMIZATION ANALYSIS -{datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print("=" * 80)

    all_summaries = []

    xml_files = sorted(Path(results_dir).glob("*.xml"))
    if not xml_files:
        print(f"\nNo XML files found in {results_dir}")
        print("Export from MT5: Results tab → Right click → Export to XML")
        return

    for xml_path in xml_files:
        if xml_path.name.startswith("_"):
            continue
        summary = analyze_single(str(xml_path))
        if summary:
            all_summaries.append(summary)

    if not all_summaries:
        return

    # Overall ranking
    all_summaries.sort(key=lambda x: x["best"]["profit"], reverse=True)

    print(f"\n{'='*80}")
    print("OVERALL RANKING")
    print(f"{'='*80}")
    print(f"{'Rank':>4} {'EA':<18} {'Symbol':<8} {'Profit':>9} {'PF':>6} {'DD%':>6} "
          f"{'Trades':>6} {'Sharpe':>7} {'Win':>8}")
    print("-" * 80)

    for i, s in enumerate(all_summaries):
        b = s["best"]
        win_str = f"{s['profitable_count']}/{s['total_combinations']}"
        print(f"{i+1:4d} {s['ea']:<18} {s['symbol']:<8} {b['profit']:9.0f} "
              f"{b['pf']:6.2f} {b['dd_pct']:6.1f} {b['trades']:6d} "
              f"{b['sharpe']:7.2f} {win_str:>8}")

    # Winners
    winners = [s for s in all_summaries
               if s["best"]["profit"] > 0 and s["best"]["pf"] > 1.2 and s["best"]["trades"] >= 20]

    if winners:
        print(f"\n{'='*80}")
        print(f"WINNERS (Profit>0, PF>1.2, Trades>=20): {len(winners)}")
        print(f"{'='*80}")
        for w in winners:
            b = w["best"]
            print(f"\n  {w['ea']} x {w['symbol']}")
            print(f"    Profit={b['profit']:.0f}  PF={b['pf']:.2f}  DD={b['dd_pct']:.1f}%  "
                  f"Trades={b['trades']}  Sharpe={b['sharpe']:.2f}")
            print(f"    Params: ", end="")
            for k, v in b["params"].items():
                print(f"{k}={v}  ", end="")
            print()
    else:
        print("\nNo winning combinations found.")

    # Save JSON summary
    summary_path = os.path.join(results_dir, "_summary.json")
    with open(summary_path, "w") as f:
        json.dump(all_summaries, f, indent=2, default=str)
    print(f"\nJSON summary: {summary_path}")

    return all_summaries


def watch_mode(results_dir=RESULTS_DIR):
    """Watch results directory for new XML files."""
    print(f"Watching {results_dir} for new XML files...")
    print("Press Ctrl+C to stop\n")

    known_files = set(str(p) for p in Path(results_dir).glob("*.xml"))

    while True:
        current_files = set(str(p) for p in Path(results_dir).glob("*.xml"))
        new_files = current_files - known_files

        for f in new_files:
            if os.path.basename(f).startswith("_"):
                continue
            print(f"\nNew file detected: {os.path.basename(f)}")
            analyze_single(f)
            known_files.add(f)

        time.sleep(5)


def main():
    import argparse
    parser = argparse.ArgumentParser(description="OkiSignal Results Analyzer")
    parser.add_argument("--file", type=str, help="Analyze single XML file")
    parser.add_argument("--watch", action="store_true", help="Watch for new files")
    parser.add_argument("--dir", type=str, default=RESULTS_DIR, help="Results directory")
    args = parser.parse_args()

    os.makedirs(args.dir, exist_ok=True)

    if args.file:
        analyze_single(args.file)
    elif args.watch:
        # First analyze existing
        analyze_all(args.dir)
        print()
        watch_mode(args.dir)
    else:
        analyze_all(args.dir)


if __name__ == "__main__":
    main()
