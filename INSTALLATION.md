# Installation

## Requirements

- MetaTrader 5 build supporting MQL5 includes and chart objects.
- Python 3.10+ only for offline research tools.
- NinjaTrader 8 is optional and currently unverified.

## MT5

1. In MT5 select **File → Open Data Folder**.
2. Copy this repository's `MQL5` folder into the opened data directory.
3. Open MetaEditor.
4. Compile `MQL5/Indicators/PriceActionBarByBar.mq5` with `F7`.
5. Refresh Navigator and attach **PriceActionBarByBar** to a chart.
6. Compile and run `MQL5/Scripts/PAB_UnitTests.mq5` manually to execute deterministic assertions.

The indicator uses repository-relative includes, so MetaEditor compiles the headers beside the indicator source.

## Python research tools

From `research`:

```powershell
python -m unittest discover -s tests -v
python -m compileall -q pab_research tests
```

No broker credentials or third-party Python packages are required for the included tests.

## NinjaTrader

See `NinjaTrader/README.md`. The current port predates the MQL5 closed-bar/context/decision changes, compiles in only the maintainer's environment, and must not be described as feature-equivalent.
