===========================================================================================
<Here's what your full code does, end-to-end:

1. Folder & File Selection

User selects a folder containing CSV waveform files from a scope recorder.

Loops through every .csv file.

2. File Reading & Cleaning

Reads each CSV, skipping 15 header lines.

Removes rows where first 4 columns are NaN.

Extracts timestamp from header lines 14–15 (date + time).

Converts time column to numeric seconds.

3. Signal Extraction

Col 1: Time

Col 2: Shunt voltage → converts to current via I = Vshunt / 0.0075 (7.5 mΩ shunt)

Col 3: Voltage 1 (Uz1)

Col 4: Voltage 2 (Uz2)

Cols 5–7: Ignored.

4. Frequency Estimation

Runs FFT on current, V1, V2.

Finds peak frequency (dominant AC frequency).

Renames file with datetime + frequency: Waveform_20260212_110243_100Hz.csv

5. Signal Smoothing

Low-pass Butterworth filter (4th order, cutoff = 5× dominant frequency).

Creates smoothed versions: current_s, voltage1_s, voltage2_s.

6. Plotting (per file)

3-panel time-domain plot: Current, V1, V2 (raw + smoothed).

6-panel FFT amplitude spectrum (raw + smoothed for I, V1, V2).

Saves plot as JPG.

7. Impedance Calculation (per file)

Computes complex impedance: Z1 = V1_fft / I_fft, Z2 = V2_fft / I_fft.

At the dominant frequency, extracts:

Magnitude (mΩ)

Phase (degrees)

Complex peak (real + imag)

Does this for both raw and smoothed signals.

Stores all results.

8. Summary Table (per-file)

Saves per-file metrics to a growing table: frequency, amplitudes (with/without DC), impedance magnitude, phase.

Exports final summary_table.csv.

9. Final Combined Bode Plot

Sorts all files by frequency.

Plots Z1 and Z2 magnitude + phase vs frequency (log x-axis).

Dual Y-axis: linear impedance + phase.

Toggle checkboxes to switch between linear and symlog y-scaling.

Overlapping axes for clean switching.

10. Nyquist Plot

Plots -Imag(Z) vs Real(Z) in mΩ for Z1 and Z2.

Both raw and smoothed peak points across all frequencies.

11. Final Summary Tables (UI)

Two side-by-side tables: raw vs smoothed.

Columns: frequency, amplitude, Z1/Z2 impedance, Z1/Z2 phase.

In short: This takes EIS waveform files from a scope, extracts current + two voltages, computes FFT-based impedance at the dominant frequency, and compiles Bode + Nyquist plots across all frequencies. Channels 4–6 are never used.
>
====================================================================

