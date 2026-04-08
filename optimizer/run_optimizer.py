"""
OkiSignal Auto Optimizer v2
============================
MT5 Strategy Tester automation via command line.
5 strategies x 8 pairs = 40 optimizations, fully automated.

Usage:
    python run_optimizer.py                                    # Run all
    python run_optimizer.py --ea EMA_ADR --symbol USDJPY       # Run specific
    python run_optimizer.py --report                           # Analyze results only
    python run_optimizer.py --ea EMA_ADR --symbols USDJPY,EURUSD  # Multiple symbols
"""

import os
import sys
import time
import subprocess
import json
from pathlib import Path
from datetime import datetime
import argparse

# === Configuration ===
MT5_TERMINAL = r"D:\xm\terminal64.exe"
MT5_DATA_DIR = r"C:\Users\daisuke\AppData\Roaming\MetaQuotes\Terminal\CDB671518263228BAF394C193A24CAB5"
MQL5_DIR = os.path.join(MT5_DATA_DIR, "MQL5")

RESULTS_DIR = r"D:\claudecode\okisignal\optimizer\results"
CONFIG_DIR = r"D:\claudecode\okisignal\optimizer\configs"

# Test period
FROM_DATE = "2024.01.01"
TO_DATE = "2026.04.01"
DEPOSIT = 100000
CURRENCY = "JPY"
LEVERAGE = "1:1000"

