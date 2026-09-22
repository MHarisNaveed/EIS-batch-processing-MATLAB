# Theory & Background

This document explains the electrochemical and signal-processing concepts behind the script, for readers who need the "why" behind the math in the [API Reference](API_REFERENCE.md).

## Table of Contents

- [Electrochemical Impedance Spectroscopy (EIS)](#electrochemical-impedance-spectroscopy-eis)
- [Impedance as a complex number](#impedance-as-a-complex-number)
- [Bode plots](#bode-plots)
- [Nyquist plots](#nyquist-plots)
- [How this script measures impedance](#how-this-script-measures-impedance)
- [Shunt-resistor current measurement](#shunt-resistor-current-measurement)
- [Smoothing / reconstruction methods](#smoothing--reconstruction-methods)
- [The Four-Parameter Sine Fit (IEEE 1241)](#the-four-parameter-sine-fit-ieee-1241)
- [Probe polarity inversion](#probe-polarity-inversion)
- [Cycle trimming](#cycle-trimming)

---

## Electrochemical Impedance Spectroscopy (EIS)

EIS characterizes an electrochemical system (a battery cell, fuel cell, or similar) by applying a small AC current or voltage perturbation at a range of frequencies and measuring the resulting voltage/current response. The ratio of the response to the excitation, at each frequency, is the **impedance** — a complex number that captures both how much the system resists current flow (magnitude) and how much it shifts the phase between voltage and current (phase angle).

Unlike a simple DC resistance measurement, impedance varies with frequency because electrochemical systems combine resistive, capacitive, and diffusive behaviors — charge-transfer resistance, double-layer capacitance, mass-transport (Warburg) effects — each of which dominates in a different frequency range. Sweeping frequency and recording the impedance at each point produces a **spectrum** that can be used to diagnose cell health, internal resistance, and degradation mechanisms.

This script performs the measurement half of EIS: given time-domain current and voltage recordings at a series of discrete excitation frequencies (one CSV file per frequency, typically), it extracts the impedance and phase at each frequency and assembles the spectrum.

## Impedance as a complex number

At a given frequency, if `V(f)` and `I(f)` are the complex Fourier components of the voltage and current signals, impedance is:

```
Z(f) = V(f) / I(f)  =  Z' + j·Z''
```

where `Z'` is the real (resistive) part and `Z''` is the imaginary (reactive) part. Equivalently, in polar form:

```
Z(f) = |Z(f)| · e^(jθ)
```

- `|Z(f)|` — impedance magnitude (Ω), how much the system opposes current flow at that frequency.
- `θ = angle(Z(f))` — phase angle (degrees), how much the current lags or leads the voltage.

This script computes exactly this: `phase_shift_fft` takes the FFT of both signals, forms `Z(f) = V(f)/I(f)` at the dominant excitation bin, and reports `|Z|` (converted to mΩ) and `θ` (degrees).

## Bode plots

A Bode plot displays impedance magnitude and phase **as functions of frequency**, typically as two stacked subplots (or one plot with dual Y-axes), with frequency on a log or linear X-axis. It's the natural way to see how a system's behavior changes across the frequency range — e.g., a system that looks resistive (flat magnitude, ~0° phase) at low frequency but capacitive (falling magnitude, phase approaching −90°) at high frequency.

This script generates both **linear** and **log**-frequency Bode plots per channel, plus a combined version overlaying every selected channel with interactive show/hide toggles for raw vs. smoothed traces.

## Nyquist plots

A Nyquist plot is a parametric plot of `−Z''` (negative imaginary impedance) against `Z'` (real impedance), with each point corresponding to one measurement frequency (frequency itself is not shown on an axis — it's implicit in the point's position along the curve). The negative sign on the imaginary axis is a long-standing electrochemistry convention: it puts capacitive behavior (negative `Z''` in the underlying math) in the upper half-plane, so most electrochemical systems trace an arc that opens upward.

The shape of the Nyquist arc — semicircle diameter, high-frequency intercept, low-frequency tail — is used to estimate equivalent-circuit parameters like ohmic resistance, charge-transfer resistance, and Warburg diffusion behavior, though this script does not itself perform equivalent-circuit fitting; it produces the raw spectrum that such fitting would consume.

## How this script measures impedance

Rather than a continuous frequency sweep from a dedicated EIS instrument, this pipeline assumes **one CSV file per excitation frequency**: the voltage and current are captured as time-domain waveforms at each discrete test frequency, and the script:

1. Estimates that frequency from the data itself (`estimate_freq_amp`, via FFT peak-finding) rather than trusting metadata.
2. Extracts the complex `V(f)` and `I(f)` at that bin.
3. Computes `Z(f) = V(f)/I(f)`.
4. Repeats across files/frequencies, then assembles a spectrum sorted by frequency, grouping files within ±5% of the same nominal frequency and averaging them (some test rigs re-run the same nominal frequency multiple times, or drift slightly run-to-run).

## Shunt-resistor current measurement

Current isn't measured directly — it's inferred from the voltage drop across a known shunt resistor, via Ohm's law:

```
I(t) = V_shunt(t) / (−R_shunt)
```

The negative sign accounts for the differential wiring polarity of the shunt in this specific hardware setup — with the shunt wired the other way, the sign would flip. If your measured current appears inverted relative to expectations, this is the first place to check (see [API Reference §14](API_REFERENCE.md#14-open-questions--ambiguities)).

## Smoothing / reconstruction methods

Raw oscilloscope/DAQ captures carry measurement noise that can bias the FFT-derived amplitude and phase, especially at low signal-to-noise ratios. The script offers four approaches, each with different tradeoffs:

| Method | What it does | Best suited for |
|---|---|---|
| **4PSF** | Fits an analytical sine model (amplitude, phase, DC offset, linear drift) via least squares, with two-pass outlier rejection, then evaluates the clean model over the full time range | Cleanest possible reconstruction when the signal is a genuine single-tone sinusoid; most robust to isolated glitches/spikes |
| **Moving Average** | Simple boxcar smoothing, window scaled to ~1/10 of a cycle | Fast, simple noise reduction when signal shape doesn't need to be perfectly preserved |
| **Savitzky-Golay** | Local polynomial (order 3, 11-point frame) fit | Preserves peak shape/curvature better than a moving average while still smoothing noise |
| **Butterworth low-pass** | 4th-order zero-phase (`filtfilt`) low-pass, cutoff at 5× the fundamental | Removes harmonics/high-frequency noise while avoiding phase distortion (zero-phase filtering) |

Because impedance phase is sensitive to any time-shift introduced by filtering, all four methods are chosen specifically for being (or approximating) **zero-phase** — `filtfilt` explicitly avoids phase lag, and 4PSF reconstructs an idealized sine wave with an explicitly fitted phase rather than a filtered/delayed one.

## The Four-Parameter Sine Fit (IEEE 1241)

4PSF is a standardized least-squares method (from IEEE Std 1241, Annex B, for characterizing ADCs and other measurement systems) for fitting a single sinusoid plus offset and linear drift to noisy data:

```
y(t) = A·cos(2π f0 t) + B·sin(2π f0 t) + C + D·t
```

- `A`, `B` — in-phase and quadrature amplitude coefficients (amplitude = `√(A²+B²)`, phase = `atan2(B,A)`)
- `C` — DC offset
- `D` — linear drift term, to absorb slow baseline drift unrelated to the AC signal

Because the model is linear in `A, B, C, D` for a *fixed* frequency `f0`, it's solved with a simple linear least-squares solve (`M \ x`). The frequency itself is *not* linear in the model, so it's refined separately via Gauss-Newton nonlinear least squares (`refine_freq_gauss_newton`) before the final linear solve.

This script adds a **two-pass outlier-rejection** step on top of the standard 4PSF: it fits once, computes residuals, flags points more than 6× the median absolute deviation (MAD) away as outliers, and re-fits using only the clean points — with several fallback thresholds if too few points survive. This makes the fit substantially more robust to transient glitches (e.g., a single corrupted sample) than a naive one-pass fit.

## Probe polarity inversion

In a multi-channel test rig measuring several voltage taps against a common reference, physical probe wiring can differ by channel — some channels may be wired with reversed polarity relative to others, which flips the sign of the measured phase and conjugates the complex impedance. The script hardcodes a fix for this: **even-numbered channels** (`Uz2`, `Uz4`, `Uz6`, …) have their phase negated and their complex impedance conjugated:

```
θ_corrected      = −θ
Z_peak_corrected = conj(Z_peak)
```

This is a **hardware-specific assumption**, not something derived from the data — it assumes a specific, consistent wiring pattern across the test rig. If your setup wires channels differently, this correction will need to be adjusted or removed (see [API Reference §14](API_REFERENCE.md#14-open-questions--ambiguities)).

## Cycle trimming

When a time-domain capture doesn't start and end exactly at zero-crossings of the AC signal, the leading and trailing partial cycles can distort FFT-based amplitude/phase estimates (spectral leakage). `extract_complete_cycles` detects zero-crossings in the current signal, estimates the average cycle length, and trims any leading/trailing fragment shorter than 20% of a cycle — keeping only whole cycles for the impedance calculation. This step is optional (`ZERO_CROSS_TRIM`) and falls back to the untrimmed signal if fewer than 3 zero-crossings are found.
