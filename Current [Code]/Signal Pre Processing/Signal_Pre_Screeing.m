% =========================================================================
%  WAVEFORM ANALYZER  —  Single-file modular script
%
%  USAGE:   Run this file.  A folder picker will appear.
%
%  OUTPUT STRUCTURE CREATED:
%    <selected>/Passed/        — renamed good CSVs + Signal + FFT plots
%    <selected>/Defective/     — renamed bad  CSVs + Signal + FFT plots
%    <selected>/Defective/separate_by_tag.m   — re-sort script by defect tag
%
%  SECTIONS:
%    §0  Tuneable Parameters
%    §1  Folder Setup & File Discovery
%    §2  Main Processing Loop
%    §3  Summary Print
%    §4  LOCAL FUNCTIONS
%        §4.1  load_csv
%        §4.2  compute_spectral_metrics
%        §4.3  check_signal_integrity
%        §4.4  classify_defects
%        §4.5  plot_signal
%        §4.6  plot_fft
%        §4.7  write_separator_script
%        §4.8  ternary  (inline conditional utility)
% =========================================================================

clc; clear; close all;

% =========================================================================
%  §0  TUNEABLE PARAMETERS
% =========================================================================
P.header_lines        = 15;     % CSV rows before data begins
P.shunt_ohm           = 0.0075; % Shunt resistor (Ω)  →  I = V_shunt / R
P.trim_pct            = 0.10;   % Fraction trimmed from each end (0–0.40)
P.freq_close_pct      = 5;      % Two FFT peaks "same freq" if within this %
P.snr_threshold_db    = 10;     % Minimum acceptable SNR (dB)
P.thd_threshold_pct   = 30;     % Maximum acceptable THD (%)
P.sine_r2_threshold   = 0.50;   % Minimum R² for sine-fit acceptance (EIS currents with noise typically 0.6-0.9)
P.freq_match_pct      = 5;      % Max allowed % difference I vs V frequency
P.top_n_peaks         = 10;     % How many dominant FFT peaks to find/annotate
P.fig_size_signal     = [1400 800];  % Signal figure [width height] px
P.fig_size_fft        = [1400 700];  % FFT figure    [width height] px
P.save_format         = 'jpeg'; % 'jpeg' | 'png'
P.fft_xlim_hz         = 0;      % Upper x-limit for FFT (Hz); 0 = auto full Nyquist

% =========================================================================
%  §1  FOLDER SETUP & FILE DISCOVERY
% =========================================================================
folder = uigetdir('', 'Select Folder Containing Waveform CSV Files');
if folder == 0
    disp('Folder selection cancelled.'); return;
end

folder_passed    = fullfile(folder, 'Passed');
folder_defective = fullfile(folder, 'Defective');
if ~exist(folder_passed,    'dir'), mkdir(folder_passed);    end
if ~exist(folder_defective, 'dir'), mkdir(folder_defective); end

% Only pick up CSVs directly in the selected folder (not sub-folders)
files = dir(fullfile(folder, '*.csv'));
if isempty(files)
    disp('No CSV files found in selected folder.'); return;
end
fprintf('\nFound %d CSV file(s) to process.\n', length(files));

% =========================================================================
%  §2  MAIN PROCESSING LOOP
% =========================================================================
summary = {};   % one row per file: {filename, status, tags, freq, snr/thd}

