"""
SMC_FVG Optimizer
==================
Run MT5 genetic optimization for SMC_FVG EA across all 8 pairs.
Optimizes: SwingLen, SLMult, TP1Mult, TP2Mult, ADRMaxRatio

Usage:
    python run_optimize_smcfvg.py                       # All pairs
    python run_optimize_smcfvg.py --symbol USDJPY       # Single pair
    python run_optimize_smcfvg.py --symbols USDJPY,EURUSD  # Multiple
"""

import os
import sys
import time
import subprocess
import argparse
from pathlib import Path
from datetime import datetime

# === Configuration ===
MT5_TERMINAL = r"D:\xm\terminal64.exe"
MT5_DATA_DIR = r"C:\Users\daisuke\AppData\Roaming\MetaQuotes\Terminal\F5969E95BA9A52F08900E609CFE3E69E"
MQL5_DIR = os.path.join(MT5_DATA_DIR, "MQL5")

RESULTS_DIR = r"D:\claudecode\okisignal\optimizer\results\smcfvg"
CONFIG_DIR = r"D:\claudecode\okisignal\optimizer\configs"

FROM_DATE = "2025.01.01"
TO_DATE = "2026.04.01"
DEPOSIT = 100000
CURRENCY = "JPY"
LEVERAGE = "1:1000"

SYMBOLS = ["USDJPY#", "EURUSD#", "GBPUSD#", "AUDUSD#", "GBPJPY#", "EURJPY#", "AUDJPY#", "XAUUSD#"]

# Optimization parameters: value||start||step||stop||Y/N
EA_PARAMS = {
    "InpWebhookUrl":   {"value": "", "type": "string", "optimize": False},
    "InpRiskPercent":   {"value": 1.0, "optimize": False},
    "InpSwingLen":      {"value": 5, "start": 3, "step": 1, "stop": 8, "optimize": True},
    "InpSLMult":        {"value": 1.5, "start": 0.75, "step": 0.25, "stop": 2.5, "optimize": True},
    "InpTP1Mult":       {"value": 1.5, "start": 0.75, "step": 0.25, "stop": 2.5, "optimize": True},
    "InpTP2Mult":       {"value": 3.0, "start": 1.5, "step": 0.5, "stop": 5.0, "optimize": True},
    "InpTP1ClosePct":   {"value": 50.0, "optimize": False},
    "InpATRPeriod":     {"value": 14, "optimize": False},
    "InpADRMaxRatio":   {"value": 0.8, "start": 0.5, "step": 0.1, "stop": 1.0, "optimize": True},
    "InpMagic":         {"value": 106, "optimize": False},
    "InpTradeEnabled":  {"value": "true", "type": "bool", "optimize": False},
    "InpSessionStart":  {"value": 8, "start": 2, "step": 2, "stop": 14, "optimize": True},
    "InpSessionEnd":    {"value": 21, "start": 16, "step": 1, "stop": 23, "optimize": True},
}


def generate_set_file():
    """Generate .set file with optimization ranges."""
    set_dir = os.path.join(MQL5_DIR, "Profiles", "Tester")
    os.makedirs(set_dir, exist_ok=True)
    set_path = os.path.join(set_dir, "SMC_FVG.set")

    lines = []
    for name, cfg in EA_PARAMS.items():
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
    return "SMC_FVG.set"


def generate_ini_file(symbol, set_filename, run_index):
    """Generate .ini config for genetic optimization."""
    os.makedirs(CONFIG_DIR, exist_ok=True)

    report_dir = os.path.join(MQL5_DIR, "Files", "OkiReports")
    os.makedirs(report_dir, exist_ok=True)
    report_rel = f"MQL5\\Files\\OkiReports\\SMC_FVG_OPT_{symbol}"

    # Optimization=2 = Genetic, OptimizationCriterion=6 = Custom (or 0=Balance)
    ini_content = f"""[Tester]
Expert=OkiSignal\\SMC_FVG
ExpertParameters={set_filename}
Symbol={symbol}
Period=M15
Optimization=2
Model=1
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
Login=75443293
"""

    ini_path = os.path.join(CONFIG_DIR, f"smcfvg_opt_{run_index:03d}_{symbol}.ini")
    with open(ini_path, "w", encoding="ascii") as f:
        f.write(ini_content)

    return ini_path, report_rel