# Strategies and optimization parameters
STRATEGIES = {
    "EMA_ADR": {
        "params": {
            "InpFastEMA":       {"value": 9,   "start": 5,    "step": 2,    "stop": 21,  "optimize": True},
            "InpSlowEMA":       {"value": 21,  "start": 15,   "step": 5,    "stop": 55,  "optimize": True},
            "InpADXPeriod":     {"value": 14,  "optimize": False},
            "InpADXMin":        {"value": 20.0,"start": 15.0, "step": 5.0,  "stop": 30.0,"optimize": True},
            "InpRSIPeriod":     {"value": 14,  "optimize": False},
            "InpRSIBuyMin":     {"value": 50.0,"optimize": False},
            "InpRSISellMax":    {"value": 50.0,"optimize": False},
            "InpADRPeriod":     {"value": 14,  "optimize": False},
            "InpADRThreshold":  {"value": 70.0,"optimize": False},
            "InpStartHour":     {"value": 7,   "optimize": False},
            "InpEndHour":       {"value": 21,  "optimize": False},
            "InpUsePullback":   {"value": "true", "type": "bool", "optimize": False},
            "InpPullbackBars":  {"value": 5,   "start": 3,    "step": 1,    "stop": 8,   "optimize": False},
            "InpRiskPercent":   {"value": 1.0, "optimize": False},
            "InpATRPeriod":     {"value": 14,  "optimize": False},
            "InpSLMult":        {"value": 1.0, "start": 0.5,  "step": 0.25, "stop": 2.0, "optimize": True},
            "InpTP1Mult":       {"value": 1.5, "start": 1.0,  "step": 0.25, "stop": 2.5, "optimize": True},
            "InpTP2Mult":       {"value": 3.0, "start": 2.0,  "step": 0.5,  "stop": 4.0, "optimize": True},
            "InpTP1ClosePct":   {"value": 50.0,"optimize": False},
            "InpMagic":         {"value": 104, "optimize": False},
            "InpTradeComment":  {"value": "OkiEMA", "type": "string", "optimize": False},
        }
    },
    "SessionBreakout": {
        "params": {
            "InpLondonHour":      {"value": 10, "start": 9,    "step": 1,    "stop": 11,  "optimize": True},
            "InpNYHour":          {"value": 16, "start": 15,   "step": 1,    "stop": 17,  "optimize": True},
            "InpRangeMinutes":    {"value": 60, "optimize": False},
            "InpBreakoutBuffer":  {"value": 2.0,"optimize": False},
            "InpMaxRangeATRMult": {"value": 1.5,"start": 1.0,  "step": 0.25, "stop": 2.5, "optimize": True},
            "InpExpiryBars":      {"value": 8,  "start": 4,    "step": 2,    "stop": 12,  "optimize": True},
            "InpRiskPercent":     {"value": 1.0,"optimize": False},
            "InpATRPeriod":       {"value": 14, "optimize": False},
            "InpSLMult":          {"value": 1.5,"start": 0.75, "step": 0.25, "stop": 2.5, "optimize": True},
            "InpTP1Mult":         {"value": 1.0,"start": 0.5,  "step": 0.25, "stop": 2.0, "optimize": True},
            "InpTP2Mult":         {"value": 2.0,"start": 1.5,  "step": 0.5,  "stop": 4.0, "optimize": True},
            "InpTP1ClosePct":     {"value": 50.0,"optimize": False},
            "InpMagic":           {"value": 101,"optimize": False},
            "InpTradeComment":    {"value": "OkiSB", "type": "string", "optimize": False},
        }
    },
    "MTFStructure": {
        "params": {
            "InpH4EMAPeriod":   {"value": 50, "start": 30,  "step": 10,   "stop": 100, "optimize": True},
            "InpSwingBars":     {"value": 5,  "start": 3,   "step": 1,    "stop": 8,   "optimize": True},
            "InpMaxSwingAge":   {"value": 50, "optimize": False},
            "InpRiskPercent":   {"value": 1.0,"optimize": False},
            "InpATRPeriod":     {"value": 14, "optimize": False},
            "InpSLMult":        {"value": 1.5,"start": 0.75, "step": 0.25, "stop": 2.5, "optimize": True},
            "InpTP1Mult":       {"value": 1.0,"start": 0.5,  "step": 0.25, "stop": 2.0, "optimize": True},
            "InpTP2Mult":       {"value": 2.0,"start": 1.5,  "step": 0.5,  "stop": 4.0, "optimize": True},
            "InpTP1ClosePct":   {"value": 50.0,"optimize": False},
            "InpMagic":         {"value": 102,"optimize": False},
            "InpTradeComment":  {"value": "OkiMTF", "type": "string", "optimize": False},
        }
    },
    "RSIDivergence": {
        "params": {
            "InpRSIPeriod":     {"value": 14, "start": 10, "step": 2,    "stop": 21,  "optimize": True},
            "InpRSIOverbought": {"value": 70, "start": 65, "step": 5,    "stop": 80,  "optimize": True},
            "InpRSIOversold":   {"value": 30, "start": 20, "step": 5,    "stop": 35,  "optimize": True},
            "InpSRLookback":    {"value": 100,"optimize": False},
            "InpSRMinTouches":  {"value": 2,  "optimize": False},
            "InpSRZoneATRMult": {"value": 0.5,"optimize": False},
            "InpDivLookback":   {"value": 20, "optimize": False},
            "InpSwingBars":     {"value": 3,  "optimize": False},
            "InpRiskPercent":   {"value": 1.0,"optimize": False},
            "InpATRPeriod":     {"value": 14, "optimize": False},
            "InpSLMult":        {"value": 1.5,"start": 0.75, "step": 0.25, "stop": 2.5, "optimize": True},
            "InpTP1Mult":       {"value": 1.0,"start": 0.5,  "step": 0.25, "stop": 2.0, "optimize": True},
            "InpTP2Mult":       {"value": 2.0,"start": 1.5,  "step": 0.5,  "stop": 4.0, "optimize": True},
            "InpTP1ClosePct":   {"value": 50.0,"optimize": False},
            "InpMagic":         {"value": 103,"optimize": False},
            "InpTradeComment":  {"value": "OkiRSI", "type": "string", "optimize": False},
        }
    },
    "OBRetest": {
        "params": {
            "InpImpulseATRMult":{"value": 1.5,"start": 1.0,  "step": 0.25, "stop": 2.5, "optimize": True},
            "InpMaxRetestBars": {"value": 20, "start": 10,   "step": 5,    "stop": 40,  "optimize": True},
            "InpOBBodyPct":     {"value": 50, "optimize": False},
            "InpMaxActiveOBs":  {"value": 3,  "optimize": False},
            "InpRiskPercent":   {"value": 1.0,"optimize": False},
            "InpATRPeriod":     {"value": 14, "optimize": False},
            "InpSLMult":        {"value": 1.5,"start": 0.75, "step": 0.25, "stop": 2.5, "optimize": True},
            "InpTP1Mult":       {"value": 1.0,"start": 0.5,  "step": 0.25, "stop": 2.0, "optimize": True},
            "InpTP2Mult":       {"value": 2.0,"start": 1.5,  "step": 0.5,  "stop": 4.0, "optimize": True},
            "InpTP1ClosePct":   {"value": 50.0,"optimize": False},
            "InpMagic":         {"value": 105,"optimize": False},
            "InpTradeComment":  {"value": "OkiOB", "type": "string", "optimize": False},
        }
    },
}