for k = 1:length(files)
    filename = files(k).name;
    fullpath = fullfile(folder, filename);
    fprintf('\n[%d/%d] Processing: %s\n', k, length(files), filename);

    % --- §2.1  Load raw data ---
    [t, current, voltage1, voltage2, dt_str, load_ok, load_msg] = ...
        load_csv(fullpath, P);

    if ~load_ok
        fprintf('  SKIP — %s\n', load_msg);
        summary(end+1,:) = {filename, 'SKIPPED', load_msg, '', ''};
        continue;
    end

    t_rel = t - t(1);   % time relative to first sample

    % --- §2.2  Signal integrity checks (time domain) ---
    [~, sig_tags] = check_signal_integrity(t_rel, current, voltage1, P);

    % --- §2.3  Spectral metrics ---
    mI = compute_spectral_metrics(current,  t_rel, P);
    mV = compute_spectral_metrics(voltage1, t_rel, P);

    % --- §2.4  Defect classification ---
    [is_defective, def_tags] = classify_defects(mI, mV, sig_tags, P);

    all_tags = strjoin([def_tags], ' | ');
    if isempty(all_tags), all_tags = 'OK'; end

    % --- §2.5  Build new filename ---
    [~, orig_base, ~] = fileparts(filename);
    freq_label  = round(median([mI.fund_hz, mV.fund_hz]));
    dest_folder = ternary(is_defective, folder_defective, folder_passed);

    if is_defective
        new_name = sprintf('%s_%dHz_DEFECTIVE.csv', orig_base, freq_label);
    else
        new_name = sprintf('%s_%dHz.csv', orig_base, freq_label);
    end

    % --- §2.6  Copy CSV (overwrites existing file of same name) ---
    copyfile(fullpath, fullfile(dest_folder, new_name));
    fprintf('  CSV saved  → %s\n', new_name);

    % --- §2.7  Derived scalars for plots ---
    I_dc        = mean(current);
    V_dc        = mean(voltage1);
    I_pk        = mI.ac_rms * sqrt(2);
    V_pk        = mV.ac_rms * sqrt(2);
    voltage1_ac = voltage1 - V_dc;

    % --- §2.8  Signal waveform plot ---
    plot_signal(t_rel, current, voltage1, voltage1_ac, ...
                I_dc, V_dc, I_pk, V_pk, mI, mV, ...
                orig_base, dt_str, dest_folder, P);

    % --- §2.9  FFT plot ---
    plot_fft(current, voltage1, t_rel, mI, mV, ...
             orig_base, dt_str, dest_folder, P);

    % --- §2.10  Accumulate summary row ---
    summary(end+1,:) = { ...
        filename, ...
        ternary(is_defective, 'DEFECTIVE', 'PASSED'), ...
        all_tags, ...
        sprintf('%.2f Hz', mI.fund_hz), ...
        sprintf('SNR %.1fdB / THD %.1f%%', mI.snr_db, mI.thd_pct) };

    fprintf('  Status : %s  |  Tags: %s\n', ...
            ternary(is_defective,'DEFECTIVE','PASSED'), all_tags);
end

% =========================================================================
%  §3  SUMMARY PRINT  &  SEPARATOR SCRIPT
% =========================================================================
fprintf('\n%s\n', repmat('=',1,95));
fprintf('  SUMMARY\n');
fprintf('%s\n', repmat('=',1,95));
fprintf('  %-35s %-12s %-38s %-14s %s\n', ...
        'File','Status','Tags','Frequency','SNR / THD');
fprintf('%s\n', repmat('-',1,95));
for r = 1:size(summary,1)
    fprintf('  %-35s %-12s %-38s %-14s %s\n', summary{r,:});
end
fprintf('%s\n', repmat('=',1,95));

write_separator_script(folder_defective);
fprintf('\nAll done.\n');


% =========================================================================
%  §4  LOCAL FUNCTIONS
% =========================================================================

% -------------------------------------------------------------------------
%  §4.1  LOAD_CSV
%
%  Reads one oscilloscope CSV file.  Extracts the time vector, current
%  (derived from shunt voltage), two voltage channels, and the capture
%  datetime from the 14th/15th header rows.  Trims P.trim_pct from each
%  end of every signal.
%
%  INPUTS:
%    fullpath  (char)    Absolute path to the CSV file.
%    P         (struct)  Global parameters (header_lines, shunt_ohm, trim_pct).
%
%  OUTPUTS:
%    t         (Nx1 double)  Time vector (seconds).
%    current   (Nx1 double)  Current (A) = V_shunt / P.shunt_ohm.
%    voltage1  (Nx1 double)  Voltage channel 1 (V).
%    voltage2  (Nx1 double)  Voltage channel 2 (V).
%    dt_str    (char)        Capture datetime 'yyyymmdd_HHMMSS'.
%    ok        (logical)     True when data is valid and usable.
%    msg       (char)        Error description (empty when ok = true).
% -------------------------------------------------------------------------
function [t, current, voltage1, voltage2, dt_str, ok, msg] = load_csv(fullpath, P)

t = []; current = []; voltage1 = []; voltage2 = [];
dt_str = ''; ok = false; msg = '';