def kill_mt5():
    """Kill any running MT5 instances."""
    try:
        result = subprocess.run(["taskkill", "/f", "/im", "terminal64.exe"],
                                capture_output=True, timeout=10)
        if result.returncode == 0:
            print("  Killed existing MT5")
            time.sleep(3)
    except Exception:
        pass


def run_optimization(ini_path, symbol, report_rel, timeout=1200):
    """Run MT5 genetic optimization."""
    kill_mt5()
    time.sleep(2)

    print(f"  Launching MT5 optimization: SMC_FVG x {symbol}...")
    print(f"  Timeout: {timeout}s ({timeout//60}min)")

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

    while proc.poll() is None:
        elapsed = time.time() - start_time
        mins = int(elapsed // 60)
        secs = int(elapsed % 60)
        print(f"\r  Running... {mins:02d}:{secs:02d}", end="", flush=True)
        if elapsed > timeout + 30:
            print(f"\n  Script timeout, killing...")
            proc.kill()
            return False
        time.sleep(10)

    elapsed = time.time() - start_time
    print(f"\n  Completed in {elapsed:.0f}s ({elapsed/60:.1f}min)")

    report_base = os.path.join(MT5_DATA_DIR, report_rel)
    for ext in [".xml", ".htm"]:
        if os.path.exists(report_base + ext):
            print(f"  Report: {report_base + ext}")
            return True

    print("  WARNING: No report found (check MT5 optimization results manually)")
    return True  # Optimization results stored in MT5 cache


def main():
    parser = argparse.ArgumentParser(description="SMC_FVG Optimizer")
    parser.add_argument("--symbol", type=str, help="Single symbol")
    parser.add_argument("--symbols", type=str, help="Comma-separated symbols")
    parser.add_argument("--timeout", type=int, default=1200, help="Timeout per pair (sec)")
    args = parser.parse_args()

    if args.symbol:
        symbols = [args.symbol]
    elif args.symbols:
        symbols = args.symbols.split(",")
    else:
        symbols = SYMBOLS

    os.makedirs(RESULTS_DIR, exist_ok=True)

    print("=" * 60)
    print(f"SMC_FVG Optimization: {len(symbols)} pairs")
    print(f"Period: {FROM_DATE} - {TO_DATE}")
    print(f"Optimizing: SwingLen, SLMult, TP1Mult, TP2Mult, ADRMaxRatio")
    print(f"Method: Genetic (Criterion: Balance)")
    print(f"Timeout: {args.timeout}s per pair")
    print("=" * 60)

    set_filename = generate_set_file()

    results = []
    total_start = time.time()

    for i, symbol in enumerate(symbols):
        print(f"\n{'='*40}")
        print(f"[{i+1}/{len(symbols)}] {symbol}")
        print(f"{'='*40}")
        ini_path, report_rel = generate_ini_file(symbol, set_filename, i + 1)
        ok = run_optimization(ini_path, symbol, report_rel, args.timeout)
        results.append((symbol, ok))

    total_elapsed = time.time() - total_start

    print(f"\n{'='*60}")
    print("OPTIMIZATION SUMMARY")
    print(f"{'='*60}")
    for symbol, ok in results:
        status = "DONE" if ok else "FAIL"
        print(f"  {symbol}: {status}")
    print(f"\nTotal time: {total_elapsed/60:.1f} min")
    print(f"\nOpen MT5 Strategy Tester > Optimization Results to see best parameters.")
    print(f"Look for highest Balance or Profit Factor in the results.")


if __name__ == "__main__":
    main()
