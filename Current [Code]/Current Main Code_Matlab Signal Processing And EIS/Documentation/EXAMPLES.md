# Examples

An end-to-end walkthrough of running the script, plus the resulting output structure.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Expected input layout](#expected-input-layout)
- [Walkthrough: full run](#walkthrough-full-run)
- [Output folder structure](#output-folder-structure)
- [Reading the combined plots](#reading-the-combined-plots)
- [Customizing defaults for repeat runs](#customizing-defaults-for-repeat-runs)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

- MATLAB R2019b+ with the Signal Processing Toolbox.
- A folder containing one or more `.csv` waveform exports, all sharing the same column layout (see [API Reference § Input Data Format](API_REFERENCE.md#4-input-data-format-csv)).

## Expected input layout

A single source folder, one CSV per test frequency (or per repeated run at a given frequency):

```
my_eis_run/
├── scope_export_001.csv   (e.g. 10 Hz)
├── scope_export_002.csv   (e.g. 31.6 Hz)
├── scope_export_003.csv   (e.g. 100 Hz)
├── scope_export_004.csv   (e.g. 316 Hz)
└── scope_export_005.csv   (e.g. 1000 Hz)
```

Each CSV has trace names on row 5, date/time metadata on rows 14–15, and numeric data from row 16 onward, with time in column 1, shunt voltage in column 2, and voltage channels `Uz1…UzN` from column 3 onward.

## Walkthrough: full run

**1. Run the script.**
```matlab
>> EIS_data_processing_M_Haris_Naveed_V1
```

**2. Select the source folder** in the dialog that appears — point it at `my_eis_run/`.

The script creates `my_eis_run/solution/` (or `solution_20260901_185422/` if `solution` already exists from a prior run).

**3. Column Selection GUI opens.**

It reads row 5 of `scope_export_001.csv` to populate channel names, then shows:

| Field | Example selection |
|---|---|
| Voltage channel checkboxes | ☑ Uz1, ☑ Uz2, ☑ Uz3 |
| Current/Shunt column | `2: Ushunt` |
| Shunt resistance (Ω) | `0.0075` |
| Smoothing method | `4PSF` |
| Trim incomplete cycles | ☑ enabled |

Click **OK**.

**4. Per-channel, per-file processing.**

For `Uz1` (column 3), the script processes all 5 files in order. For `scope_export_001.csv` (10 Hz), the console shows something like:

```
========== Processing Uz1 (column 3) ==========
--- Peak frequency from I  (Hz): 10.002341
 ...
--- Impedance ---
Z1 = 842.317 mOhm | Phase = -12.44 deg
```

The file is renamed and copied into `solution/Uz1/` as:
```
Renamed_Uz1_20260901_185422_10Hz.csv
```

A time-domain waveform plot and (if enabled) FFT zoom plots are saved alongside it.

This repeats for all 5 files, then for `Uz2` and `Uz3` in turn.

**5. Per-channel summary.**

After all 5 files are processed for `Uz1`, the script:
- Groups the 5 frequency points (already distinct, so no averaging needed here — but if two files were both ~10 Hz within ±5%, they'd be merged).
- Generates `bode_plot_linear.png`, `bode_plot_log.png`, `nyquist_plot.png` in `solution/Uz1/`.
- Writes a summary CSV and table figure.

**6. Combined multi-channel figures.**

After `Uz1`, `Uz2`, `Uz3` are all processed, two interactive figure windows pop up:
- **Combined Bode** — all three channels' magnitude and phase overlaid, with 4 checkboxes to toggle raw magnitude / smoothed magnitude / raw phase / smoothed phase visibility.
- **Combined Nyquist** — all three channels' impedance loci overlaid, with raw/smoothed toggles.

Both are saved to `solution/` as `combined_bode_linear.png`, `combined_bode_log.png`, `combined_nyquist.png` (plus `.fig` versions).

## Output folder structure

```
my_eis_run/
└── solution_20260901_185422/
    ├── combined_bode_linear.png / .fig
    ├── combined_bode_log.png / .fig
    ├── combined_nyquist.png / .fig
    ├── Uz1/
    │   ├── Renamed_Uz1_20260901_185422_10Hz.csv
    │   ├── Renamed_Uz1_20260901_185422_32Hz.csv
    │   ├── ...
    │   ├── Renamed_Uz1_20260901_185422_10Hz_plot.jpg / .fig
    │   ├── Renamed_Uz1_20260901_185422_10Hz_fft_raw.png / .fig
    │   ├── Renamed_Uz1_20260901_185422_10Hz_fft_smoothed.png / .fig
    │   ├── bode_plot_linear.png / .fig
    │   ├── bode_plot_log.png / .fig
    │   ├── nyquist_plot.png / .fig
    │   ├── summary_table_figure.png / .fig
    │   └── summary_data_tables.png / .fig
    ├── Uz2/
    │   └── ... (same structure)
    └── Uz3/
        └── ... (same structure)
```

## Reading the combined plots

- **Combined Bode:** compare impedance magnitude and phase trends across channels at a glance — useful for spotting one cell/probe behaving differently from the rest of a stack. Toggle "smoothed" off temporarily to sanity-check that smoothing isn't distorting the underlying data.
- **Combined Nyquist:** compare arc shapes/diameters across channels — a channel with a visibly larger semicircle typically indicates higher charge-transfer resistance on that cell/tap relative to the others.

## Customizing defaults for repeat runs

If you're running the same rig configuration repeatedly, hand-edit the preset block near the top of the script instead of re-selecting in the GUI each time:

```matlab
PRESET_VOLTAGE_COLS   = [3 4 5 6 7];   % adjust to your channel count
PRESET_CURRENT_COL    = 2;
PRESET_SHUNT_OHMS     = 0.0075;        % match your actual shunt resistor
PRESET_SMOOTH_METHOD  = '4PSF';
PRESET_ZERO_CROSS_TRIM = true;
```

These are only pre-ticked defaults — the GUI still opens and lets you confirm or override them per run.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Wrong data ends up under a channel label | CSVs in the folder have inconsistent column order | Ensure every CSV in the batch was exported with the same channel configuration |
| Phase sign looks flipped on one channel vs. others | Even/odd polarity correction doesn't match your actual wiring | Review the `mod(uz_num,2)==0` correction in `phase_shift_fft`'s caller and adjust if needed |
| A file is silently skipped | Fewer than 10 samples, or NaNs in time/current/voltage | Check the console `warning` message naming the file; inspect that CSV directly |
| Channel labeled `Uz0` or `Uz-1` | Column 1 or 2 was selected as a voltage channel in the GUI | Don't select the time or shunt column as a voltage channel |
| FFT-estimated frequency is noisy/wrong | Very low SNR, or a non-sinusoidal excitation | Try Butterworth or 4PSF smoothing; verify `PRESET_SHUNT_OHMS` matches your hardware |
