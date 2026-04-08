"""
OkiSignal Auto Optimizer
========================
5 strategies x 8 pairs = 40 optimizations, fully automated.

Usage:
    python run_optimizer.py          # Run all
    python run_optimizer.py --ea EMA_ADR --symbol USDJPY  # Run specific
    python run_optimizer.py --report  # Analyze existing results only
"""

import os
import sys
import time
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path
from datetime import datetime
import argparse
import json

# === Configuration ===
MT5_TERMINAL = r"D:\xm\terminal64.exe"
MT5_DATA_DIR = r"C:\Users\daisuke\AppData\Roaming\MetaQuotes\Terminal\CDB671518263228BAF394C193A24CAB5"
MQL5_DIR = os.path.join(MT5_DATA_DIR, "MQL5")
TESTER_DIR = os.path.join(MT5_DATA_DIR, "Tester")

RESULTS_DIR = r"D:\claudecode\okisignal\optimizer\results"
CONFIG_DIR = r"D:\claudecode\okisignal\optimizer\configs"

# Test period
FROM_DATE = "2024.01.01"
TO_DATE = "2026.04.01"
DEPOSIT = 100000
CURRENCY = "JPY"
LEVERAGE = 1000

# Strategies and their optimization parameters
STRATEGIES = {
    "EMA_ADR": {
        "magic": 104,
        "params": {
            "InpFastEMA":      {"value": 20, "start": 10, "step": 5,    "stop": 30,  "optimize": True},
            "InpSlowEMA":      {"value": 50, "start": 40, "step": 10,   "stop": 100, "optimize": True},
            "InpADRPeriod":    {"value": 14, "optimize": False},
            "InpADRThreshold": {"value": 70, "start": 50, "step": 10,   "stop": 80,  "optimize": True},
            "InpEMASpacingMult":{"value": 0.1,"start": 0.05,"step": 0.05,"stop": 0.3,"optimize": False},
            "InpRiskPercent":  {"value": 1.0, "optimize": False},
            "InpATRPeriod":    {"value": 14, "optimize": False},
            "InpSLMult":       {"value": 1.5, "start": 0.75,"step": 0.25,"stop": 2.5, "optimize": True},
            "InpTP1Mult":      {"value": 1.0, "start": 0.5, "step": 0.25,"stop": 2.0, "optimize": True},
            "InpTP2Mult":      {"value": 2.0, "start": 1.5, "step": 0.5, "stop": 4.0, "optimize": True},
            "InpTP1ClosePct":  {"value": 50.0, "optimize": False},
            "InpMagic":        {"value": 104, "optimize": False},
            "InpTradeComment": {"value": "OkiEMA", "type": "string", "optimize": False},
        }
    },
    "SessionBreakout": {
        "magic": 101,
        "params": {
            "InpLondonHour":     {"value": 10, "start": 9,   "step": 1,   "stop": 11,  "optimize": True},
            "InpNYHour":         {"value": 16, "start": 15,  "step": 1,   "stop": 17,  "optimize": True},
            "InpRangeMinutes":   {"value": 60, "optimize": False},
            "InpBreakoutBuffer": {"value": 2.0, "optimize": False},
            "InpMaxRangeATRMult":{"value": 1.5, "start": 1.0,"step": 0.25,"stop": 2.5, "optimize": True},
            "InpExpiryBars":     {"value": 8,   "start": 4,  "step": 2,   "stop": 12,  "optimize": True},
            "InpRiskPercent":    {"value": 1.0, "optimize": False},
            "InpATRPeriod":      {"value": 14, "optimize": False},
            "InpSLMult":         {"value": 1.5, "start": 0.75,"step": 0.25,"stop": 2.5, "optimize": True},
            "InpTP1Mult":        {"value": 1.0, "start": 0.5, "step": 0.25,"stop": 2.0, "optimize": True},
            "InpTP2Mult":        {"value": 2.0, "start": 1.5, "step": 0.5, "stop": 4.0, "optimize": True},
            "InpTP1ClosePct":    {"value": 50.0, "optimize": False},
            "InpMagic":          {"value": 101, "optimize": False},
            "InpTradeComment":   {"value": "OkiSB", "type": "string", "optimize": False},
        }
    },
    "MTFStructure": {
        "magic": 102,
        "params": {
            "InpH4EMAPeriod":  {"value": 50, "start": 30,  "step": 10,  "stop": 100, "optimize": True},
            "InpSwingBars":    {"value": 5,  "start": 3,   "step": 1,   "stop": 8,   "optimize": True},
            "InpMaxSwingAge":  {"value": 50, "optimize": False},
            "InpRiskPercent":  {"value": 1.0, "optimize": False},
            "InpATRPeriod":    {"value": 14, "optimize": False},
            "InpSLMult":       {"value": 1.5, "start": 0.75,"step": 0.25,"stop": 2.5, "optimize": True},
            "InpTP1Mult":      {"value": 1.0, "start": 0.5, "step": 0.25,"stop": 2.0, "optimize": True},
            "InpTP2Mult":      {"value": 2.0, "start": 1.5, "step": 0.5, "stop": 4.0, "optimize": True},
            "InpTP1ClosePct":  {"value": 50.0, "optimize": False},
            "InpMagic":        {"value": 102, "optimize": False},
            "InpTradeComment": {"value": "OkiMTF", "type": "string", "optimize": False},
        }
    },
    "RSIDivergence": {
        "magic": 103,
        "params": {
            "InpRSIPeriod":     {"value": 14, "start": 10, "step": 2,   "stop": 21,  "optimize": True},
            "InpRSIOverbought": {"value": 70, "start": 65, "step": 5,   "stop": 80,  "optimize": True},
            "InpRSIOversold":   {"value": 30, "start": 20, "step": 5,   "stop": 35,  "optimize": True},
            "InpSRLookback":    {"value": 100, "optimize": False},
            "InpSRMinTouches":  {"value": 2, "optimize": False},
            "InpSRZoneATRMult": {"value": 0.5, "optimize": False},
            "InpDivLookback":   {"value": 20, "start": 15, "step": 5,   "stop": 30,  "optimize": False},
            "InpSwingBars":     {"value": 3, "optimize": False},
            "InpRiskPercent":   {"value": 1.0, "optimize": False},
            "InpATRPeriod":     {"value": 14, "optimize": False},
            "InpSLMult":        {"value": 1.5, "start": 0.75,"step": 0.25,"stop": 2.5, "optimize": True},
            "InpTP1Mult":       {"value": 1.0, "start": 0.5, "step": 0.25,"stop": 2.0, "optimize": True},
            "InpTP2Mult":       {"value": 2.0, "start": 1.5, "step": 0.5, "stop": 4.0, "optimize": True},
            "InpTP1ClosePct":   {"value": 50.0, "optimize": False},
            "InpMagic":         {"value": 103, "optimize": False},
            "InpTradeComment":  {"value": "OkiRSI", "type": "string", "optimize": False},
        }
    },
    "OBRetest": {
        "magic": 105,
        "params": {
            "InpImpulseATRMult":{"value": 1.5, "start": 1.0,"step": 0.25,"stop": 2.5, "optimize": True},
            "InpMaxRetestBars": {"value": 20, "start": 10, "step": 5,   "stop": 40,  "optimize": True},
            "InpOBBodyPct":     {"value": 50, "optimize": False},
            "InpMaxActiveOBs":  {"value": 3, "optimize": False},
            "InpRiskPercent":   {"value": 1.0, "optimize": False},
            "InpATRPeriod":     {"value": 14, "optimize": False},
            "InpSLMult":        {"value": 1.5, "start": 0.75,"step": 0.25,"stop": 2.5, "optimize": True},
            "InpTP1Mult":       {"value": 1.0, "start": 0.5, "step": 0.25,"stop": 2.0, "optimize": True},
            "InpTP2Mult":       {"value": 2.0, "start": 1.5, "step": 0.5, "stop": 4.0, "optimize": True},
            "InpTP1ClosePct":   {"value": 50.0, "optimize": False},
            "InpMagic":         {"value": 105, "optimize": False},
            "InpTradeComment":  {"value": "OkiOB", "type": "string", "optimize": False},
        }
    },
}

