# EIS Data Processing Toolkit (MATLAB)

Batch-processing pipeline for **Electrochemical Impedance Spectroscopy (EIS)** time-domain waveform data. Point it at a folder of oscilloscope/DAQ CSV exports and it will estimate frequencies, denoise/reconstruct the signals, trim incomplete cycles, compute per-frequency impedance and phase via FFT, and generate Bode/Nyquist plots and summary tables — per channel and combined across all channels.

Built for multi-channel test setups such as fuel cell stacks or multi-cell battery packs, where each voltage tap (`Uz1`, `Uz2`, …) needs its own impedance spectrum referenced to a common shunt current measurement.

> **Script:** `EIS_data_processing_M_Haris_Naveed_V1.m`
> **Type:** Single MATLAB script (main script + local functions)

---

## Table of Contents

- [What it does](#what-it-does)
- [Requirements](#requirements)
- [Input data format](#input-data-format)
- [Quick start](#quick-start)
- [Configuration](#configuration)
- [Pipeline overview](#pipeline-overview)
- [Outputs](#outputs)
- [Documentation](#documentation)
- [Known limitations](#known-limitations)

---

## What it does

For each CSV file in a selected folder, and for each user-selected voltage channel:

1. **Loads** the time-series current (derived from a shunt resistor voltage) and voltage signal.
2. **Estimates** the fundamental excitation frequency via FFT.
3. **Smooths / reconstructs** the signal using one of four methods (4PSF, moving average, Savitzky-Golay, or Butterworth low-pass).
4. **Trims** leading/trailing partial sine cycles (optional).
5. **Computes** the complex impedance `Z(f) = V(f) / I(f)` at the fundamental frequency, plus magnitude and phase, for both the raw and smoothed signal.
6. **Renames and archives** the source CSV using the detected channel and frequency.
7. **Plots** time-domain waveforms and zoomed FFT peaks per file.
8. After all files for a channel are processed: **groups** results by frequency (±5% tolerance), then generates single-channel **Bode** (linear + log frequency) and **Nyquist** plots plus summary tables.
9. After all channels are processed: generates **interactive, combined multi-channel** Bode and Nyquist plots with checkbox toggles for raw/smoothed visibility.

## Requirements

- MATLAB **R2019b or later** (uses App Designer UI components, string arrays, and `readtable`/`detectImportOptions`).
- **Signal Processing Toolbox** (`filtfilt`, `butter`, `sgolayfilt`, `movmean`).
- No other toolboxes required.

## Input data format

The script expects CSV exports with a fixed layout:

| Rows | Content |
|---|---|
| Row 5 | Column/trace header names (used to populate the channel-selection GUI) |
| Rows 14–15 | Date string and time string (used to build the output filename timestamp) |
| Row 16+ | Numeric time-series data, comma-delimited |

| Column | Content |
|---|---|
| 1 | Time (`duration`, `datetime`, or numeric seconds) |
| 2 | Shunt voltage `V_shunt` (used to derive current) |
| 3…N | Individual voltage channels `Uz1, Uz2, … Uz(N-2)` |

All CSV files in a given run **must share the same column layout**. See [Techinical Reference](docs/Techinical_Reference.md#4-input-data-format-csv) for full details, validation rules, and edge-case handling.

## Quick start

1. Open the script in MATLAB and run it (or press **Run**).
2. In the folder dialog, select the directory containing your CSV waveform files.
3. In the **Select Columns** GUI:
   - Tick the voltage channels you want analyzed.
   - Choose the current/shunt column.
   - Enter the shunt resistance (Ω).
   - Pick a smoothing method.
   - Choose whether to trim incomplete cycles.
   - Click **OK**.
4. The script processes each file for each selected channel, then opens interactive combined Bode and Nyquist figures.
5. All outputs are written to `solution/` (or `solution_YYYYMMDD_HHMMSS/` if `solution` already exists) inside your source folder.

See [Examples](docs/EXAMPLES.md) for a full walkthrough with expected file layouts and output structure.

## Configuration

All tunable defaults live in a block near the top of the script:

```matlab
SAVE_FFT_RAW  = true;
SAVE_FFT_SM   = true;
FFT_ZOOM_BINS = 20;

PRESET_VOLTAGE_COLS   = [3 4 5 6 7];
PRESET_CURRENT_COL    = 2;
PRESET_SHUNT_OHMS     = 0.0075;
PRESET_SMOOTH_METHOD  = '4PSF';
PRESET_ZERO_CROSS_TRIM = true;
```

These only set the **defaults pre-filled in the GUI** — every run can override them interactively. Full parameter reference: [Techinical Reference § Constants](docs/Techinical_Reference.md#10-constants--configurable-parameters).

## Pipeline overview

```
Select folder → Create output folder → Read column headers → Column Selection GUI
        │
        ▼
For each selected voltage channel:
        │
        ├─ For each CSV file:
        │     Load data → Derive current → Estimate frequency (FFT)
        │     → Smooth/reconstruct → Trim cycles (optional)
        │     → FFT peak plots (optional) → Time-domain plot
        │     → Impedance & phase (raw + smoothed) → Polarity correction (even channels)
        │
        ├─ Group & average by frequency (±5%)
        ├─ Channel summary table (CSV + figure)
        ├─ Channel Bode plots (linear + log)
        └─ Channel Nyquist plot
        │
        ▼
Combined multi-channel Bode plot (interactive)
Combined multi-channel Nyquist plot (interactive)
```

Full function-level detail: [Techinical Reference § Function Reference](docs/Techinical_Reference.md#5-function-by-function-reference).

## Outputs

Per channel (`solution/Uz<N>/`):
- Renamed/archived source CSVs (`Renamed_Uz<N>_<timestamp>_<freq>Hz.csv`)
- Time-domain waveform plots (`.jpg` + `.fig`)
- FFT zoom peak plots, raw and smoothed (`.png` + `.fig`, optional)
- Bode plots, linear and log frequency (`.png` + `.fig`)
- Nyquist plot (`.png` + `.fig`)
- Summary data table (`.png`/`.fig` figure + CSV)

At the run root (`solution/`):
- Combined multi-channel Bode plots, linear and log (`.png` + `.fig`)
- Combined multi-channel Nyquist plot (`.png` + `.fig`)

## Documentation

- **[Techinical Reference](docs/Techinical_Reference.md)** — every function, GUI element, constant, formula, and error-handling path.
- **[Theory & Background](docs/THEORY.md)** — EIS fundamentals, the impedance/phase math, the 4PSF algorithm, and why polarity correction exists.
- **[Examples](docs/EXAMPLES.md)** — annotated end-to-end walkthrough and output structure.

## Known limitations

- All CSVs in a folder are assumed to share identical column order — mismatched layouts silently select the wrong data.
- Even-numbered channels have phase/impedance polarity inverted by hardcoded convention (`mod(uz_num,2)==0`); confirm this matches your probe wiring before trusting phase sign.
- Selecting column 1 or 2 as a "voltage channel" produces invalid channel labels (`Uz-1`, `Uz0`).
- `lockin_reconstruct` is implemented but not wired into the smoothing dispatcher — it's dead code, available if you want to add it as a fifth method.

See [Techinical Reference § Open Questions](docs/Techinical_Reference.md#14-open-questions--ambiguities) for the complete list.

---

*Author: M. Haris Naveed*