SYMBOLS = ["USDJPY", "EURUSD", "GBPUSD", "AUDUSD", "GBPJPY", "EURJPY", "AUDJPY", "XAUUSD"]


def generate_set_file(ea_name, params):
    """Generate .set file for MT5 optimization parameters."""
    # MT5 expects .set file in: MQL5/Profiles/Tester/
    set_dir = os.path.join(MQL5_DIR, "Profiles", "Tester")
    os.makedirs(set_dir, exist_ok=True)

    set_path = os.path.join(set_dir, f"{ea_name}.set")

    lines = []
    for name, cfg in params.items():
        val = cfg["value"]
        param_type = cfg.get("type", "")

        if param_type == "string":
            lines.append(f"{name}={val}")
        elif param_type == "bool":
            lines.append(f"{name}={val}||0||0||1||N")
        elif cfg.get("optimize", False):
            start = cfg["start"]
            step = cfg["step"]
            stop = cfg["stop"]
            lines.append(f"{name}={val}||{start}||{step}||{stop}||Y")
        else:
            lines.append(f"{name}={val}||{val}||0||{val}||N")

    content = "\n".join(lines) + "\n"

    with open(set_path, "w", encoding="ascii") as f:
        f.write(content)

    print(f"  .set file: {set_path}")
    return f"{ea_name}.set"


def generate_ini_file(ea_name, symbol, set_filename, run_index):
    """Generate .ini config file for MT5 terminal."""
    os.makedirs(CONFIG_DIR, exist_ok=True)

    # Reports go to MQL5/Files/ (MT5 can write here)
    report_dir = os.path.join(MQL5_DIR, "Files", "OkiReports")
    os.makedirs(report_dir, exist_ok=True)
    report_rel = f"MQL5\\Files\\OkiReports\\{ea_name}_{symbol}"

    ini_content = f"""[Tester]
Expert=OkiSignal\\{ea_name}
ExpertParameters={set_filename}
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
Report={report_rel}
ReplaceReport=1
ShutdownTerminal=1
UseLocal=1
UseRemote=0
UseCloud=0
Visual=0
"""

    ini_path = os.path.join(CONFIG_DIR, f"{run_index:03d}_{ea_name}_{symbol}.ini")
    with open(ini_path, "w", encoding="ascii") as f:
        f.write(ini_content)

    return ini_path, report_rel


def kill_mt5():
    """Kill any running MT5 terminal instances."""
    try:
        result = subprocess.run(["taskkill", "/f", "/im", "terminal64.exe"],
                                capture_output=True, timeout=10)
        if result.returncode == 0:
            print("  Killed existing MT5")
            time.sleep(3)
    except Exception:
        pass


