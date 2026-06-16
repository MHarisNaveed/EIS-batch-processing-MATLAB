skipped first 15 lines

fix time format, <T = Untitled;
T.VarName1 = erase(T.VarName1, ',');
T.VarName1 = duration(T.VarName1, 'InputFormat', 'hh:mm:ss.SSSSSSSS');>

Columns 5, 6, 7 (Uz3, Uz4, Uz5) are never touched in the entire code. 


==========================

EIS Data Processing — Work Done So Far
File
Single CSV file from a Yokogawa DL350 scope recorder

User selects file via MATLAB UI dialog

Step 1 — Raw File Read
Read entire file as lines of text (1017 lines total)

Step 2 — Header Parsing
Extracted from header:

6 channel names: Ushunt [V], Uz1 [V], Uz2 [V], Uz3 [V], Uz4 {V}, Uz5 [V]

Date: 2026/02/12

Time: 11:02:43.10852825

Sample Rate: 1,000,000 Hz

Data starts at line 17

Step 3 — Data Import
Read CSV skipping first 16 header lines

Assigned proper column names: Time + 6 channels

Fixed Time column: removed commas, converted to duration (hh:mm:ss.SSSSSSSS), zeroed to start

Step 4 — Current Calculation
Removed last 3 rows (998 rows remain)

Calculated Current = Ushunt / 0.0075 (shunt resistor = 7.5 mΩ)

Added Current as new column

Step 5 — FFT Analysis
Plotted one-sided FFT amplitude spectrum for Current, Uz1, and Uz2

Printed top 3 peak frequencies and amplitudes for each

Step 6 — DC Bias Removal (Uz2)
Calculated mean DC offset of Uz2 (~3.59 V — battery nominal voltage)

Subtracted bias to create Uz2_AC column (pure AC component)

Step 7 — Amplitude Scaling (Uz2)
Computed peak-to-peak values for Current and Uz2_AC

Scaled Uz2_AC to match Current amplitude range (~±5 A)

Added Uz2_AC_scaled column for overlay comparison

Current Table Structure
Time	Ushunt	Uz1	Uz2	Uz3	Uz4	Uz5	Current	Uz2_AC	Uz2_AC_scaled

======================================
For Electrochemical Impedance Spectroscopy (EIS), the accuracy of your results depends entirely on extracting the exact phase shift ($\theta$) and magnitude ($|Z|$) between the voltage and current signals. Standard filtering (like a Butterworth or Moving Average) is often counter-productive for EIS because it can introduce frequency-dependent phase lags that distort your impedance calculation.Since you are working with a known excitation frequency (visible as $5\text{ kHz}$ in Screenshot 2026-05-13 181301.png), you can exploit the "sine-wave" nature of the signal using Orthogonal Correlation or Lock-in Amplification.

1. Why "Standard" Filters are Risky for EISIn battery testing, particularly when developing Digital Twins or Battery Management Systems, the timing between $V$ and $I$ is critical.Phase Distortion: A low-pass filter shifts the phase of the signal. If your voltage and current signals aren't filtered with identical, perfectly matched filters, you will measure an "artificial" phase shift that isn't actually coming from the battery's internal chemistry.Amplitude Attenuation: If your cutoff frequency is too close to your test frequency, you will dampen the peak voltage, leading to an incorrect $R_{internal}$ calculation.

================================
