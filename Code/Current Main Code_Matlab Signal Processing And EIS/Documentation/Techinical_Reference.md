# Technical Reference

Complete technical reference for `EIS_data_processing_M_Haris_Naveed_V1.m` — every GUI element, function, constant, formula, and error-handling path in the script.

## Table of Contents

1. [Script Overview](#1-script-overview)
2. [File Structure & Execution Flow](#2-file-structure--execution-flow)
3. [GUI / UI Components](#3-gui--ui-components)
4. [Input Data Format (CSV)](#4-input-data-format-csv)
5. [Function-by-Function Reference](#5-function-by-function-reference)
6. [Filtering / Smoothing Methods](#6-filtering--smoothing-methods)
7. [Impedance & Phase Calculations](#7-impedance--phase-calculations)
8. [Plotting / Visualization Outputs](#8-plotting--visualization-outputs)
9. [Global / Shared Variables & State](#9-global--shared-variables--state)
10. [Constants & Configurable Parameters](#10-constants--configurable-parameters)
11. [Error Handling & Edge Cases](#11-error-handling--edge-cases)
12. [Open Questions / Ambiguities](#14-open-questions--ambiguities)

---

## 1. Script Overview

The script provides an automated, multi-channel batch-processing pipeline for EIS time-domain waveform data. It ingests CSV files containing current and voltage recordings, estimates signal frequencies via FFT, applies configurable signal smoothing/reconstruction, trims incomplete cycles, and computes fundamental-frequency impedance magnitude, phase shift, and complex impedance. It produces renamed/archived source files, individual and combined Bode/Nyquist plots, FFT zoom plots, interactive figure tables, and CSV summary tables.

**Toolbox dependencies (inferred):**
- Signal Processing Toolbox — `filtfilt`, `butter`, `sgolayfilt`, `fft`, `movmean`
- App Designer / UI Components — `uifigure`, `uipanel`, `uicheckbox`, `uidropdown`, `uieditfield`, `uibutton`

**MATLAB version:** R2019b+ recommended (App Designer UI components, string arrays, `readtable`/`detectImportOptions`, cell-array conversions).

---

## 2. File Structure & Execution Flow

```
[Startup — run once]
  ├── UI folder picker (uigetdir)
  ├── Output directory creation ('solution' or 'solution_<timestamp>')
  ├── Parse column header names from row 5 of the first CSV
  └── Column Selection GUI (select_columns_gui)

[Outer loop — for each selected voltage channel]
  ├── Reset per-channel preallocations
  │
  ├── [Inner loop — for each CSV file in folder]
  │     ├── Import data + datetime metadata (readtable, detectImportOptions)
  │     ├── Compute current (V_shunt / -R_shunt), extract voltage
  │     ├── Estimate fundamental frequency (FFT) — estimate_freq_amp
  │     ├── Rename/archive file into channel subfolder (first channel pass only)
  │     ├── Smooth signal — apply_smoothing (4PSF / MovAvg / SavGol / Butterworth)
  │     ├── Trim zero-crossing fragments — extract_complete_cycles [optional]
  │     ├── FFT peak zoom plots [optional] — plot_fft_peak_pair
  │     ├── Time-domain waveform plot (JPG + FIG)
  │     ├── Impedance & phase via FFT — phase_shift_fft (raw and smoothed)
  │     ├── Probe polarity correction for even channels (Uz2, Uz4, …)
  │     └── Accumulate results into per-channel arrays
  │
  ├── Channel summary table (CSV + FIG)
  ├── Group & average spectral points within ±5% frequency band
  ├── Single-channel Bode plots (linear + log frequency)
  ├── Single-channel Nyquist plot
  └── Single-channel summary data tables (raw vs. smoothed)

[Aggregation — run once, after all channels]
  ├── Combined multi-channel Bode plots (interactive checkboxes, linear + log)
  └── Combined multi-channel Nyquist plot (interactive checkboxes)
```

**Run once at startup:** folder pickers, output folder init, header inspection, column-selection GUI, combined aggregation plots.

**Run repeatedly inside loops:** CSV loading, signal conversion, smoothing, cycle trimming, FFT phase-shift calculation, single-channel figure generation, file writing.

**Callback / event-driven:**
- `okCallback` — fired by the "OK" button in `select_columns_gui`; resumes main script via `uiresume`.
- Anonymous checkbox callbacks on combined Bode/Nyquist figures — toggle line visibility for "Show Raw" / "Show Smoothed" traces.

---

## 3. GUI / UI Components

### `select_columns_gui` (`uifigure`)

- **Title:** "Select Columns"
- **Size:** 460 × figH px, where `figH = min(max(290 + 22*nCols, 500), 800)`

| Element | Type | Purpose | Options | Default |
|---|---|---|---|---|
| Voltage column checkboxes | `uicheckbox` array | Select which voltage channels to analyze | One per header column (row 5 names) | Ticked per `PRESET_VOLTAGE_COLS` (e.g. `[3 4 5 6 7]`) |
| Current/Shunt dropdown | `uidropdown` | Select which column is the shunt voltage | Formatted "index: name" strings | `PRESET_CURRENT_COL` (e.g. col 2) |
| Shunt resistance field | `uieditfield` (numeric) | Shunt resistance in Ω, for `I = V/-R` | Limits `[eps, Inf]` | `PRESET_SHUNT_OHMS` (0.0075) |
| Smoothing method dropdown | `uidropdown` | Signal conditioning algorithm | `4PSF`, `Moving Average`, `Savitzky-Golay`, `Low-pass Butterworth` | `PRESET_SMOOTH_METHOD` |
| Zero-crossing trim checkbox | `uicheckbox` | Enable/disable cycle trimming | on/off | `PRESET_ZERO_CROSS_TRIM` (true) |
| OK button | `uibutton` | Confirm settings, resume script | — | callback: `okCallback` |

None of the individual GUI elements have live callbacks — state is read in bulk only when **OK** is pressed.

### Combined-figure checkboxes (`uicontrol`)

Created dynamically on the combined Bode and combined Nyquist figures:
- Style: `checkbox`, binary value (0/1, default 1)
- Callback: `@(src,~) set(targetLines, 'Visible', logical_to_vis(src.Value))`
- Purpose: toggle visibility of raw/smoothed magnitude/phase (Bode) or raw/smoothed curve (Nyquist) line objects without regenerating the plot.

---

## 4. Input Data Format (CSV)

### Structure

| Location | Content |
|---|---|
| Row 5 | Trace/header names — parsed via `readcell(file, 'Range', '5:5')`, used to label GUI checkboxes |
| Row 14 | Date string, e.g. `"2025/07/30"` |
| Row 15 | Time string, e.g. `"13:52:25.87803125"` |
| Row 16+ | Numeric time-series data, comma-delimited |

### Column mapping

| Column | Content |
|---|---|
| 1 | Time `t` — `duration`, `datetime`, or numeric seconds |
| 2 (default) | `V_shunt` — voltage drop across shunt resistor (V) |
| 3…N | Individual voltage channels `Uz1 … Uz(N-2)` |

### Physical conversion

```
I(t) = V_shunt(t) / -R_shunt
```

### Validation & error handling

- Rows where columns 1–4 are entirely `NaN` are dropped.
- A file is skipped (with a `warning`) if time, current, or the active voltage channel contains `NaN`s, is empty, or has fewer than 10 samples.
- If CSV date/time metadata extraction fails, falls back to the file system's save date (`dir(...).datenum`).

### Assumption

All CSV files in the selected folder are assumed to share **identical column layout**. There is no per-file re-validation of column identity — this is the single biggest correctness risk in a mixed-batch run (see [§14](#14-open-questions--ambiguities)).

---

## 5. Function-by-Function Reference

### `logical_to_vis(val)`
Converts a boolean to a MATLAB visibility string.
- **In:** `val` (logical)
- **Out:** `v` — `'on'` or `'off'`
- **Called by:** combined-plot checkbox callbacks.

---

### `select_columns_gui(headerNames, presetVoltageCols, presetCurrentCol, presetShuntOhms, presetSmoothMethod, presetZeroCrossTrim)`
Displays the modal App Designer channel/parameter selection window.
- **In:** `headerNames` (1×N string), `presetVoltageCols` (double array), `presetCurrentCol` (double), `presetShuntOhms` (double), `presetSmoothMethod` (char/string), `presetZeroCrossTrim` (logical)
- **Out:** `selectedCols` (1×M double), `selectedCurrentCol` (double), `shuntOhms` (double), `smoothMethod` (string), `zeroCrossTrim` (logical)
- **Logic:** builds a scrollable `uipanel` of checkboxes + dropdowns/fields → blocks on `uiwait(fig)` until `okCallback` calls `uiresume(fig)` or the user closes the window → reads field states (dropdown parsed with `sscanf`) → closes figure → returns values.
- **Called by:** main script (startup).

---

### `apply_smoothing(current, voltage1, t, f0_init, method)`
Dispatches to the selected smoothing algorithm.
- **In:** `current`, `voltage1`, `t` (double vectors), `f0_init` (Hz), `method` (string)
- **Out:** `i_out`, `v1_out` (double vectors)
- **Logic:** `switch(method)` → `fit_reconstruct_4psf` | `smooth_moving_average` | `smooth_savgol` | `smooth_butterworth`
- **Called by:** main per-file processing loop.

---

### `smooth_moving_average(current, voltage1, t, f0_init)`
- **Logic:** `Fs = 1/mean(diff(t))`; `win = max(3, round(Fs / f0_init / 10))`; applies `movmean` to both signals.
- **Calls:** `mean`, `diff`, `round`, `movmean`.

---

### `smooth_savgol(current, voltage1, t)`
- **Logic:** `sgolayfilt` with polynomial order 3, frame length 11, applied to both signals.
- **Calls:** `sgolayfilt`.

---

### `smooth_butterworth(current, voltage1, t, f0_init)`
- **Logic:** `Fs = 1/mean(diff(t))`; cutoff `= min(5*f0_init, 0.9*(Fs/2))`; 4th-order low-pass via `butter(4, cutoff/(Fs/2), 'low')`; zero-phase filtering via `filtfilt`.
- **Calls:** `mean`, `diff`, `min`, `butter`, `filtfilt`.

---

### `plot_fft_peak_pair(current_sig, voltage_sig, t, uz_label, pass_label, savepath, zoom_bins)`
Generates a 2-subplot zoomed FFT peak figure (current + voltage) and saves it.
- **In:** signals + time, `uz_label` (e.g. `'Uz1'`), `pass_label` (`'RAW'`/`'SMOOTHED'`), `savepath`, `zoom_bins`
- **Out:** none (writes files)
- **Logic:** computes spectrum via `local_fft_amp`, plots via `zoom_and_stem`, saves `.png` + `.fig`.
- **Calls:** `figure`, `subplot`, `local_fft_amp`, `zoom_and_stem`, `sgtitle`, `saveas`, `savefig`, `close`.

---

### `local_fft_amp(signal, t)`
Single-sided FFT amplitude spectrum + non-DC peak location.
- **Out:** `f` (freq vector), `amp` (amplitude vector), `peak_idx`, `bin_width`
- **Logic:** removes DC (`signal - mean(signal)`) → `fft` → positive-frequency axis up to `Fs/2` → scale by `1/N`, double non-DC bins → find max starting from bin 2.

---

### `zoom_and_stem(f, amp, peak_idx, zoom_bins, plot_title)`
Plots a stem graph zoomed around a peak bin.
- **Logic:** restricts range to `[peak_idx - zoom_bins, peak_idx + zoom_bins]`, overlays a red circle on the peak.
- **Calls:** `stem`, `plot`, `xlim`, `title`, `legend`, `grid`.

---

### `estimate_freq_amp(signal, t)`
Dominant frequency + peak amplitude via FFT.
- **Out:** `freq` (Hz), `amp`
- **Logic:** mean-subtracted FFT → normalize positive-frequency bins → locate max → return corresponding frequency/amplitude. Prints results to console.

---

### `fit_reconstruct_4psf(current, voltage1, t, f0_init)`
IEEE 1241 **Four-Parameter Sine Fit** with two-pass outlier rejection.
- **Out:** `i_out`, `v1_out` — reconstructed (noise-free) time series
- **Logic:**
  1. Refine `f0` via `refine_freq_gauss_newton` (on current).
  2. Pass 1: solve 4PSF on current, compute residuals and MAD.
  3. Flag outliers where residual `> 6×MAD`; if too few clean samples remain (< 3 cycles or < 30% of length), progressively relax to `8×, 12×, 20×` MAD, or fall back to the longest contiguous valid block.
  4. Pass 2: solve 4PSF (`solve_4psf`) on both signals using only valid samples.
  5. Evaluate the clean analytical model across the **full** time vector via `eval_4psf`.
- **Calls:** `refine_freq_gauss_newton`, `fit_4psf_residual`, `solve_4psf`, `eval_4psf`, plus standard MATLAB math/statistics functions.
- **Side effects:** prints fit parameters and phase delta to console.

---

### `refine_freq_gauss_newton(x, t, f0_init)`
Refines the FFT frequency estimate via Gauss-Newton nonlinear least squares (IEEE 1241 Annex B).
- **Out:** `f1` — refined frequency (Hz)
- **Logic:** normalizes time to start at 0; iterates up to 20 steps — builds design matrix `D = [cos(ωt), sin(ωt), 1, t]`, solves linear params via `D\x`, computes Jacobian w.r.t. frequency, step `d_f = Jᵀr / (JᵀJ + 1e-10)` capped to 10% of `f0`, updates frequency, breaks early if `|d_f| < 1e-7`.

---

### `solve_4psf(x, t, f0)`
Linear least-squares solve for the four sine parameters at fixed `f0`.
- **Out:** `A` (cos coeff), `B` (sin coeff), `C` (DC offset), `D` (linear drift)
- **Logic:** `M = [cos(2πf0·t), sin(2πf0·t), 1, t]`; `cf = M\x`.

---

### `fit_4psf_residual(x, t, f0)`
- **Out:** `r` — residual vector `x - y_fit`
- **Calls:** `solve_4psf`, `eval_4psf`.

---

### `eval_4psf(t, A, B, C, D, f0)`
Evaluates the 4PSF model.
```
y(t) = A·cos(2π f0 t) + B·sin(2π f0 t) + C + D·t
```

---

### `phase_shift_fft(V1, I, t)`
Core impedance/phase calculation — the single most important function in the script.
- **Out:** `f_main`, `v1_main` (dominant frequencies), `i_amp_yes_dc`/`i_amp_no_dc`, `v1_amp_yes_dc`/`v1_amp_no_dc`, `Z1_mag` (mΩ), `Z1_phase_main` (deg), `Z1_peak` (complex Ω)
- **Logic:**
  1. FFT of `I` and `V1`.
  2. Normalize one-sided spectrum (÷N, ×2 for non-DC/non-Nyquist bins).
  3. Locate dominant bin from the current spectrum (excluding DC).
  4. `Z1(f) = V1(f) ./ I(f)` — complex spectrum.
  5. Extract `Z1_peak = Z1(idx)`; `Z1_mag = |Z1_peak| × 1000` (Ω → mΩ); `Z1_phase_main = rad2deg(angle(Z1_peak))`.
- **Called by:** main loop, twice per file (once raw, once smoothed).
- **Side effects:** prints amplitude/frequency/impedance/phase to console.

---

### `lockin_reconstruct(x, t, f0, Fs, ref_signal)` — ⚠️ unused
Alternative lock-in-amplifier-style demodulation/reconstruction.
- **Logic:** extracts reference phase from `fft(ref_signal)`, demodulates with in-phase/quadrature references, low-passes with a single-cycle moving-average `filtfilt`, reconstructs.
- **Status:** defined but never called by `apply_smoothing` or anywhere else — dead code, available for manual wiring as a 5th smoothing option.

---

### `extract_complete_cycles(current_s, voltage1_s)`
Trims partial sine cycles at the start/end of a signal.
- **Out:** `i_out`, `v1_out` (trimmed), `idx_range` (kept indices)
- **Logic:**
  1. Center current using the mean over the central 20–80% window.
  2. Find upward zero-crossings (`I(t)<0 & I(t+1)>=0`).
  3. Estimate cycle length `= mean(diff(crossings))`.
  4. If the leading/trailing fragment is `< 20%` of a cycle, drop it (move to next/previous crossing); otherwise keep it.
  5. Return the sliced signals.
- **Called by:** main loop (optional, gated by `ZERO_CROSS_TRIM`).
- **Side effects:** prints trim decisions to console.

---

## 6. Filtering / Smoothing Methods

| Method | Function | Key parameters | Applied to |
|---|---|---|---|
| **4PSF** (IEEE 1241 sine fit) | `fit_reconstruct_4psf` | `f0` (refined via Gauss-Newton); outlier MAD threshold 6× (relaxed to 8/12/20× if needed); min clean-sample threshold | `current`, `voltage1` |
| **Moving Average** | `smooth_moving_average` | window `= max(3, round(Fs/f0/10))` | `current`, `voltage1` |
| **Savitzky-Golay** | `smooth_savgol` | polynomial order 3, frame length 11 | `current`, `voltage1` |
| **Low-pass Butterworth** | `smooth_butterworth` | order 4, cutoff `= min(5·f0, 0.9·Fs/2)`, zero-phase (`filtfilt`) | `current`, `voltage1` |
| **Lock-in reconstruction** *(unused)* | `lockin_reconstruct` | `f0`, 1-cycle moving-average low-pass | dead code |

See [Theory & Background](THEORY.md#smoothing--reconstruction-methods) for the reasoning behind each method and when to choose it.

---

## 7. Impedance & Phase Calculations

```
I(f)  = FFT(I(t))
V1(f) = FFT(V1(t))

Z1(f) = V1(f) / I(f)                          [Ω]

|Z1|  = |Z1(f_main)| × 1000                   [mΩ]
θ     = rad2deg(angle(Z1(f_main)))            [degrees]

Nyquist components:
  Re(Z1(f_main))                              [Ω]
 -Im(Z1(f_main))                               [Ω]
```

**Probe polarity correction** — applied to even-numbered channels (`mod(uz_num,2)==0`, i.e. `Uz2`, `Uz4`, …):

```
θ_corrected        = -θ
Z_peak_corrected    = conj(Z_peak)
```

**Frequency grouping/averaging:** spectral points from different files are grouped when within **±5%** of a reference frequency (`f_ref × [0.95, 1.05]`) and averaged.

**Units:** current and voltage in A/V; impedance magnitude reported in **mΩ** (multiplied ×1000 from base Ω); phase in degrees.

---

## 8. Plotting / Visualization Outputs

| Plot | Axes | Generated | Saved as |
|---|---|---|---|
| FFT peak zoom | Current amp vs Hz (top), Voltage amp vs Hz (bottom), linear | Per file, if `SAVE_FFT_RAW`/`SAVE_FFT_SM` | `_fft_raw.png/.fig`, `_fft_smoothed.png/.fig` |
| Time-domain waveform | Current vs t (top), Voltage vs t (bottom) | Per file, always | `[base]_plot.jpg/.fig` |
| Single-channel Bode (linear/log) | Left Y: \|Z1\| (mΩ); Right Y: Phase (deg); X: Hz | Per channel, after file loop | `bode_plot_linear.png/.fig`, `bode_plot_log.png/.fig` |
| Single-channel Nyquist | X: Re(Z) (Ω); Y: −Im(Z) (Ω); `axis equal` | Per channel | `nyquist_plot.png/.fig` |
| Combined multi-channel Bode | Same as above, all channels overlaid, 4 toggle checkboxes (raw mag/smooth mag/raw phase/smooth phase) | Once, after all channels | `combined_bode_linear.png/.fig`, `combined_bode_log.png/.fig` |
| Combined multi-channel Nyquist | Same as single-channel, all channels overlaid, raw/smoothed toggles | Once | `combined_nyquist.png/.fig` |
| Summary table figures | Rendered `uitable` of numeric results | Per channel | `summary_table_figure.png/.fig`, `summary_data_tables.png/.fig` |

---

## 9. Global / Shared Variables & State

| Variable | Purpose | Scope |
|---|---|---|
| `combined` (struct) | Accumulates per-channel results (`freqs`, `mag_raw`, `mag_s`, `phase_raw`, `phase_s`, `Zpeak_raw`, `Zpeak_s`) across the outer loop for final combined plots | Written per channel iteration; read once at the end |
| `col_list`, `current_col_idx`, `shunt_ohms`, `SMOOTH_METHOD`, `ZERO_CROSS_TRIM` | User's GUI selections | Written once by `select_columns_gui`; read throughout |
| `all_freqs`, `all_mag_Z1_raw`, `all_mag_Z1_s`, `all_phase_V1I_raw`, `all_phase_V1I_s`, `all_Z1_peak_raw`, `all_Z1_peak_s` | Per-channel, per-file accumulation arrays | Preallocated/reset each outer-loop iteration; populated per file; consumed by grouping/plotting |

---

## 10. Constants & Configurable Parameters

| Constant | Value | Location | Purpose |
|---|---|---|---|
| `SAVE_FFT_RAW` | `true` | Top toggle section | Save raw-signal FFT zoom plots |
| `SAVE_FFT_SM` | `true` | Top toggle section | Save smoothed-signal FFT zoom plots |
| `FFT_ZOOM_BINS` | `20` | Top toggle section | Bins either side of peak shown in zoom plot |
| `PRESET_VOLTAGE_COLS` | `[3 4 5 6 7]` | Top preset section | Default GUI-ticked voltage columns |
| `PRESET_CURRENT_COL` | `2` | Top preset section | Default shunt/current column |
| `PRESET_SHUNT_OHMS` | `0.0075` | Top preset section | Default shunt resistance (Ω) |
| `PRESET_SMOOTH_METHOD` | `'4PSF'` | Top preset section | Default smoothing method |
| `PRESET_ZERO_CROSS_TRIM` | `true` | Top preset section | Default cycle-trim toggle |
| `tol` | `0.05` | Frequency-averaging section | ±5% frequency grouping tolerance |
| Outlier MAD multiplier | `6.0` (relaxed to 8/12/20) | `fit_reconstruct_4psf` | Residual threshold for 4PSF outlier rejection |

---

## 11. Error Handling & Edge Cases

**Implementation:**
- The per-file loop body is wrapped in `try/catch ME`; on error, a `warning` reports the filename and error text, and processing continues with the next file.
- `uigetdir` cancellation returns cleanly (`disp` + `return`).
- No CSV files found → `error('No CSV files found...')`, halting execution.
- No voltage channels selected in the GUI → script exits cleanly.

**Handled edge cases:**
- Rows with `NaN` across columns 1–4 are stripped before processing.
- Files with non-numeric/`NaN` signals, or fewer than 10 samples, are skipped with a warning.
- Missing/malformed datetime header → falls back to filesystem save date.
- Fewer than 3 zero-crossings → `extract_complete_cycles` warns and returns the original, untrimmed signal.
- 4PSF outlier rejection failure → progressively relaxed MAD thresholds, then falls back to the longest contiguous clean block or the middle 70% of the data.

**Known gaps (not handled):**
- No per-file column-layout validation — if CSVs in the same batch have different column orders, the wrong data will silently be read into the wrong channel.
- Extremely noisy current signals can produce false zero-crossings, corrupting cycle-boundary detection in `extract_complete_cycles`.

---

## 12. Theory / Background Hooks

See the dedicated [Theory & Background](THEORY.md) document for full explanations of:
- Electrochemical Impedance Spectroscopy (EIS)
- Bode and Nyquist plots
- The Four-Parameter Sine Fit (IEEE 1241)
- Shunt-resistor current measurement
- Probe polarity inversion and why even channels are corrected

---

## 14. Open Questions / Ambiguities

- **Dead code:** `lockin_reconstruct` is fully implemented but never called.
- **Dead variable:** `final_amp = median([amp_c, amp_v1])` is computed but explicitly marked `%usless btw` in the source — not used downstream.
- **Commented-out code:** time-vector trimming block, single-sided FFT plotting inside `estimate_freq_amp`, and low/high-frequency directional arrow annotations on Nyquist plots are all present but disabled.
- **Channel-label edge case:** `uz_num = col_idx - 2`. Selecting column 1 or 2 as a "voltage channel" in the GUI produces `Uz-1` / `Uz0` — not validated against.
- **Hardcoded polarity assumption:** every even-numbered channel (`mod(uz_num,2)==0`) is assumed to have inverted probe polarity. This is a hardware-wiring assumption baked into the code, not detected automatically.
- **Shunt sign convention:** `current = v_shunt / -shunt_ohms` — the hardcoded negative sign assumes a specific differential wiring polarity on the shunt. Verify against your hardware before trusting the sign of computed current/phase.

Treat all of the above as things to **verify against your specific hardware setup** before relying on absolute phase sign or channel numbering.