try
    % Read data block
    opts = detectImportOptions(fullpath, 'NumHeaderLines', P.header_lines);
    T    = readtable(fullpath, opts);

    % Drop rows where all of the first 4 columns are missing
    T = T(~all(ismissing(T(:, 1:4)), 2), :);

    if height(T) < 10
        msg = 'Too few valid data rows after cleaning.'; return;
    end

    % Time column (handle duration / datetime / numeric)
    t_raw = T{:,1};
    if isduration(t_raw) || isdatetime(t_raw)
        t = seconds(t_raw);
    else
        t = double(t_raw);
    end

    % Signal columns
    v_shunt  = double(T{:,2});
    current  = v_shunt / P.shunt_ohm;
    voltage1 = double(T{:,4});
    voltage2 = double(T{:,5});

    % Trim both ends
    n       = length(t);
    i_start = floor(P.trim_pct * n) + 1;
    i_end   = floor((1 - P.trim_pct) * n);
    idx     = i_start:i_end;
    t        = t(idx);
    current  = current(idx);
    voltage1 = voltage1(idx);
    voltage2 = voltage2(idx);

    if any(isnan(t)) || any(isnan(current)) || any(isnan(voltage1)) || ...
       any(isnan(voltage2)) || length(t) < 10
        msg = 'NaN values or too few samples after trim.'; return;
    end

    % Parse capture datetime from header rows 14–15
    try
        optsH                  = detectImportOptions(fullpath);
        optsH.DataLines        = [14 15];
        optsH.VariableNamesLine = 0;
        optsH.Delimiter        = ',';
        optsH                  = setvartype(optsH, 2, 'string');
        Th      = readtable(fullpath, optsH);
        rawDate = strtrim(string(Th{1,2}));
        rawTime = strtrim(string(Th{2,2}));
        dt_csv  = datetime(rawDate + " " + rawTime, ...
                           'InputFormat','yyyy/MM/dd HH:mm:ss.SSSSSSSSS');
        dt_str  = datestr(dt_csv, 'yyyymmdd_HHMMSS');
    catch
        fi     = dir(fullpath);
        dt_str = datestr(fi.datenum, 'yyyymmdd_HHMMSS');
    end

    ok = true;

catch ME
    msg = ME.message;
end
end


% -------------------------------------------------------------------------
%  §4.2  COMPUTE_SPECTRAL_METRICS
%
%  Computes FFT-based metrics for a single signal channel.
%
%  INPUTS:
%    signal  (Nx1 double)  Time-domain signal (current or voltage).
%    t       (Nx1 double)  Uniform time vector (seconds).
%    P       (struct)      Global parameters (top_n_peaks).
%
%  OUTPUTS:
%    m  (struct):
%      .fund_hz        Fundamental frequency (Hz).
%      .top_freqs      Top-N peak frequencies (Hz), descending amplitude.
%      .top_amps       Corresponding amplitudes.
%      .snr_db         Signal-to-Noise Ratio (dB).
%      .thd_pct        Total Harmonic Distortion (%).
%      .ac_rms         RMS of the AC component.
%      .crest_factor   Peak / RMS of AC component.
%      .freq_drift_pct Approx. frequency drift first vs second half (%).
%      .f_vec          Frequency axis (Hz).
%      .mag_vec        Single-sided FFT magnitude (signal units).
%      .phase_fund     Phase at fundamental (radians).
%      .sine_r2        R² of best-fit sine.
% -------------------------------------------------------------------------
function m = compute_spectral_metrics(signal, t, P)

m  = struct();
dt = median(diff(t));
Fs = 1 / dt;
N  = length(signal);

% AC component
sig_ac = signal - mean(signal);

% FFT — single-sided magnitude
Y     = fft(sig_ac);
P_mag = abs(Y / N);
P_one = P_mag(1:floor(N/2)+1);
P_one(2:end-1) = 2 * P_one(2:end-1);
f_vec = Fs * (0:floor(N/2)) / N;

m.f_vec   = f_vec;
m.mag_vec = P_one;

% Top-N peaks (skip DC bin)
[sorted_amps, sorted_idx] = sort(P_one(2:end), 'descend');
sorted_freqs = f_vec(sorted_idx + 1);
n_peaks      = min(P.top_n_peaks, length(sorted_amps));
m.top_freqs  = sorted_freqs(1:n_peaks);
m.top_amps   = sorted_amps(1:n_peaks);
m.fund_hz    = m.top_freqs(1);

