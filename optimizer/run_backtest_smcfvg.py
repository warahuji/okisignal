"""
SMC_FVG Backtest Runner
========================
Run single-pass backtests for SMC_FVG EA across all 8 pairs.
No optimization - just check if the strategy produces trades and basic stats.

Usage:
    python run_backtest_smcfvg.py                    # All pairs
    python run_backtest_smcfvg.py --symbol USDJPY    # Single pair
"""

import os
import sys
import time
import subprocess
import argparse
from pathlib import Path
from datetime import datetime

# === Configuration ===
MT5_TERMINAL = r"C:\Program Files\Axiory MetaTrader 5\terminal64.exe"
MT5_DATA_DIR = r"C:\Users\daisuke\AppData\Roaming\MetaQuotes\Terminal\ED051E4A9BEE8A33BDDD0F947358B2B2"
MQL5_DIR = os.path.join(MT5_DATA_DIR, "MQL5")

RESULTS_DIR = r"D:\claudecode\okisignal\optimizer\results\smcfvg"
CONFIG_DIR = r"D:\claudecode\okisignal\optimizer\configs"

FROM_DATE = "2025.01.01"
TO_DATE = "2026.04.01"
DEPOSIT = 100000
CURRENCY = "JPY"
LEVERAGE = "1:1000"

SYMBOLS = ["USDJPY", "EURUSD", "GBPUSD", "AUDUSD", "GBPJPY", "EURJPY", "AUDJPY", "XAUUSD"]

EA_PARAMS = {
    "InpWebhookUrl":   {"value": "", "type": "string"},
    "InpRiskPercent":   {"value": 1.0},
    "InpSwingLen":      {"value": 5},
    "InpSLMult":        {"value": 1.5},
    "InpTP1Mult":       {"value": 1.5},
    "InpTP2Mult":       {"value": 3.0},
    "InpTP1ClosePct":   {"value": 50.0},
    "InpATRPeriod":     {"value": 14},
    "InpADRMaxRatio":   {"value": 0.8},
    "InpMagic":         {"value": 106},
    "InpTradeEnabled":  {"value": "true", "type": "bool"},
}


def generate_set_file():
    """Generate .set file for MT5 backtest."""
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
        else:
            lines.append(f"{name}={val}||{val}||0||{val}||N")

    content = "\n".join(lines) + "\n"
    with open(set_path, "w", encoding="ascii") as f:
        f.write(content)

    print(f"  .set file: {set_path}")
    return "SMC_FVG.set"


def generate_ini_file(symbol, set_filename, run_index):
    """Generate .ini config for single-pass backtest."""
    os.makedirs(CONFIG_DIR, exist_ok=True)

    report_dir = os.path.join(MQL5_DIR, "Files", "OkiReports")
    os.makedirs(report_dir, exist_ok=True)
    report_rel = f"MQL5\\Files\\OkiReports\\SMC_FVG_{symbol}"

    ini_content = f"""[Tester]
Expert=OkiSignal\\SMC_FVG
ExpertParameters={set_filename}
Symbol={symbol}
Period=M15
Optimization=0
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
"""

    ini_path = os.path.join(CONFIG_DIR, f"smcfvg_{run_index:03d}_{symbol}.ini")
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


def run_backtest(ini_path, symbol, report_rel, timeout=300):
    """Run MT5 backtest via PowerShell -Wait."""
    kill_mt5()
    time.sleep(2)

    print(f"  Launching MT5 backtest: SMC_FVG x {symbol}...")

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
        time.sleep(5)

    elapsed = time.time() - start_time
    print(f"\n  Completed in {elapsed:.0f}s")

    report_base = os.path.join(MT5_DATA_DIR, report_rel)
    for ext in [".xml", ".htm"]:
        if os.path.exists(report_base + ext):
            print(f"  Report: {report_base + ext}")
            return True

    print("  WARNING: No report found")
    return False


def main():
    parser = argparse.ArgumentParser(description="SMC_FVG Backtest Runner")
    parser.add_argument("--symbol", type=str, help="Single symbol to test")
    args = parser.parse_args()

    symbols = [args.symbol] if args.symbol else SYMBOLS
    os.makedirs(RESULTS_DIR, exist_ok=True)

    print("=" * 60)
    print(f"SMC_FVG Backtest: {len(symbols)} pairs")
    print(f"Period: {FROM_DATE} - {TO_DATE}")
    print("=" * 60)

    set_filename = generate_set_file()

    results = []
    for i, symbol in enumerate(symbols):
        print(f"\n[{i+1}/{len(symbols)}] {symbol}")
        ini_path, report_rel = generate_ini_file(symbol, set_filename, i + 1)
        ok = run_backtest(ini_path, symbol, report_rel)
        results.append((symbol, ok))

    print("\n" + "=" * 60)
    print("RESULTS SUMMARY")
    print("=" * 60)
    for symbol, ok in results:
        status = "OK" if ok else "FAIL"
        print(f"  {symbol}: {status}")

    print(f"\nReports: {os.path.join(MT5_DATA_DIR, 'MQL5', 'Files', 'OkiReports')}")


if __name__ == "__main__":
    main()