SYMBOLS = ["USDJPY", "EURUSD", "GBPUSD", "AUDUSD", "GBPJPY", "EURJPY", "AUDJPY", "XAUUSD"]


def generate_set_file(ea_name, params, symbol):
    """Generate .set file for MT5 optimization parameters."""
    set_dir = os.path.join(MQL5_DIR, "Profiles", "Tester")
    os.makedirs(set_dir, exist_ok=True)

    set_path = os.path.join(set_dir, f"OkiSignal\\{ea_name}.set")
    os.makedirs(os.path.dirname(set_path), exist_ok=True)

    lines = []
    for name, cfg in params.items():
        val = cfg["value"]
        is_string = cfg.get("type") == "string"

        if is_string:
            lines.append(f"{name}={val}")
            lines.append(f"{name},F=0")
        elif cfg.get("optimize", False):
            start = cfg["start"]
            step = cfg["step"]
            stop = cfg["stop"]
            lines.append(f"{name}={val}||{start}||{step}||{stop}||Y")
        else:
            lines.append(f"{name}={val}||{val}||0||{val}||N")

    content = "\n".join(lines) + "\n"

    with open(set_path, "w", encoding="utf-16-le") as f:
        f.write(content)

    return set_path


def generate_ini_file(ea_name, symbol, run_index):
    """Generate .ini config file for MT5 terminal."""
    os.makedirs(CONFIG_DIR, exist_ok=True)
    os.makedirs(RESULTS_DIR, exist_ok=True)

    report_name = f"{ea_name}_{symbol}"
    report_path = os.path.join(RESULTS_DIR, report_name)

    ini_content = f"""[Tester]
Expert=OkiSignal\\{ea_name}
Symbol={symbol}
Period=M15
Optimization=2
Model=0
FromDate={FROM_DATE}
ToDate={TO_DATE}
ForwardMode=0
Deposit={DEPOSIT}
Currency={CURRENCY}
Leverage={LEVERAGE}
ExecutionMode=0
OptimizationCriterion=0
Report={report_path}
ReplaceReport=1
ShutdownTerminal=1
"""

    ini_path = os.path.join(CONFIG_DIR, f"{run_index:03d}_{ea_name}_{symbol}.ini")
    with open(ini_path, "w") as f:
        f.write(ini_content)

    return ini_path, report_path


