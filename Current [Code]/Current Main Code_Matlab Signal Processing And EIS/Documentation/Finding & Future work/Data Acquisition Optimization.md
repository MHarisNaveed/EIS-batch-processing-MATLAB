# **Data Acquisition Optimization for Electrochemical Impedance Spectroscopy (EIS)**  
## **Summary**  
Electrochemical Impedance Spectroscopy (EIS) relies on precise frequency-domain data to resolve physical cell mechanisms such as charge transfer resistance (**Rct**), double-layer capacitance ( **Cdl**), and Warburg diffusion elements. Traditional fixed sampling setups across wide frequency sweeps create extreme computational inefficiency at high frequencies and inadequate resolution at low frequencies.  
This document presents a comparative evaluation between the initial unoptimized acquisition setup and an optimized logarithmic **2^N** framework. By aligning sampling rates ( **Fs**), capture durations ( **T**), and power-of-two point counts ( **N_FFT**) with the physical requirements of EIS, this strategy eliminates spectral leakage, speeds up computation, and preserves cell stability.  
   
## **Baseline Hardware Data Setup**  
The table below outlines the initial parameters recorded during data collection prior to optimization.  
   
   
| | | | | | |  
|-|-|-|-|-|-|  
| **Target Frequency (f_target)** | **Initial Sampling Rate (F_s)** | **Initial Point Count (N)** | **Initial Capture Time (T)** | **Initial Bin Width (Δf)** | **Baseline Precision Status** |   
| 1.0 Hz | 2,000 Hz | 10,001 | 5.000 s | 0.20 Hz | Fair (± 0.20 Hz) |   
| 4.0 Hz | 5,000 Hz | 10,001 | 2.000 s | 0.50 Hz | Coarse (± 0.50 Hz) |   
| 10.0 Hz | 20,000 Hz | 10,001 | 0.500 s | 2.00 Hz | Poor (± 2.00 Hz) |   
| 30.0 Hz | 50,000 Hz | 10,001 | 0.200 s | 5.00 Hz | Poor (± 5.00 Hz) |   
| 80.0 Hz | 200,000 Hz | 10,001 | 0.050 s | 20.00 Hz | Very Poor (± 20.00 Hz) |   
| 250.0 Hz | 500,000 Hz | 10,001 | 0.020 s | 50.00 Hz | Severe Smearing (± 50.00 Hz) |   
| 400.0 Hz | 500,000 Hz | 10,001 | 0.020 s | 50.00 Hz | Severe Smearing (± 50.00 Hz) |   
| 600.0 Hz | 1,000,000 Hz | 10,001 | 0.010 s | 99.99 Hz | Unusable (± 100 Hz) |   
| 1,999.0 Hz | 1,000,000 Hz | 2,001 | 0.002 s | 499.75 Hz | Unusable (± 500 Hz) |   
| 4,995.0 Hz | 1,000,000 Hz | 1,001 | 0.001 s | 999.00 Hz | Unusable (± 1,000 Hz) |   
![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAACCAYAAACZgbYnAAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAAEklEQVR4nGP4//8/AxMDAwMDABf8AwDXbXN0AAAAAElFTkSuQmCC)  
   
   
## Optimized EIS Acquisition Strategy  
## To resolve the frequency smearing observed at higher target frequencies, the target resolution (**Δf**) is scaled logarithmically. Point counts are rounded to exact powers of two (2^N) to unlock O(N log N) radix-2 Fast Fourier Transform (FFT) computational speed.  
| | | | | | | | |  
|-|-|-|-|-|-|-|-|  
| ## **Target Freq. (f_target)** | ## **Target Log Res. (Δf)** | ## **Relative Precision** | ## **Rec. F_s (Hz)** | ## **Opt. Points (N_FFT)** | ## **Capture Time (T)** | ## **Captured Sine Cycles** | ## **Effective Bin Width (EBW)** |   
| ## 0.2 Hz | ## 0.02 Hz | ## 10.00% | ## 100 | ## 8,192 (2^13) | ## 81.92 s | ## 16.38 cycles | ## 0.0122 Hz |   
| ## 0.4 Hz | ## 0.02 Hz | ## 5.00% | ## 100 | ## 8,192 (2^13) | ## 81.92 s | ## 32.77 cycles | ## 0.0122 Hz |   
| ## 0.6 Hz | ## 0.02 Hz | ## 3.33% | ## 100 | ## 8,192 (2^13) | ## 81.92 s | ## 49.15 cycles | ## 0.0122 Hz |   
| ## 0.8 Hz | ## 0.02 Hz | ## 2.50% | ## 100 | ## 8,192 (2^13) | ## 81.92 s | ## 65.54 cycles | ## 0.0122 Hz |   
| ## 1.0 Hz | ## 0.02 Hz | ## 2.00% | ## 1,000 | ## 65,536 (2^16) | ## 65.54 s | ## 65.54 cycles | ## 0.0153 Hz |   
| ## 4.0 Hz | ## 0.05 Hz | ## 1.25% | ## 1,000 | ## 32,768 (2^15) | ## 32.77 s | ## 131.07 cycles | ## 0.0305 Hz |   
| ## 10.0 Hz | ## 0.10 Hz | ## 1.00% | ## 1,000 | ## 16,384 (2^14) | ## 16.38 s | ## 163.84 cycles | ## 0.0610 Hz |   
| ## 30.0 Hz | ## 0.20 Hz | ## 0.67% | ## 1,000 | ## 8,192 (2^13) | ## 8.19 s | ## 245.76 cycles | ## 0.1221 Hz |   
| ## 80.0 Hz | ## 0.50 Hz | ## 0.63% | ## 2,000 | ## 8,192 (2^13) | ## 4.10 s | ## 327.68 cycles | ## 0.2441 Hz |   
| ## 250.0 Hz | ## 1.00 Hz | ## 0.40% | ## 5,000 | ## 8,192 (2^13) | ## 1.64 s | ## 409.60 cycles | ## 0.6104 Hz |   
| ## 400.0 Hz | ## 1.50 Hz | ## 0.38% | ## 5,000 | ## 4,096 (2^12) | ## 0.82 s | ## 327.68 cycles | ## 1.2207 Hz |   
| ## 600.0 Hz | ## 2.00 Hz | ## 0.33% | ## 10,000 | ## 8,192 (2^13) | ## 0.82 s | ## 491.52 cycles | ## 1.2207 Hz |   
| ## 1,999.0 Hz | ## 3.00 Hz | ## 0.15% | ## 20,000 | ## 8,192 (2^13) | ## 0.41 s | ## 818.79 cycles | ## 2.4414 Hz |   
| ## 4,995.0 Hz | ## 5.00 Hz | ## 0.10% | ## 50,000 | ## 16,384 (2^14) | ## 0.33 s | ## 1,636.76 cycles | ## 3.0518 Hz |   
Technical Analysis & Research Findings  
1. Parameter Definitions  
- **Target Frequency (f_target):** The frequency of the applied sinusoidal current/voltage excitation.  
- **Log Resolution (Δf):** The desired frequency step size. Scaled logarithmically to maintain consistent relative precision.  
- **Relative Precision:** (Δf / f_target) × 100%, indicating the relative sharpness of the bin spacing.  
- **Recommended Sampling Rate (F_s):** Hardware sampling speed chosen at 10× to 20× f_target, providing Nyquist margin (F_s ≥ 2 f_target) while avoiding excessive file sizes.  
- **Optimized Points (N_FFT):** Sample count rounded up to the nearest 2^N value (via hardware capture or software zero-padding).  
- **Effective Bin Width (EBW):** The actual frequency spacing generated by the algorithm: EBW = F_s / N_FFT.  
2. Governing Equations  
- **Effective Bin Width (EBW)** = F_s / N_FFT  
- **Physical Capture Duration (T)** = N_FFT / F_s  
- **Captured Cycles (C)** = f_target × T = f_target × (N_FFT / F_s)  
- **FFT Computational Complexity** = O(N_FFT log2 N_FFT)  
System Optimization Mechanisms  
1. Eliminating Extreme Oversampling  
In the baseline setup, sampling 600 Hz at 1 MHz yielded an extremely short 10-millisecond capture window. The resulting 100 Hz bin width caused severe spectral smearing. Reducing F_s to 10,000 Hz extends the capture window to 0.82 seconds, refining the bin resolution down to 1.22 Hz.  
2. Power-of-Two Radix-2 Speedup  
Direct Discrete Fourier Transform (DFT) algorithms require O(N^2) complex operations. Arbitrary sizes (such as N = 10,001) force processors into slow mixed-radix calculations. Forcing N to power-of-two lengths (2^10, 2^12, 2^14) unlocks the Cooley-Tukey algorithm, reducing processing time by up to 100×.  
3. Benefits for EIS Measurement Accuracy  
- **Low-Frequency Drift Cancellation:** Capturing 16 to 65 complete cycles between 0.2 Hz and 1.0 Hz averages out non-steady-state DC drift and thermal noise, stabilizing Warburg diffusion measurements.  
- **Minimization of Picket-Fence Losses:** Ensuring EBW ≤ Log Δf keeps peak energy aligned near bin centers, preventing artificial amplitude drops in impedance magnitude (|Z|) and phase angle (θ).  
- **Optimized Test Duration:** Restricting high-frequency recording windows to fractions of a second allows full multi-decade sweeps to execute rapidly, preventing cell degradation during testing.  
![](data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAACCAYAAACZgbYnAAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAAEklEQVR4nGP4//8/AxMDAwMDABf8AwDXbXN0AAAAAElFTkSuQmCC)  
   