% Phase at fundamental
[~, fund_bin]  = min(abs(f_vec - m.fund_hz));
m.phase_fund   = angle(Y(fund_bin));

% SNR — fundamental ± 5% of fund frequency treated as "signal", rest as "noise"
%       Using Hz-based bandwidth avoids the ±2-bin problem at low frequencies
freq_res   = f_vec(2) - f_vec(1);               % Hz per FFT bin
bw_hz      = max(3 * freq_res, 0.05 * m.fund_hz); % at least 3 bins or 5% of fund
bw_bins    = ceil(bw_hz / freq_res);
sig_bins   = max(1, fund_bin-bw_bins) : min(length(P_one), fund_bin+bw_bins);
noise_bins = setdiff(2:length(P_one), sig_bins);
sig_pwr    = sum(P_one(sig_bins).^2);
noise_pwr  = sum(P_one(noise_bins).^2);
m.snr_db   = ternary(noise_pwr > 0, 10*log10(sig_pwr/noise_pwr), Inf);

% THD — sum harmonics 2f, 3f, … up to Nyquist
harm_pwr = 0;
h = 2;
while h * m.fund_hz <= Fs/2
    [~, hbin] = min(abs(f_vec - h * m.fund_hz));
    harm_pwr  = harm_pwr + P_one(hbin)^2;
    h = h + 1;
end
fund_amp  = P_one(fund_bin);
m.thd_pct = ternary(fund_amp > 0, 100*sqrt(harm_pwr)/fund_amp, Inf);

% AC RMS and crest factor
m.ac_rms      = rms(sig_ac);
pk            = max(abs(sig_ac));
m.crest_factor = ternary(m.ac_rms > 0, pk/m.ac_rms, Inf);

% Frequency drift (first vs second half)
n_half = floor(N/2);
f1 = local_fund(sig_ac(1:n_half),      Fs);
f2 = local_fund(sig_ac(n_half+1:end),  Fs);
m.freq_drift_pct = ternary(f1 > 0, 100*abs(f2-f1)/f1, 0);

% Sine-fit R²  — least-squares fit of A*sin(wt)+B*cos(wt), phase-invariant.
% Avoids anti-phase cancellation that causes R² = -1 with fixed-phase approach.
t_rel  = t - t(1);
w      = 2 * pi * m.fund_hz;
X      = [sin(w * t_rel), cos(w * t_rel)];   % design matrix
coeffs = X \ sig_ac;                          % least-squares [A; B]
sine_fit  = X * coeffs;
ss_res    = sum((sig_ac - sine_fit).^2);
ss_tot    = sum((sig_ac - mean(sig_ac)).^2);
m.sine_r2    = ternary(ss_tot > 0, 1 - ss_res/ss_tot, 0);
m.fit_amp_pk = sqrt(coeffs(1)^2 + coeffs(2)^2);  % fitted peak amplitude
end

% Helper: fundamental from a signal segment
function f = local_fund(seg, Fs)
N     = length(seg);
Y     = abs(fft(seg - mean(seg)));
Y     = Y(1:floor(N/2)+1);
f_vec = Fs * (0:floor(N/2)) / N;
[~,i] = max(Y(2:end));
f     = f_vec(i + 1);
end


% -------------------------------------------------------------------------
%  §4.3  CHECK_SIGNAL_INTEGRITY
%
%  Time-domain sanity checks.
%
%  INPUTS:
%    t        (Nx1 double)  Relative time vector (s).
%    current  (Nx1 double)  Current signal (A).
%    voltage  (Nx1 double)  Voltage signal (V).
%    P        (struct)      Global parameters (no specific fields required).
%
%  OUTPUTS:
%    ok    (logical)        True when all checks pass.
%    tags  (cell of char)   Defect tag strings (empty cell when ok = true).
%
%  CHECKS:
%    1. NaN / Inf in t, current, voltage.
%    2. Flat-line (zero variance) signals.
%    3. Leading / trailing zero-runs > 1% of length.
%    4. Non-monotonic or zero time steps.
%    5. Minimum 10 samples.
% -------------------------------------------------------------------------
function [ok, tags] = check_signal_integrity(t, current, voltage, ~)

tags = {};

if length(t) < 10
    tags{end+1} = 'TOO_SHORT'; ok = false; return;
end