def run_mt5_optimization(ini_path, ea_name, symbol, timeout=600):
    """Run MT5 with config and wait for completion."""
    print(f"  Starting MT5: {ea_name} x {symbol}...")

    cmd = [MT5_TERMINAL, f"/config:{ini_path}"]
    proc = subprocess.Popen(cmd)

    start_time = time.time()
    while proc.poll() is None:
        elapsed = time.time() - start_time
        if elapsed > timeout:
            print(f"  TIMEOUT after {timeout}s, killing...")
            proc.kill()
            return False
        time.sleep(5)
        mins = int(elapsed // 60)
        secs = int(elapsed % 60)
        print(f"\r  Running... {mins:02d}:{secs:02d}", end="", flush=True)

    elapsed = time.time() - start_time
    print(f"\n  Completed in {elapsed:.0f}s (exit code: {proc.returncode})")
    return True


def parse_xml_results(xml_path):
    """Parse MT5 optimization XML results."""
    if not os.path.exists(xml_path):
        return []

    try:
        tree = ET.parse(xml_path)
    except ET.ParseError:
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


def analyze_all_results():
    """Analyze all optimization results and produce ranking."""
    print("\n" + "=" * 80)
    print("OKISIGNAL OPTIMIZATION RESULTS")
    print("=" * 80)

    all_results = []

    for filename in sorted(os.listdir(RESULTS_DIR)):
        if not filename.endswith(".xml"):
            continue

        parts = filename.replace(".xml", "").split("_", 1)
        if len(parts) < 2:
            continue

        ea_name = parts[0]
        symbol = parts[1]
        xml_path = os.path.join(RESULTS_DIR, filename)

        results = parse_xml_results(xml_path)
        if not results:
            print(f"\n[{ea_name} x {symbol}] No results")
            continue

        # Sort by profit
        results.sort(key=lambda x: x.get("Profit", 0), reverse=True)
        best = results[0]
        profitable = sum(1 for r in results if r.get("Profit", 0) > 0)

        profit = best.get("Profit", 0)
        pf = best.get("Profit Factor", 0)
        dd = best.get("Equity DD %", 0)
        trades = int(best.get("Trades", 0))
        sharpe = best.get("Sharpe Ratio", 0)

        # Collect optimized param values
        param_vals = {}
        for k, v in best.items():
            if k.startswith("Inp"):
                param_vals[k] = v

        all_results.append({
            "ea": ea_name,
            "symbol": symbol,
            "profit": profit,
            "pf": pf,
            "dd": dd,
            "trades": trades,
            "sharpe": sharpe,
            "profitable_count": profitable,
            "total_count": len(results),
            "params": param_vals,
        })

        status = "PROFITABLE" if profit > 0 else "LOSS"
        print(f"\n[{ea_name} x {symbol}] {status}")
        print(f"  Best: Profit={profit:.0f} PF={pf:.2f} DD={dd:.1f}% Trades={trades} Sharpe={sharpe:.2f}")
        print(f"  Profitable: {profitable}/{len(results)} combinations")
        print(f"  Params: {param_vals}")

    # Overall ranking
    all_results.sort(key=lambda x: x["profit"], reverse=True)

    print("\n" + "=" * 80)
    print("OVERALL RANKING (Top 20)")
    print("=" * 80)
    print(f"{'Rank':>4} {'EA':<18} {'Symbol':<8} {'Profit':>9} {'PF':>6} {'DD%':>6} {'Trades':>6} {'Win%':>8}")
    print("-" * 80)

    for i, r in enumerate(all_results[:20]):
        print(f"{i+1:4d} {r['ea']:<18} {r['symbol']:<8} {r['profit']:9.0f} {r['pf']:6.2f} {r['dd']:6.1f} {r['trades']:6d} {r['profitable_count']:4d}/{r['total_count']:<4d}")

    # Save summary JSON
    summary_path = os.path.join(RESULTS_DIR, "_summary.json")
    with open(summary_path, "w") as f:
        json.dump(all_results, f, indent=2, default=str)
    print(f"\nSummary saved to: {summary_path}")

    # Identify winners
    winners = [r for r in all_results if r["profit"] > 0 and r["pf"] > 1.2 and r["trades"] >= 20]
    if winners:
        print(f"\n{'='*80}")
        print(f"WINNERS (Profit>0, PF>1.2, Trades>=20): {len(winners)}")
        print(f"{'='*80}")
        for w in winners:
            print(f"  {w['ea']} x {w['symbol']}: Profit={w['profit']:.0f} PF={w['pf']:.2f} Trades={w['trades']}")
            print(f"    Params: {w['params']}")
    else:
        print("\nNo winning combinations found. Consider revising strategy logic.")

    return all_results


def main():
    parser = argparse.ArgumentParser(description="OkiSignal Auto Optimizer")
    parser.add_argument("--ea", type=str, help="Run specific EA only")
    parser.add_argument("--symbol", type=str, help="Run specific symbol only")
    parser.add_argument("--report", action="store_true", help="Analyze existing results only")
    parser.add_argument("--timeout", type=int, default=600, help="Timeout per run (seconds)")
    args = parser.parse_args()

    if args.report:
        analyze_all_results()
        return

    # Filter strategies and symbols
    eas = [args.ea] if args.ea else list(STRATEGIES.keys())
    symbols = [args.symbol] if args.symbol else SYMBOLS

    total_runs = len(eas) * len(symbols)
    print(f"OkiSignal Auto Optimizer")
    print(f"Strategies: {eas}")
    print(f"Symbols: {symbols}")
    print(f"Total runs: {total_runs}")
    print(f"Timeout per run: {args.timeout}s")
    print(f"Start: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 60)

    run_index = 0
    completed = 0
    failed = 0

    for ea_name in eas:
        if ea_name not in STRATEGIES:
            print(f"Unknown strategy: {ea_name}")
            continue

        strategy = STRATEGIES[ea_name]

        for symbol in symbols:
            run_index += 1
            print(f"\n[{run_index}/{total_runs}] {ea_name} x {symbol}")
            print("-" * 40)

            # Generate .set file
            generate_set_file(ea_name, strategy["params"], symbol)

            # Generate .ini file
            ini_path, report_path = generate_ini_file(ea_name, symbol, run_index)

            # Run optimization
            success = run_mt5_optimization(ini_path, ea_name, symbol, args.timeout)

            if success:
                xml_file = report_path + ".xml"
                if os.path.exists(xml_file):
                    results = parse_xml_results(xml_file)
                    profitable = sum(1 for r in results if r.get("Profit", 0) > 0)
                    print(f"  Results: {len(results)} combinations, {profitable} profitable")
                    completed += 1
                else:
                    print(f"  WARNING: Result file not found: {xml_file}")
                    failed += 1
            else:
                failed += 1

            # Brief pause between runs
            time.sleep(3)

    print(f"\n{'='*60}")
    print(f"DONE: {completed} completed, {failed} failed")
    print(f"End: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    # Analyze all results
    analyze_all_results()


if __name__ == "__main__":
    main()
