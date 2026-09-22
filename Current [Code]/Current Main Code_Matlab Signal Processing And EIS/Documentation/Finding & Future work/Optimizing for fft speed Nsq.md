Yes, you can absolutely make the Effective Bin Width (EBW) a clean, "natural-looking"
decimal number (like exactly 0.010 Hz, 0.050 Hz, or 0.100 Hz).
To get a clean decimal bin width, you simply set your capture time to a clean number of
seconds (T = 1 / EBW) and collect an integer number of points (N = Fs × T).
However, shifting from power-of-two point counts (2^N) to clean decimal numbers comes
with specific trade-offs.
How to Get Clean "Natural" EBWs
| Desired  | Required Capture     | At Fs = 100 Hz  | At Fs = 1,000 Hz  |
| -------- | -------------------- | --------------- | ----------------- |
| Clean    | Time (T = 1 / EBW)   | (N = Fs × T)    | (N = Fs × T)      |
EBW
| 0.100 Hz  | 10 seconds   | 1,000 points   | 10,000 points   |
| --------- | ------------ | -------------- | --------------- |
| 0.050 Hz  | 20 seconds   | 2,000 points   | 20,000 points   |
| 0.020 Hz  | 50 seconds   | 5,000 points   | 50,000 points   |
| 0.010 Hz  | 100 seconds  | 10,000 points  | 100,000 points  |
Pros & Cons of Clean Decimal EBWs
PROS
●  Human Readability: Your frequency spectrum displays clean bin values (1.00 Hz, 1.01
Hz, 1.02 Hz instead of 1.0122 Hz, 1.0244 Hz). This makes manual inspection and
plotting much easier to interpret.
●  Exact Peak Alignment: If your excitation frequency is a clean decimal (e.g., 1.00 Hz), it
lands exactly in the center of Bin 100 (when EBW = 0.010 Hz). This eliminates spectral
leakage and phase distortion without needing windowing functions.
●  Intuitive Time-Domain Planning: Capture times are predictable round numbers (10s,
20s, 50s, 100s).
CONS (The Cost)
●  Slower Computational Speed: Numbers like 10,000 or 50,000 are not powers of two
(2^N). Modern software (MATLAB/Python) cannot use the hyper-fast Radix-2

Cooley-Tukey algorithm. It must fall back to mixed-radix algorithms, which are 3× to 20×
slower depending on the prime factors of N.
● Loss of Arbitrary Padding Efficiency: If you zero-pad 10,000 points to 16,384 points
to regain processing speed, your effective bin width reverts back to an "unnatural"
number (0.061 Hz).
● Inflexible Memory Allocations: Hardware microcontrollers and DSP chips are
architected around power-of-two memory buffers (1024, 2048, 4096). Arbitrary point
counts require custom buffer handling.
Summary: Should You Do It for EIS?
● If your priority is Real-Time Embedded Processing or Automated Fitting: Stick to
Power-of-Two (2^N). The computer does not care about "pretty" bin numbers, and it
benefits greatly from O(N log N) execution speeds.
● If your priority is Human Data Presentation, CSV Export, or Pure Harmonics: Use
Clean Decimal EBWs (10s, 50s, 100s capture windows). The processing overhead on
modern desktop CPUs is measured in milliseconds anyway, making the clean human
readability well worth the minor computational cost.
1.