def run_mt5_optimization(ini_path, ea_name, symbol, report_rel, timeout=900):
    """Run MT5 with config using PowerShell -Wait for proper completion."""
    kill_mt5()
    time.sleep(2)

    print(f"  Launching MT5: {ea_name} x {symbol}...")

    # Use PowerShell Start-Process -Wait for proper synchronization
    ps_cmd = (
        f'$p = Start-Process -FilePath "{MT5_TERMINAL}" '
        f'-ArgumentList "/config:`"{ini_path}`"" '
        f'-PassThru; '
        f'$p.WaitForExit({timeout * 1000}); '
        f'if(!$p.HasExited) {{ $p.Kill(); exit 1 }} '
        f'exit $p.ExitCode'
    )

    start_time = time.time()

    proc = subprocess.Popen(
        ["powershell", "-Command", ps_cmd],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )

    # Monitor progress
    while proc.poll() is None:
        elapsed = time.time() - start_time
        mins = int(elapsed // 60)
        secs = int(elapsed % 60)
        print(f"\r  Running... {mins:02d}:{secs:02d}", end="", flush=True)

        if elapsed > timeout + 30:
            print(f"\n  Script timeout, killing...")
            proc.kill()
            return False

        time.sleep(5)

    elapsed = time.time() - start_time
    print(f"\n  Completed in {elapsed:.0f}s")

    # Check for report file
    report_base = os.path.join(MT5_DATA_DIR, report_rel)
    for ext in [".xml", ".htm"]:
        if os.path.exists(report_base + ext):
            print(f"  Report found: {report_base + ext}")
            return True

    # Search in common locations
    report_name = f"{ea_name}_{symbol}"
    search_locations = [
        os.path.join(MQL5_DIR, "Files", "OkiReports"),
        os.path.join(MT5_DATA_DIR, "Tester"),
        MT5_DATA_DIR,
        os.path.join(MQL5_DIR, "Files"),
    ]

    for loc in search_locations:
        if not os.path.isdir(loc):
            continue
        for f in os.listdir(loc):
            if report_name in f and f.endswith(".xml"):
                print(f"  Report found: {os.path.join(loc, f)}")
                return True

    print(f"  WARNING: No report file found")
    return False


def collect_reports():
    """Copy all reports from MT5 to our results directory."""
    os.makedirs(RESULTS_DIR, exist_ok=True)
    import shutil

    report_dir = os.path.join(MQL5_DIR, "Files", "OkiReports")
    if not os.path.isdir(report_dir):
        return 0

    count = 0
    for f in os.listdir(report_dir):
        if f.endswith(".xml"):
            src = os.path.join(report_dir, f)
            dst = os.path.join(RESULTS_DIR, f)
            shutil.copy2(src, dst)
            count += 1

    return count


def main():
    parser = argparse.ArgumentParser(description="OkiSignal Auto Optimizer v2")
    parser.add_argument("--ea", type=str, help="Run specific EA only")
    parser.add_argument("--symbol", type=str, help="Run specific symbol only")
    parser.add_argument("--symbols", type=str, help="Comma-separated symbols")
    parser.add_argument("--report", action="store_true", help="Analyze existing results only")
    parser.add_argument("--timeout", type=int, default=900, help="Timeout per run (seconds)")
    args = parser.parse_args()

    if args.report:
        # Use the analyzer script
        os.system(f'python "{os.path.join(os.path.dirname(__file__), "analyze_results.py")}"')
        return

    # Filter strategies and symbols
    eas = [args.ea] if args.ea else list(STRATEGIES.keys())
    if args.symbols:
        symbols = args.symbols.split(",")
    elif args.symbol:
        symbols = [args.symbol]
    else:
        symbols = SYMBOLS

    total_runs = len(eas) * len(symbols)
    print(f"{'='*60}")
    print(f"OkiSignal Auto Optimizer v2")
    print(f"{'='*60}")
    print(f"Strategies: {eas}")
    print(f"Symbols: {symbols}")
    print(f"Total runs: {total_runs}")
    print(f"Timeout per run: {args.timeout}s ({args.timeout//60}min)")
    print(f"Model: Open prices only (fast screening)")
    print(f"Optimization: Genetic algorithm")
    print(f"Period: {FROM_DATE} - {TO_DATE}")
    print(f"Start: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"{'='*60}")

    run_index = 0
    completed = 0
    failed = 0

    for ea_name in eas:
        if ea_name not in STRATEGIES:
            print(f"Unknown strategy: {ea_name}")
            continue

        strategy = STRATEGIES[ea_name]

        # Generate .set file once per EA
        set_filename = generate_set_file(ea_name, strategy["params"])

        for symbol in symbols:
            run_index += 1
            print(f"\n[{run_index}/{total_runs}] {ea_name} x {symbol}")
            print("-" * 40)

            # Generate .ini file
            ini_path, report_rel = generate_ini_file(
                ea_name, symbol, set_filename, run_index
            )

            # Run optimization
            success = run_mt5_optimization(
                ini_path, ea_name, symbol, report_rel, args.timeout
            )

            if success:
                completed += 1
            else:
                failed += 1

            time.sleep(3)

    # Collect reports to our results dir
    print(f"\nCollecting reports...")
    count = collect_reports()
    print(f"Copied {count} report files to {RESULTS_DIR}")

    print(f"\n{'='*60}")
    print(f"DONE: {completed} completed, {failed} failed")
    print(f"End: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"{'='*60}")

    # Analyze
    if completed > 0:
        print(f"\nAnalyzing results...")
        os.system(f'python "{os.path.join(os.path.dirname(__file__), "analyze_results.py")}"')


if __name__ == "__main__":
    main()