if any(~isfinite(t)),       tags{end+1} = 'TIME_NAN_INF';    end
if any(~isfinite(current)), tags{end+1} = 'CURRENT_NAN_INF'; end
if any(~isfinite(voltage)), tags{end+1} = 'VOLTAGE_NAN_INF'; end

thr = max(2, floor(0.01 * length(current)));

lead_I  = find(current ~= 0, 1, 'first') - 1;
lead_V  = find(voltage ~= 0, 1, 'first') - 1;
trail_I = length(current) - find(current ~= 0, 1, 'last');
trail_V = length(voltage) - find(voltage ~= 0, 1, 'last');

if ~isempty(lead_I)  && lead_I  > thr, tags{end+1} = sprintf('LEADING_ZEROS_CURRENT(%d)',  lead_I);  end
if ~isempty(lead_V)  && lead_V  > thr, tags{end+1} = sprintf('LEADING_ZEROS_VOLTAGE(%d)',  lead_V);  end
if ~isempty(trail_I) && trail_I > thr, tags{end+1} = sprintf('TRAILING_ZEROS_CURRENT(%d)', trail_I); end
if ~isempty(trail_V) && trail_V > thr, tags{end+1} = sprintf('TRAILING_ZEROS_VOLTAGE(%d)', trail_V); end

if std(current) < 1e-12, tags{end+1} = 'FLAT_CURRENT'; end
if std(voltage) < 1e-12, tags{end+1} = 'FLAT_VOLTAGE'; end

if any(diff(t) <= 0), tags{end+1} = 'NON_MONOTONIC_TIME'; end

ok = isempty(tags);
end


% -------------------------------------------------------------------------
%  §4.4  CLASSIFY_DEFECTS
%
%  Applies spectral and sine-fit rules; merges with prior integrity tags.
%
%  INPUTS:
%    mI          (struct)        Spectral metrics for current.
%    mV          (struct)        Spectral metrics for voltage.
%    prior_tags  (cell of char)  Tags from check_signal_integrity.
%    P           (struct)        Global parameters:
%                                  freq_close_pct, snr_threshold_db,
%                                  thd_threshold_pct, sine_r2_threshold,
%                                  freq_match_pct.
%
%  OUTPUTS:
%    is_defective  (logical)       True if any defect found.
%    tags          (cell of char)  All defect tag strings.
%
%  RULES:
%    1. Top-2 FFT peaks within freq_close_pct → AMBIGUOUS_FREQ.
%    2. SNR below threshold              → LOW_SNR.
%    3. THD above threshold              → HIGH_THD.
%    4. Sine R² below threshold          → NOT_SINUSOIDAL.
%    5. Current/Voltage fundamental mismatch → FREQ_MISMATCH_I_vs_V.
% -------------------------------------------------------------------------
function [is_defective, tags] = classify_defects(mI, mV, prior_tags, P)

tags = prior_tags(:)';

% Rule 1 — ambiguous dominant frequency (checked separately for I and V)
if length(mI.top_freqs) >= 2
    f1 = mI.top_freqs(1);  f2 = mI.top_freqs(2);
    if 100*abs(f1-f2)/max(f1,1) < P.freq_close_pct
        tags{end+1} = sprintf('CURRENT_AMBIGUOUS_FREQ(%.1fHz_vs_%.1fHz)', f1, f2);
    end
end
if length(mV.top_freqs) >= 2
    f1 = mV.top_freqs(1);  f2 = mV.top_freqs(2);
    if 100*abs(f1-f2)/max(f1,1) < P.freq_close_pct
        tags{end+1} = sprintf('VOLTAGE_AMBIGUOUS_FREQ(%.1fHz_vs_%.1fHz)', f1, f2);
    end
end

% Rule 2 — SNR (current only; voltage is a small AC perturbation on DC bias
%           so its SNR is naturally low and not a meaningful defect indicator)
if mI.snr_db < P.snr_threshold_db, tags{end+1} = sprintf('LOW_SNR_CURRENT(%.1fdB)',  mI.snr_db); end

% Rule 3 — THD (current only; voltage harmonics are expected in EIS perturbation)
if mI.thd_pct > P.thd_threshold_pct, tags{end+1} = sprintf('HIGH_THD_CURRENT(%.1f%%)', mI.thd_pct); end

