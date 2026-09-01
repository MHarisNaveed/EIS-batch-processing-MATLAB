# EIS Data Processing Script — Documentation

**File:** `EIS_data_processing_M_Haris_Naveed_V1.m`
**Purpose:** Loads oscilloscope-exported CSV waveform files (current + one or more
voltage channels), estimates the excitation frequency of each file, smooths /
denoises the signals, computes impedance magnitude and phase (EIS), and produces
per-channel and combined-channel plots (time-domain, FFT peak, Bode, Nyquist,
summary tables).

This document explains **what each section/function does**, its **inputs**,
**outputs**, and **side effects** (files written, figures created), so future edits
are easier to place correctly.

---

## Table of Contents

1. [Script-level Setup](#1-script-level-setup)
2. [Toggles & Presets](#2-toggles--presets)
3. [Column Selection GUI Call](#3-column-selection-gui-call)
4. [Outer Loop — Per Voltage Channel](#4-outer-loop--per-voltage-channel)
5. [Inner Loop — Per CSV File](#5-inner-loop--per-csv-file)
6. [Per-Channel Post-Processing](#6-per-channel-post-processing)
7. [Combined Multi-Channel Plots](#7-combined-multi-channel-plots)
8. [Function Reference](#8-function-reference)

---

## 1. Script-level Setup

### Folder selection & output folder creation
```matlab
folder = uigetdir(...)
out_folder = fullfile(folder, 'solution')
```
- **What it does:** Opens a folder-picker dialog for the user to select the folder
  containing raw waveform CSVs. Creates a `solution` output subfolder; if one
  already exists (e.g. from a previous run), a timestamped folder
  (`solution_YYYYMMDD_HHMMSS`) is created instead so results are never overwritten.
- **Inputs:** None (interactive dialog).
- **Outputs (script-level variables):**
  - `folder` — path to the selected source folder.
  - `out_folder` — path to the (possibly timestamped) output folder.
  - `files` — `dir()` struct array of all `*.csv` files found in `folder`.

---

## 2. Toggles & Presets

```matlab
SAVE_FFT_RAW, SAVE_FFT_SM, FFT_ZOOM_BINS
PRESET_VOLTAGE_COLS, PRESET_CURRENT_COL, PRESET_SHUNT_OHMS
PRESET_SMOOTH_METHOD, PRESET_ZERO_CROSS_TRIM
```
- **What it does:** Defines default/starting values that pre-populate the Column
  Selection GUI. These are only *defaults* — the GUI lets the user override them
  interactively before processing starts.
- **Variables:**
  | Variable | Meaning |
  |---|---|
  | `SAVE_FFT_RAW` (bool) | If true, saves a zoomed FFT peak plot (current+voltage) for the **raw** signal per file. |
  | `SAVE_FFT_SM` (bool) | Same, but for the **smoothed** signal. |
  | `FFT_ZOOM_BINS` (int) | Number of FFT bins shown on each side of the detected peak in the saved FFT plots. |
  | `PRESET_VOLTAGE_COLS` | 1-based column indices pre-ticked as voltage channels in the GUI. |
  | `PRESET_CURRENT_COL` | 1-based column index pre-selected as the current/shunt column. |
  | `PRESET_SHUNT_OHMS` | Default shunt resistance value (Ohms) shown in the GUI. |
  | `PRESET_SMOOTH_METHOD` | Default smoothing method dropdown selection (`'4PSF'`, `'Moving Average'`, `'Savitzky-Golay'`, `'Low-pass Butterworth'`). |
  | `PRESET_ZERO_CROSS_TRIM` | Default state of the "enable zero-crossing cycle trim" checkbox. |

### Header name extraction
```matlab
traceRow = readcell(sampleFile, 'Range', '5:5');
headerNames = ...
```
- **What it does:** Reads row 5 (the `TraceName` row) of the first CSV file to get
  human-readable channel labels (e.g. `Uz1 [V]`, `Ushunt [V]`), used to label
  checkboxes/dropdowns in the GUI.
- **Inputs:** `sampleFile` (first file in `files`).
- **Outputs:** `headerNames` — 1×N string array; index *N* corresponds to column *N*
  in the data table `T`.

---

## 3. Column Selection GUI Call

```matlab
[col_list, current_col_idx, shunt_ohms, SMOOTH_METHOD, ZERO_CROSS_TRIM] = ...
    select_columns_gui(headerNames, PRESET_VOLTAGE_COLS, PRESET_CURRENT_COL, ...
                        PRESET_SHUNT_OHMS, PRESET_SMOOTH_METHOD, PRESET_ZERO_CROSS_TRIM);
```
- **What it does:** Opens an interactive dialog (see [`select_columns_gui`](#select_columns_gui)
  in the Function Reference) letting the user pick which voltage columns to
  process, which column is the current/shunt signal, the shunt resistance, the
  smoothing method, and whether zero-crossing cycle trimming is enabled.
- **Inputs:** `headerNames` + all `PRESET_*` values above.
- **Outputs (script-level variables used for the rest of the run):**
  | Variable | Meaning |
  |---|---|
  | `col_list` | Row vector of selected voltage column indices (e.g. `[3 4 5]`). Drives the outer loop. |
  | `current_col_idx` | Selected current/shunt column index. |
  | `shunt_ohms` | Shunt resistance (Ohms) used to convert shunt voltage → current. |
  | `SMOOTH_METHOD` | Chosen smoothing method string, used by `apply_smoothing`. |
  | `ZERO_CROSS_TRIM` | Boolean; if true, `extract_complete_cycles` is applied after smoothing. |
- **Early exit:** If `col_list` is empty (user cancelled or ticked nothing), the
  script prints a message and `return`s.

---

## 4. Outer Loop — Per Voltage Channel

```matlab
for col_idx = col_list
    ...
end
```
- **What it does:** Iterates over every voltage column the user selected in the
  GUI. For each channel, creates a dedicated output subfolder
  (`out_folder/UzN/`), resets per-channel accumulator arrays, then runs the
  **inner loop** (below) over every CSV file, followed by **per-channel
  post-processing** (summary tables, averaging, Bode/Nyquist plots).
- **Key per-channel variables:**
  | Variable | Meaning |
  |---|---|
  | `uz_num` | Channel number derived from `col_idx - 2` (column 3 → Uz1, column 4 → Uz2, ...). |
  | `uz_label` | String label, e.g. `'Uz3'`. |
  | `uz_folder` | Output subfolder for this channel's files/plots. |
  | `combined` | Struct that **persists across the whole outer loop** (not reset per channel) — accumulates each channel's frequency/impedance/phase data for the final combined multi-channel plots (Section 7). |

### Per-channel array preallocation
```matlab
all_freqs, all_mag_Z1_raw, all_mag_Z1_s, all_phase_V1I_raw, all_phase_V1I_s,
all_Z1_peak_raw, all_Z1_peak_s, T_summary_data, processed_count
```
- **What it does:** Preallocates fixed-size arrays (one slot per CSV file) to
  store, per processed file: dominant frequency, raw/smoothed impedance
  magnitude, raw/smoothed phase, raw/smoothed complex impedance peak, and a row
  for the summary table. `processed_count` tracks how many files were
  successfully processed (some may be skipped due to errors).

---

## 5. Inner Loop — Per CSV File

```matlab
for k = 1:nFiles
    try
        ... (all steps below) ...
    catch ME
        warning(...)
    end
end
```
Wrapped in `try/catch` so a single bad file doesn't halt the whole run — errors
are logged via `warning()` and that file is skipped.

### 5.1 Load & parse CSV
- **What it does:** Reads the CSV (skipping the 15-line instrument header),
  drops any fully-NaN rows, and extracts the time column `t` (converting from
  `duration`/`datetime` to numeric seconds if needed). Also re-reads specific
  header lines (14–15) to extract the recording's real-world date/time
  (`dt_csvscope`), used later for file naming. Falls back to file-modified date
  if header parsing fails.
- **Inputs:** `fullpath` (current file), `current_col_idx`.
- **Outputs:** `t` (time vector), `dt_str` (formatted datetime string for naming).

### 5.2 Extract signal columns
```matlab
v_shunt  = double(T{:, current_col_idx});
current  = (v_shunt / -shunt_ohms);
voltage1 = double(T{:, col_idx});
```
- **What it does:** Converts the shunt-voltage column to a current signal using
  Ohm's law (`I = V / R`, sign-inverted per probe convention), and extracts the
  active voltage channel for this iteration.
- **Inputs:** `T` (data table), `current_col_idx`, `shunt_ohms`, `col_idx`.
- **Outputs:** `current`, `voltage1` (raw signal vectors, same length as `t`).
- **Sanity check:** Skips (via `continue`) if any of `t`, `current`, `voltage1`
  contain NaNs or are too short (<10 samples).

### 5.3 FFT-based frequency estimate & file renaming
```matlab
[freq_c, amp_c] = estimate_freq_amp(current, t);
[freq_v1, amp_v1] = estimate_freq_amp(voltage1, t);
final_freq = freq_c;
newname = sprintf('Renamed_%s_%s_%dHz.csv', uz_label, dt_str, abs(round(final_freq)));
```
- **What it does:** Estimates the dominant excitation frequency from the raw
  current signal via FFT peak detection (see `estimate_freq_amp`), then builds a
  new descriptive filename encoding channel label, recording datetime, and
  frequency. Handles filename collisions. The renamed CSV is physically copied
  into `uz_folder` **only once per unique source file** (on the first channel
  processed for that file — `if col_idx == col_list(1)`), since all channels
  share the same underlying raw CSV.
- **Outputs:** `final_freq`, `newname`, `newpath`, `base` (filename stem, reused
  throughout the rest of the loop for consistent output naming).

### 5.4 Smoothing / noise cancellation
```matlab
[current_s, voltage1_s] = apply_smoothing(current, voltage1, t, freq_c, SMOOTH_METHOD);
if ZERO_CROSS_TRIM
    [current_s, voltage1_s, cycle_idx] = extract_complete_cycles(current_s, voltage1_s);
    t_s = t(cycle_idx);
else
    t_s = t;
end
```
- **What it does:** Applies the user-selected smoothing method (see
  [`apply_smoothing`](#apply_smoothing)) to denoise both signals. If zero-crossing
  trim is enabled, further trims the smoothed signals down to only complete
  current cycles (see [`extract_complete_cycles`](#extract_complete_cycles)) —
  this improves FFT/impedance accuracy by removing partial-cycle edge effects.
- **Inputs:** `current`, `voltage1`, `t`, `freq_c`, `SMOOTH_METHOD`, `ZERO_CROSS_TRIM`.
- **Outputs:** `current_s`, `voltage1_s` (smoothed, possibly trimmed), `t_s`
  (corresponding time vector — shorter than `t` if trimmed).
- **Saved output (conditional):** If `SAVE_FFT_SM` is true, saves a zoomed
  FFT peak plot of the **smoothed** current+voltage to
  `uz_folder/<base>_fft_smoothed.png` (+ `.fig`).

### 5.5 Plot raw vs. smoothed time-domain signal
- **What it does:** Creates a 2-subplot figure (current on top, voltage on
  bottom), each showing raw vs. smoothed overlaid traces.
- **Saved output:** `uz_folder/<base>_plot.jpg` and `.fig`.
- **Saved output (conditional):** If `SAVE_FFT_RAW` is true, saves a zoomed
  FFT peak plot of the **raw** current+voltage to
  `uz_folder/<base>_fft_raw.png` (+ `.fig`).

### 5.6 Impedance & phase computation
```matlab
[f_main, v1_main, i_amp_yes_dc_raw, i_amp_no_dc_raw, v1_amp_yes_dc_raw, ...
 v1_amp_no_dc_raw, Z1_mag_raw, Z1_phase_raw, Z1_peak_raw] = phase_shift_fft(voltage1, current, t);

[~, ~, i_amp_yes_dc_s, ..., Z1_mag_s, Z1_phase_s, Z1_peak_s] = phase_shift_fft(voltage1_s, current_s, t_s);
```
- **What it does:** Calls [`phase_shift_fft`](#phase_shift_fft) **twice** — once
  on the raw signals, once on the smoothed/trimmed signals — to compute FFT-based
  impedance magnitude (mΩ) and phase (deg) at the dominant frequency bin. Applies
  a polarity correction (phase sign flip, complex conjugate) for even-numbered
  channels (`mod(uz_num,2)==0`) to account for inverted probe wiring.
- **Outputs:** All of `f_main`, `v1_main`, amplitude summaries, `Z1_mag_raw/s`,
  `Z1_phase_raw/s`, `Z1_peak_raw/s` (complex impedance at peak bin) — packed into
  a `row` cell array and appended to `T_summary_data`.

### 5.7 Accumulate results
```matlab
processed_count = processed_count + 1;
all_freqs(processed_count) = main_freq;
... (etc for all_mag_Z1_raw, all_mag_Z1_s, all_phase_V1I_raw, all_phase_V1I_s,
     all_Z1_peak_raw, all_Z1_peak_s, T_summary_data)
```
- **What it does:** Stores this file's results into the per-channel accumulator
  arrays at the next available index. Arrays are later trimmed to
  `processed_count` in case some files were skipped due to errors.

---

## 6. Per-Channel Post-Processing

Runs once per channel, after all files for that channel have been processed.

### 6.1 Summary table & CSV export
- **What it does:** Builds a `T_summary` table (14 columns: frequencies,
  amplitudes with/without DC, raw/smoothed impedance & phase) from
  `T_summary_data`, renders it as a figure (`uitable`), and writes it to CSV.
- **Saved output:** `uz_folder/summary_table_figure.png`/`.fig`,
  `uz_folder/summary_table.csv`.

### 6.2 Frequency-group averaging (±5% tolerance)
- **What it does:** Groups all processed files by similar dominant frequency
  (within ±5%) and averages their magnitude/phase/complex-peak values within
  each group. This consolidates repeated measurements at (nominally) the same
  test frequency into a single data point.
- **Inputs:** `all_freqs`, `all_mag_Z1_raw/s`, `all_phase_V1I_raw/s`,
  `all_Z1_peak_raw/s` (per-file values).
- **Outputs:** `avg_freqs`, `avg_mag_Z1_raw/s`, `avg_ph_Z1_raw/s`,
  `avg_Zpk_Z1_raw/s` — these **overwrite** the `all_*` variables for use in the
  rest of the pipeline (Bode/Nyquist plots).

### 6.3 Bode plots (linear & log frequency scale)
- **What it does:** Plots impedance magnitude (left y-axis) and phase (right
  y-axis) vs. frequency, raw vs. smoothed overlaid, once with linear x-axis and
  once with logarithmic x-axis.
- **Saved output:** `uz_folder/bode_plot_linear.png`/`.fig`,
  `uz_folder/bode_plot_log.png`/`.fig`.

### 6.4 Nyquist plot
- **What it does:** Plots the complex impedance (Re(Z) vs. −Im(Z)) — one point
  per averaged frequency — for both raw and smoothed data. Also stores this
  channel's frequency/impedance/phase arrays into the persistent `combined`
  struct (`combined.(uz_label). ...`) for later use in the combined
  multi-channel plots.
- **Saved output:** `uz_folder/nyquist_plot.png`/`.fig`.

### 6.5 Additional summary tables (formatted display)
- **What it does:** Builds two side-by-side `uitable` figures (raw vs.
  smoothed) showing frequency/amplitude/impedance/phase, each value formatted
  to 6 decimal places.
- **Saved output:** `uz_folder/summary_data_tables.png`/`.fig`.

---

## 7. Combined Multi-Channel Plots

Runs once, after the outer channel loop finishes.

### 7.1 Combined Bode plots
- **What it does:** Overlays every channel's Bode data (magnitude + phase, raw
  + smoothed) on one figure, once linear and once log frequency scale. Adds
  interactive `uicontrol` checkboxes to toggle visibility of raw magnitude,
  smoothed magnitude, raw phase, smoothed phase lines independently.
- **Inputs:** `combined` struct (all channels).
- **Saved output:** `out_folder/combined_bode_linear.png`/`.fig`,
  `out_folder/combined_bode_log.png`/`.fig`.

### 7.2 Combined Nyquist plot
- **What it does:** Overlays every channel's Nyquist curve (raw + smoothed) on
  one figure, with checkboxes to toggle raw/smoothed visibility.
- **Saved output:** `out_folder/combined_nyquist.png`/`.fig`.

---

## 8. Function Reference

### `logical_to_vis(val)`
- **Purpose:** Tiny helper converting a boolean/`0`/`1` to the string `'on'`/`'off'`
  for use with `Visible` properties in checkbox callbacks.
- **Input:** `val` — logical or numeric 0/1.
- **Output:** `v` — `'on'` or `'off'`.

---

### `select_columns_gui` {#select_columns_gui}
```matlab
[selectedCols, selectedCurrentCol, shuntOhms, smoothMethod, zeroCrossTrim] = ...
    select_columns_gui(headerNames, presetVoltageCols, presetCurrentCol, ...
                        presetShuntOhms, presetSmoothMethod, presetZeroCrossTrim)
```
- **Purpose:** Renders an interactive `uifigure` dialog for the user to
  configure the run before processing begins.
- **GUI elements:**
  - Scrollable checkbox list — one checkbox per CSV column, pre-ticked per
    `presetVoltageCols`. User selects which columns are voltage channels.
  - Dropdown — selects the current/shunt column, pre-set to `presetCurrentCol`.
  - Numeric field — shunt resistance (Ohms), pre-filled with `presetShuntOhms`.
  - Dropdown — smoothing method (`4PSF` / `Moving Average` / `Savitzky-Golay` /
    `Low-pass Butterworth`), pre-set to `presetSmoothMethod`.
  - Checkbox — enable/disable zero-crossing cycle trim, pre-set to
    `presetZeroCrossTrim`.
  - OK button — confirms selections and closes the dialog (`uiwait`/`uiresume`).
- **Inputs:**
  | Name | Meaning |
  |---|---|
  | `headerNames` | String array of column labels (for checkbox/dropdown text). |
  | `presetVoltageCols` | Column indices pre-ticked as voltage channels. |
  | `presetCurrentCol` | Column index pre-selected as current/shunt. |
  | `presetShuntOhms` | Default shunt resistance value. |
  | `presetSmoothMethod` | Default smoothing method string. |
  | `presetZeroCrossTrim` | Default zero-crossing trim checkbox state. |
- **Outputs:**
  | Name | Meaning |
  |---|---|
  | `selectedCols` | Row vector of ticked voltage column indices. Empty if the user closed the window without pressing OK. |
  | `selectedCurrentCol` | Chosen current/shunt column index. |
  | `shuntOhms` | Chosen shunt resistance value. |
  | `smoothMethod` | Chosen smoothing method string. |
  | `zeroCrossTrim` | Chosen zero-crossing trim boolean. |
- **Fallback behavior:** If the user closes the dialog without pressing OK
  (`okPressed` stays `false`), all outputs fall back to the `preset*` input
  values, and `selectedCols` is returned empty (signaling the caller to exit).

---

### `apply_smoothing` {#apply_smoothing}
```matlab
[i_out, v1_out] = apply_smoothing(current, voltage1, t, f0_init, method)
```
- **Purpose:** Dispatcher — routes to the appropriate smoothing implementation
  based on the `method` string chosen in the GUI.
- **Inputs:** `current`, `voltage1` (raw signal vectors), `t` (time vector),
  `f0_init` (FFT-estimated fundamental frequency, used by some methods),
  `method` — one of `'4PSF'`, `'Moving Average'`, `'Savitzky-Golay'`,
  `'Low-pass Butterworth'`.
- **Outputs:** `i_out`, `v1_out` — smoothed current/voltage vectors.
- **Errors:** Throws if `method` doesn't match a known case.

#### `smooth_moving_average(current, voltage1, t, f0_init)`
- **Purpose:** Simple moving-average smoothing (`movmean`), with window size
  set to ~1/10th of one signal cycle (`Fs / f0_init / 10`, minimum 3 samples).
- **Inputs/Outputs:** Same shape as `apply_smoothing`.

#### `smooth_savgol(current, voltage1, t)`
- **Purpose:** Savitzky-Golay polynomial smoothing (`sgolayfilt`), fixed
  polynomial order 3, frame length 11. Requires Signal Processing Toolbox.
- **Inputs/Outputs:** Same shape as `apply_smoothing` (note: `t` unused inside
  but kept in the signature for interface consistency).

#### `smooth_butterworth(current, voltage1, t, f0_init)`
- **Purpose:** 4th-order low-pass Butterworth filter (`butter` + `filtfilt`,
  zero-phase). Cutoff frequency set to 5× the fundamental frequency
  (`f0_init * 5`), clamped below 90% of Nyquist. Requires Signal Processing
  Toolbox.
- **Inputs/Outputs:** Same shape as `apply_smoothing`.

> **Note:** Unlike 4PSF (which analytically reconstructs a clean sine wave),
> Moving Average / Savitzky-Golay / Butterworth smooth the *actual* noisy
> waveform — zero-crossing detection downstream (`extract_complete_cycles`) may
> behave differently (noisier) with these methods, especially at low SNR.

---

### `plot_fft_peak_pair` {#plot_fft_peak_pair}
```matlab
plot_fft_peak_pair(current_sig, voltage_sig, t, uz_label, pass_label, savepath, zoom_bins)
```
- **Purpose:** Creates and saves a 2-subplot figure (current FFT on top,
  voltage FFT below), each zoomed to a window around its detected FFT peak bin,
  with the peak circled.
- **Inputs:**
  | Name | Meaning |
  |---|---|
  | `current_sig`, `voltage_sig` | Signal vectors to analyze. |
  | `t` | Corresponding time vector. |
  | `uz_label` | Channel label, used in plot titles. |
  | `pass_label` | `'RAW'` or `'SMOOTHED'` — used in plot titles/figure name. |
  | `savepath` | Full path (including filename, `.png`) to save the figure. |
  | `zoom_bins` | Number of FFT bins to show on each side of the peak. |
- **Outputs:** None (writes files directly).
- **Saved output:** `savepath` (PNG) and a matching `.fig` (same name, `.fig`
  extension) saved alongside it. The figure is created with `Visible,'off'`
  during construction (to avoid flashing windows), then set back to
  `Visible,'on'` **before** `savefig` — otherwise the saved `.fig` file opens
  invisibly when double-clicked later.

#### `local_fft_amp(signal, t)`
- **Purpose:** Computes the one-sided FFT amplitude spectrum and finds the peak
  bin (ignoring DC).
- **Inputs:** `signal`, `t`.
- **Outputs:** `f` (frequency vector), `amp` (one-sided amplitude spectrum),
  `peak_idx` (index of peak bin, DC excluded), `bin_width` (`Fs/N`, the exact
  frequency resolution).

#### `zoom_and_stem(f, amp, peak_idx, zoom_bins, plot_title)`
- **Purpose:** Draws a stem plot zoomed to `±zoom_bins` around `peak_idx`, with
  the peak circled in red.
- **Inputs:** `f`, `amp` (from `local_fft_amp`), `peak_idx`, `zoom_bins`,
  `plot_title` (string).
- **Outputs:** None (draws into the current axes).

---

### `estimate_freq_amp(signal, t)`
- **Purpose:** Computes a one-sided FFT amplitude spectrum and returns the
  dominant (peak) frequency and amplitude. Used early in the pipeline purely
  for **file naming and initial frequency estimate** — not the same function
  used for final impedance calculation (`phase_shift_fft`).
- **Inputs:** `signal`, `t`.
- **Outputs:** `freq` (peak frequency, Hz), `amp` (peak amplitude).
- **Side effect:** Prints peak amplitude/frequency to the console via `fprintf`.

---

### `fit_reconstruct_4psf(current, voltage1, t, f0_init)` {#fit_reconstruct_4psf}
- **Purpose:** Four-Parameter Sine Fit (IEEE 1241 method) — fits
  `x(t) = A·cos(2πf₀t) + B·sin(2πf₀t) + C + D·t` to the current signal (DC
  offset `C` and linear drift `D` absorbed into the model), refines `f₀` via
  Gauss-Newton iteration, rejects transient/outlier samples (two-pass: initial
  6×MAD threshold, escalating to 8×/12×/20×MAD or longest-clean-block fallback
  if too few clean samples remain), then re-fits both current and voltage on
  the clean sample mask using the **same** refined frequency (so phase
  relationship between the two is preserved exactly). Reconstructs both signals
  analytically over the full original time axis — no filtering, no edge
  artifacts.
- **Inputs:** `current`, `voltage1` (raw), `t`, `f0_init` (FFT-estimated
  starting frequency).
- **Outputs:** `i_out`, `v1_out` — analytically reconstructed (smoothed)
  current/voltage.
- **Side effect:** Extensive `fprintf` diagnostics (refined frequency, %
  samples kept clean, fitted amplitude/phase, phase difference).

#### `refine_freq_gauss_newton(x, t, f0_init)`
- **Purpose:** Refines the fundamental frequency estimate via Gauss-Newton
  optimization (up to 20 iterations), minimizing 4-parameter sine-fit residual.
- **Inputs:** `x` (signal, typically current), `t`, `f0_init`.
- **Outputs:** `f1` — refined frequency (best cost achieved across iterations,
  bounded to `[0.5×f0_init, 2×f0_init]`).

#### `solve_4psf(x, t, f0)`
- **Purpose:** Solves the linear least-squares 4-parameter sine fit for a
  single signal at a fixed frequency `f0`.
- **Inputs:** `x` (signal), `t`, `f0`.
- **Outputs:** `A`, `B`, `C`, `D` — fitted coefficients (cosine amp, sine amp,
  DC offset, linear drift).

#### `fit_4psf_residual(x, t, f0)`
- **Purpose:** Computes the residual (`x - model`) of a 4PSF fit — used for
  outlier/transient detection.
- **Inputs/Outputs:** `x`, `t`, `f0` → `r` (residual vector).

#### `eval_4psf(t, A, B, C, D, f0)`
- **Purpose:** Evaluates the 4-parameter sine model at given coefficients over
  time vector `t`.
- **Inputs:** `t`, `A`, `B`, `C`, `D`, `f0`.
- **Outputs:** `y` — reconstructed signal.

---

### `phase_shift_fft(V1, I, t)` {#phase_shift_fft}
- **Purpose:** Core impedance/phase calculation. Computes FFT of both voltage
  and current, finds each one's dominant frequency bin, computes the complex
  impedance spectrum `Z1 = V1_fft ./ I_fft`, and extracts magnitude (mΩ) and
  phase (deg) at the dominant bin (indexed by current's peak, per
  `idx`/`f_main`).
- **Inputs:** `V1` (voltage signal), `I` (current signal), `t` (time vector).
  Called twice per file — once with raw signals, once with smoothed/trimmed.
- **Outputs:**
  | Name | Meaning |
  |---|---|
  | `f_main` | Dominant frequency from current spectrum (Hz). |
  | `v1_main` | Dominant frequency from voltage spectrum (Hz) — for cross-check. |
  | `i_amp_yes_dc`, `i_amp_no_dc` | Current amplitude, including/excluding DC bin. |
  | `v1_amp_yes_dc`, `v1_amp_no_dc` | Voltage amplitude, including/excluding DC bin. |
  | `Z1_mag` | Impedance magnitude at dominant bin, in **mΩ**. |
  | `Z1_phase_main` | Impedance phase at dominant bin, in **degrees**. |
  | `Z1_peak` | Complex impedance value at the dominant bin (Ohms, raw complex ratio) — used for Nyquist plots. |
- **Side effect:** Extensive `fprintf` diagnostics.

---

### `lockin_reconstruct(x, t, f0, Fs, ref_signal)`
- **Purpose:** Alternative smoothing approach (lock-in amplifier style
  demodulation) — **not currently wired into the main pipeline**
  (`apply_smoothing` does not call it). Demodulates a signal against a
  reference's phase at `f0`, low-passes via moving-average `filtfilt`, then
  reconstructs the AC fundamental and restores the DC offset.
- **Inputs:** `x` (signal to reconstruct), `t`, `f0` (target frequency), `Fs`
  (sample rate), `ref_signal` (reference signal whose phase is used for
  demodulation, typically current).
- **Outputs:** `y` — reconstructed signal.
- **Status:** Legacy/unused — kept in the file (marked `% ---- END ADD ----`)
  but no longer called by the main loop, which now uses `fit_reconstruct_4psf`
  (or the other `apply_smoothing` methods) instead.

---

### `extract_complete_cycles(current_s, voltage1_s)` {#extract_complete_cycles}
- **Purpose:** Trims the smoothed current/voltage signals down to only
  **complete cycles**, using current's zero-crossings (rising edge, relative to
  a robust mean computed from the middle 60% of the signal) as the reference
  clock. Drops "tiny" partial-cycle fragments at the start/end (< 20% of one
  estimated cycle length) to avoid FFT/impedance distortion from incomplete
  cycles; keeps "large" partial fragments as-is.
- **Inputs:** `current_s`, `voltage1_s` — smoothed signal vectors (from
  `apply_smoothing`).
- **Outputs:** `i_out`, `v1_out` — trimmed signal vectors; `idx_range` — the
  index range (into the input vectors) that was kept, used by the caller to
  also trim the corresponding time vector (`t_s = t(cycle_idx)`).
- **Fallback behavior:** If fewer than 3 zero-crossings are found, returns the
  original (untrimmed) signals with a warning. If the computed trim range is
  empty/invalid, also falls back to returning the original signals.
- **Side effect:** `fprintf`/`warning` diagnostics describing which
  fragments were kept/dropped and the final kept sample range.
- **Toggle:** Only called when `ZERO_CROSS_TRIM` (GUI checkbox) is `true`;
  otherwise the main loop skips this step entirely and uses the untrimmed
  smoothed signal directly.

---

## Data Flow Summary (per file, per channel)

```
CSV file
  │
  ▼
[Load & parse] ──► t, current (raw), voltage1 (raw)
  │
  ▼
[estimate_freq_amp] ──► freq_c (initial frequency estimate)
  │
  ▼
[Rename/copy CSV] ──► newname, base (used for all output filenames below)
  │
  ▼
[apply_smoothing] ──► current_s, voltage1_s  (method: 4PSF / MovAvg / SavGol / Butterworth)
  │
  ▼
[extract_complete_cycles]  (if ZERO_CROSS_TRIM)  ──► current_s, voltage1_s, t_s (trimmed)
  │
  ├──► [plot_fft_peak_pair] (SMOOTHED)  ──► <base>_fft_smoothed.png/.fig   (if SAVE_FFT_SM)
  │
  ▼
[Time-domain raw-vs-smoothed plot] ──► <base>_plot.jpg/.fig
  │
  ├──► [plot_fft_peak_pair] (RAW)  ──► <base>_fft_raw.png/.fig   (if SAVE_FFT_RAW)
  │
  ▼
[phase_shift_fft] × 2 (raw signals, smoothed signals)
  ──► Z1_mag_raw/s, Z1_phase_raw/s, Z1_peak_raw/s
  │
  ▼
[Accumulate into all_freqs / all_mag_Z1_* / all_phase_V1I_* / all_Z1_peak_* / T_summary_data]
```

After all files for a channel are processed:
```
[Summary table + CSV] → [±5% frequency-group averaging] → [Bode plots] → [Nyquist plot]
  → combined.(uz_label) populated for later combined multi-channel plots
```

After all channels are processed:
```
combined struct → [Combined Bode plots (linear+log)] → [Combined Nyquist plot]
```