% Rule 4 — sine fitness (current only; voltage AC amplitude is small vs DC offset
%           which makes R² unreliable as a quality metric for voltage)
if mI.sine_r2 < P.sine_r2_threshold, tags{end+1} = sprintf('NOT_SINUSOIDAL_CURRENT(R2=%.3f)', mI.sine_r2); end

% Rule 5 — I vs V frequency mismatch
f_pct = 100 * abs(mI.fund_hz - mV.fund_hz) / max(mI.fund_hz, 1);
if f_pct > P.freq_match_pct
    tags{end+1} = sprintf('FREQ_MISMATCH_I_vs_V(%.1fHz_vs_%.1fHz)', mI.fund_hz, mV.fund_hz);
end

is_defective = ~isempty(tags);
end


% -------------------------------------------------------------------------
%  §4.5  PLOT_SIGNAL
%
%  Three-subplot time-domain waveform figure → saved JPEG/PNG.
%
%  INPUTS:
%    t_rel       (Nx1 double)  Relative time (s).
%    current     (Nx1 double)  Current signal (A).
%    voltage     (Nx1 double)  Voltage signal (V).
%    voltage_ac  (Nx1 double)  AC-only voltage (V).
%    I_dc        (double)      DC offset of current (A).
%    V_dc        (double)      DC offset of voltage (V).
%    I_pk        (double)      Peak AC current estimate (A).
%    V_pk        (double)      Peak AC voltage estimate (V).
%    mI          (struct)      Spectral metrics for current.
%    mV          (struct)      Spectral metrics for voltage.
%    base_name   (char)        Original filename stem (no extension).
%    dt_str      (char)        Datetime string 'yyyymmdd_HHMMSS'.
%    dest_folder (char)        Destination folder for the saved image.
%    P           (struct)      Parameters (fig_size_signal, save_format).
%
%  OUTPUTS:
%    Image file: <dest_folder>/<base_name>_<dt_str>_Signal.<ext>
% -------------------------------------------------------------------------
function plot_signal(t_rel, current, voltage, voltage_ac, ...
                     I_dc, V_dc, I_pk, V_pk, mI, mV, ...
                     base_name, dt_str, dest_folder, P)

C_I = [0.20 0.55 0.85];
C_V = [0.85 0.33 0.10];

fig = figure('Name', sprintf('%s | %s', base_name, dt_str), ...
             'NumberTitle','off', ...
             'Position',   [50 50 P.fig_size_signal(1) P.fig_size_signal(2)], ...
             'Color','w', 'Visible','off');

sgtitle(sprintf('Raw Signal Inspection  —  %s\n%s  |  I: %.2f Hz  |  V: %.2f Hz', ...
                base_name, dt_str, mI.fund_hz, mV.fund_hz), ...
        'FontSize',12, 'FontWeight','bold', 'Interpreter','none');

% Subplot 1 — Current
ax1 = subplot(3,1,1);
plot(t_rel, current, 'Color',C_I, 'LineWidth',1.2);
yline(I_dc,'--k', sprintf('DC = %.4f A', I_dc), ...
      'LineWidth',0.8, 'LabelHorizontalAlignment','left');
ylabel('Current (A)');
title(sprintf('Current  [%.2f Hz  |  AC pk = %.4f A  |  THD = %.1f%%  |  SNR = %.1f dB  |  R² = %.3f]', ...
              mI.fund_hz, I_pk, mI.thd_pct, mI.snr_db, mI.sine_r2));
grid on; box on;

% Subplot 2 — Voltage
ax2 = subplot(3,1,2);
plot(t_rel, voltage, 'Color',C_V, 'LineWidth',1.2);
yline(V_dc,'--k', sprintf('DC = %.6f V', V_dc), ...
      'LineWidth',0.8, 'LabelHorizontalAlignment','left');
ylabel('Voltage (V)');
title(sprintf('Voltage  [%.2f Hz  |  AC pk = %.6f V  |  THD = %.1f%%  |  SNR = %.1f dB  |  R² = %.3f]', ...
              mV.fund_hz, V_pk, mV.thd_pct, mV.snr_db, mV.sine_r2));
grid on; box on;

% Subplot 3 — Voltage AC only
ax3 = subplot(3,1,3);
plot(t_rel, voltage_ac, 'Color',C_V, 'LineWidth',1.2);
yline(0,'--k','LineWidth',0.8);
ylabel('Voltage AC (V)'); xlabel('Time (s)');
title(sprintf('Voltage AC only  [RMS = %.6f V  |  Crest = %.2f  |  Freq drift = %.1f%%]', ...
              mV.ac_rms, mV.crest_factor, mV.freq_drift_pct));
grid on; box on;

linkaxes([ax1,ax2,ax3],'x');
xlim(ax1,[t_rel(1) t_rel(end)]);

out_name = sprintf('%s_%s_Signal.%s', base_name, dt_str, P.save_format);
exportgraphics(fig, fullfile(dest_folder, out_name), 'Resolution',150);
fprintf('  Signal plot → %s\n', out_name);
close(fig);
end


% -------------------------------------------------------------------------
%  §4.6  PLOT_FFT
%
%  Two-subplot broad-spectrum FFT figure with annotated peak markers.
%  X-axis spans full Nyquist (or P.fft_xlim_hz if set > 0).
%  Top P.top_n_peaks frequencies are marked with triangles and labels.
%
%  INPUTS:
%    current     (Nx1 double)  Current signal (A).
%    voltage     (Nx1 double)  Voltage signal (V).
%    t           (Nx1 double)  Relative time vector (s).
%    mI          (struct)      Spectral metrics for current.
%    mV          (struct)      Spectral metrics for voltage.
%    base_name   (char)        Original filename stem (no extension).
%    dt_str      (char)        Datetime string 'yyyymmdd_HHMMSS'.
%    dest_folder (char)        Destination folder for the saved image.
%    P           (struct)      Parameters (fig_size_fft, fft_xlim_hz,
%                              save_format, top_n_peaks).
%
%  OUTPUTS:
%    Image file: <dest_folder>/<base_name>_<dt_str>_FFT.<ext>
% -------------------------------------------------------------------------
function plot_fft(current, voltage, ~, mI, mV, base_name, dt_str, dest_folder, P)

C_I = [0.20 0.55 0.85];
C_V = [0.85 0.33 0.10];

% Auto x-limit: full Nyquist unless user set a specific value
if P.fft_xlim_hz > 0
    xlim_hz = P.fft_xlim_hz;
else
    xlim_hz = max(mI.f_vec(end), mV.f_vec(end));
end

fig = figure('Name', sprintf('FFT | %s', base_name), ...
             'NumberTitle','off', ...
             'Position',   [50 50 P.fig_size_fft(1) P.fig_size_fft(2)], ...
             'Color','w', 'Visible','off');

sgtitle(sprintf('FFT Spectrum  —  %s  |  %s', base_name, dt_str), ...
        'FontSize',12, 'FontWeight','bold', 'Interpreter','none');

% ---- Subplot 1: Current FFT ---------------------------------------------
ax1 = subplot(2,1,1);
plot(mI.f_vec, mI.mag_vec, 'Color',C_I, 'LineWidth',1.0);
hold on;
n_ann = min(P.top_n_peaks, length(mI.top_freqs));
for p = 1:n_ann
    xp = mI.top_freqs(p);  yp = mI.top_amps(p);
    plot(ax1, xp, yp, 'v', 'Color',C_I, 'MarkerFaceColor',C_I, 'MarkerSize',6);
    text(xp, yp*1.10, sprintf('#%d\n%.2f Hz', p, xp), ...
         'FontSize',7, 'HorizontalAlignment','center', ...
         'Color',C_I, 'Interpreter','none');
end
xlim([0 xlim_hz]);
xlabel('Frequency (Hz)'); ylabel('Magnitude (A)');
title(sprintf('Current FFT  [Fund: %.2f Hz  |  SNR: %.1f dB  |  THD: %.1f%%  |  R²: %.3f]', ...
              mI.fund_hz, mI.snr_db, mI.thd_pct, mI.sine_r2));
grid on; box on;

% ---- Subplot 2: Voltage FFT ---------------------------------------------
ax2 = subplot(2,1,2);
plot(mV.f_vec, mV.mag_vec, 'Color',C_V, 'LineWidth',1.0);
hold on;
n_ann = min(P.top_n_peaks, length(mV.top_freqs));
for p = 1:n_ann
    xp = mV.top_freqs(p);  yp = mV.top_amps(p);
    plot(ax2, xp, yp, 'v', 'Color',C_V, 'MarkerFaceColor',C_V, 'MarkerSize',6);
    text(xp, yp*1.10, sprintf('#%d\n%.2f Hz', p, xp), ...
         'FontSize',7, 'HorizontalAlignment','center', ...
         'Color',C_V, 'Interpreter','none');
end
xlim([0 xlim_hz]);
xlabel('Frequency (Hz)'); ylabel('Magnitude (V)');
title(sprintf('Voltage FFT  [Fund: %.2f Hz  |  SNR: %.1f dB  |  THD: %.1f%%  |  R²: %.3f]', ...
              mV.fund_hz, mV.snr_db, mV.thd_pct, mV.sine_r2));
grid on; box on;

linkaxes([ax1,ax2],'x');

out_name = sprintf('%s_%s_FFT.%s', base_name, dt_str, P.save_format);
exportgraphics(fig, fullfile(dest_folder, out_name), 'Resolution',150);
fprintf('  FFT plot    → %s\n', out_name);
close(fig);
end


% -------------------------------------------------------------------------
%  §4.7  WRITE_SEPARATOR_SCRIPT
%
%  Generates a standalone MATLAB script inside the Defective folder.
%  Running it re-sorts defective files into sub-folders by tag keyword.
%
%  INPUTS:
%    defective_folder  (char)  Full path to the Defective/ folder.
%
%  OUTPUTS:
%    File written: <defective_folder>/separate_by_tag.m
% -------------------------------------------------------------------------
function write_separator_script(defective_folder)

out_path = fullfile(defective_folder, 'separate_by_tag.m');

lines = { ...
'% separate_by_tag.m  —  auto-generated by waveform_analyzer.m', ...
'% Run this to re-sort DEFECTIVE files into sub-folders by tag keyword.', ...
'% Edit TAG_MAP to add or rename categories.', ...
'clc; clear;', ...
sprintf('defective_folder = ''%s'';', strrep(defective_folder,'\','\\')), ...
'', ...
'TAG_MAP = {', ...
'    ''AMBIGUOUS_FREQ'',    ''Tag_AmbiguousFreq'';', ...
'    ''FREQ_MISMATCH'',     ''Tag_FreqMismatch'';', ...
'    ''LOW_SNR'',           ''Tag_LowSNR'';', ...
'    ''HIGH_THD'',          ''Tag_HighTHD'';', ...
'    ''NOT_SINUSOIDAL'',    ''Tag_NotSinusoidal'';', ...
'    ''FLAT'',              ''Tag_FlatSignal'';', ...
'    ''LEADING_ZEROS'',     ''Tag_EdgeZeros'';', ...
'    ''TRAILING_ZEROS'',    ''Tag_EdgeZeros'';', ...
'    ''NAN_INF'',           ''Tag_NaNInf'';', ...
'};', ...
'', ...
'files = dir(fullfile(defective_folder, ''*DEFECTIVE*.csv''));', ...
'for k = 1:length(files)', ...
'    fname   = files(k).name;', ...
'    matched = false;', ...
'    for t = 1:size(TAG_MAP,1)', ...
'        if contains(fname, TAG_MAP{t,1}, ''IgnoreCase'', true)', ...
'            dest = fullfile(defective_folder, TAG_MAP{t,2});', ...
'            if ~exist(dest,''dir''), mkdir(dest); end', ...
'            copyfile(fullfile(defective_folder,fname), fullfile(dest,fname));', ...
'            fprintf(''  %s  →  %s\n'', fname, TAG_MAP{t,2});', ...
'            matched = true; break;', ...
'        end', ...
'    end', ...
'    if ~matched', ...
'        fprintf(''  %s  →  (unmatched, stays in Defective/)\n'', fname);', ...
'    end', ...
'end', ...
'disp(''Separation complete.'');', ...
};

fid = fopen(out_path, 'w');
for i = 1:length(lines)
    fprintf(fid, '%s\n', lines{i});
end
fclose(fid);
fprintf('  Separator script → %s\n', out_path);
end


% -------------------------------------------------------------------------
%  §4.8  TERNARY  —  Inline conditional utility
%
%  INPUTS:
%    cond       (logical scalar)  Condition to test.
%    val_true   (any)             Returned when cond is true.
%    val_false  (any)             Returned when cond is false.
%
%  OUTPUT:
%    out  —  val_true or val_false.
% -------------------------------------------------------------------------
function out = ternary(cond, val_true, val_false)
if cond, out = val_true; else, out = val_false; end
end