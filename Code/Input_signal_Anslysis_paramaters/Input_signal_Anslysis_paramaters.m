%% ============================================================
%  EIS Input Data Analysis — Raw Signal Inspection + Quality Metrics
%  Version: 3.0
%
%  CSV column layout (after 15-line header skip):
%    Col 1 — Time
%    Col 2 — Shunt voltage  → current = col2 / SHUNT_RESISTANCE
%    Col 3 — Unused / ignored
%    Col 4 — Voltage sense (default, selectable up to col 7)
%
%  Per-file outputs:
%    (A) Signal plot  — 3 subplots (current+DC, voltage+DC, voltage AC)
%    (B) Metrics plot — signal quality summary table per file
%
%  End-of-run output:
%    (C) Combined metrics CSV  — one row per file, all metrics
%    (D) Combined metrics figure — scrollable uitable of all files
%
%  No filtering applied — raw data inspection only.
% ============================================================


%% ============================================================
%  SECTION 0 — CONFIGURATION
% ============================================================

SHUNT_RESISTANCE  = 0.0075;   % [Ω]  current = v_shunt / R_shunt
VOLTAGE_COL       = 4;         % Voltage column index (4–7)
TRIM_FRACTION     = 0.10;      % Fraction trimmed from each end (10%)
NUM_HEADER_LINES  = 15;        % CSV header lines before data
HEADER_ROW_DATE   = 14;        % Row index: acquisition date
HEADER_ROW_TIME   = 15;        % Row index: acquisition time
SAVE_FORMAT       = 'jpeg';     % Output image format
FIG_SIZE_SIGNAL   = [1400 800];  % Signal plot size [w h] px
FIG_SIZE_METRICS  = [900 560];   % Metrics table figure size [w h] px

% --- Frequency stability: window count for short-time FFT (STFT)
%     More windows = finer time resolution, less freq resolution
N_STFT_WINDOWS    = 8;

% --- Noise estimation: high-pass residual above this harmonic multiple
%     e.g. 5 means: noise = energy above 5× fundamental
NOISE_HARMONIC_CUTOFF = 5;


%% ============================================================
%  SECTION 1 — FOLDER SELECTION & FILE DISCOVERY
%  Outputs: folder (char), files (struct array)
% ============================================================

folder = uigetdir('', 'Select Folder Containing Waveform CSV Files');
if folder == 0, disp('Cancelled.'); return; end

files = dir(fullfile(folder, '*.csv'));
if isempty(files)
    errordlg('No CSV files found.', 'No Files'); return;
end
fprintf('\nFound %d CSV file(s) in:\n  %s\n\n', length(files), folder);

% Pre-allocate summary collector (cell array — rows added per file)
all_metrics = {};   % filled in loop, converted to table after


%% ============================================================
%  SECTION 2 — MAIN LOOP: READ → TRIM → METRICS → PLOT → SAVE
%  Inputs:  folder, files, all Section 0 constants
%  Outputs: signal PNG + metrics PNG per file; all_metrics populated
% ============================================================

for k = 1:length(files)

    filename = files(k).name;
    fullpath = fullfile(folder, filename);
    fprintf('[%d/%d] %s\n', k, length(files), filename);

    try

        % --------------------------------------------------------
        %  2.1  READ CSV DATA
        %  Inputs:  fullpath, NUM_HEADER_LINES, VOLTAGE_COL
        %  Outputs: t [s], current [A], voltage [V]
        % --------------------------------------------------------

        opts = detectImportOptions(fullpath, 'NumHeaderLines', NUM_HEADER_LINES);
        T    = readtable(fullpath, opts);
        T    = T(~all(ismissing(T(:, 1:4)), 2), :);   % drop blank boundary rows

        t_raw = T{:, 1};
        if isduration(t_raw) || isdatetime(t_raw)
            t = seconds(t_raw);
        else
            t = double(t_raw);
        end

        v_shunt = double(T{:, 2});
        current = v_shunt / SHUNT_RESISTANCE;   % [A]

        if VOLTAGE_COL < 4 || VOLTAGE_COL > width(T)
            error('VOLTAGE_COL=%d out of range (table has %d cols).', VOLTAGE_COL, width(T));
        end
        voltage = double(T{:, VOLTAGE_COL});   % [V]


        % --------------------------------------------------------
        %  2.2  PARSE ACQUISITION DATETIME FROM CSV HEADER
        %  Inputs:  fullpath, HEADER_ROW_DATE, HEADER_ROW_TIME
        %  Outputs: dt_str (char, 'yyyymmdd_HHMMSS')
        % --------------------------------------------------------

        dt_str = '';
        try
            optsH                   = detectImportOptions(fullpath);
            optsH.DataLines         = [HEADER_ROW_DATE, HEADER_ROW_TIME];
            optsH.VariableNamesLine = 0;
            optsH.Delimiter         = ',';
            optsH                   = setvartype(optsH, 2, 'string');
            Tinfo                   = readtable(fullpath, optsH);
            rawDate = strtrim(Tinfo{1, 2});
            rawTime = strtrim(Tinfo{2, 2});
            dt_csv  = datetime(rawDate + " " + rawTime, ...
                               'InputFormat', 'yyyy/MM/dd HH:mm:ss.SSSSSSSSS');
            dt_str  = datestr(dt_csv, 'yyyymmdd_HHMMSS');
        catch
            warning('  Could not parse header datetime — using file date.');
        end
        if isempty(dt_str)
            finfo  = dir(fullpath);
            dt_str = datestr(finfo.datenum, 'yyyymmdd_HHMMSS');
        end


        % --------------------------------------------------------
        %  2.3  TRIM SIGNALS (middle 80%)
        %  Inputs:  t, current, voltage, TRIM_FRACTION
        %  Outputs: t, current, voltage (trimmed)
        % --------------------------------------------------------

        n       = length(t);
        i_start = floor(TRIM_FRACTION * n) + 1;
        i_end   = floor((1 - TRIM_FRACTION) * n);
        t       = t(i_start:i_end);
        current = current(i_start:i_end);
        voltage = voltage(i_start:i_end);


        % --------------------------------------------------------
        %  2.4  SANITY CHECK
        % --------------------------------------------------------

        if isempty(t) || length(t) < 20 ...
                || any(isnan(t)) || any(isnan(current)) || any(isnan(voltage))
            warning('  "%s": invalid/short data — skipping.', filename);
            continue;
        end


        % --------------------------------------------------------
        %  2.5  BASIC SIGNAL PREPARATION
        %  Inputs:  t, current, voltage
        %  Outputs: Fs, t_rel, current_ac, voltage_ac,
        %           I_dc, V_dc, I_pk, V_pk
        % --------------------------------------------------------

        dt_s   = mean(diff(t));
        Fs     = 1 / dt_s;              % sampling frequency [Hz]
        t_rel  = t - t(1);              % time axis starting at 0 [s]

        I_dc   = mean(current);
        V_dc   = mean(voltage);

        current_ac = current - I_dc;    % AC component of current
        voltage_ac = voltage - V_dc;    % AC component of voltage

        I_pk   = max(abs(current_ac));  % peak AC current [A]
        V_pk   = max(abs(voltage_ac));  % peak AC voltage [V]


        % --------------------------------------------------------
        %  2.6  SIGNAL QUALITY METRICS
        %  Inputs:  current, current_ac, voltage, voltage_ac, t, Fs,
        %           N_STFT_WINDOWS, NOISE_HARMONIC_CUTOFF
        %  Outputs: metrics struct (I_ and V_ fields)
        % --------------------------------------------------------

        % --- Call metric function for current and voltage ---
        mI = compute_signal_metrics(current, current_ac, t, Fs, ...
                                    N_STFT_WINDOWS, NOISE_HARMONIC_CUTOFF);
        mV = compute_signal_metrics(voltage, voltage_ac, t, Fs, ...
                                    N_STFT_WINDOWS, NOISE_HARMONIC_CUTOFF);


        % --------------------------------------------------------
        %  2.7  PLOT A — SIGNAL WAVEFORMS (3 subplots, shared X)
        %  Inputs:  t_rel, current, voltage, voltage_ac,
        %           I_dc, V_dc, mI, mV, filename, dt_str
        %  Outputs: PNG saved to folder
        % --------------------------------------------------------

        C_I = [0.20 0.55 0.85];
        C_V = [0.85 0.33 0.10];

        fig_sig = figure('Name', sprintf('%s | %s', filename, dt_str), ...
                         'NumberTitle', 'off', ...
                         'Position',   [50 50 FIG_SIZE_SIGNAL(1) FIG_SIZE_SIGNAL(2)], ...
                         'Color', 'w');

        sgtitle(sprintf('Raw Signal Inspection  —  %s\n%s  |  I: %.2f Hz  |  V: %.2f Hz', ...
                filename, dt_str, mI.freq_hz, mV.freq_hz), ...
                'FontSize', 12, 'FontWeight', 'bold', 'Interpreter', 'none');

        ax1 = subplot(3,1,1);
        plot(t_rel, current, 'Color', C_I, 'LineWidth', 1.2);
        yline(I_dc, '--k', sprintf('DC = %.4f A', I_dc), ...
              'LineWidth', 0.8, 'LabelHorizontalAlignment', 'left');
        ylabel('Current (A)');
        title(sprintf('Current  [%.2f Hz  |  AC pk = %.4f A  |  THD = %.1f%%  |  SNR = %.1f dB]', ...
              mI.freq_hz, I_pk, mI.thd_pct, mI.snr_db));
        grid on; box on;

        ax2 = subplot(3,1,2);
        plot(t_rel, voltage, 'Color', C_V, 'LineWidth', 1.2);
        yline(V_dc, '--k', sprintf('DC = %.6f V', V_dc), ...
              'LineWidth', 0.8, 'LabelHorizontalAlignment', 'left');
        ylabel('Voltage (V)');
        title(sprintf('Voltage col%d  [%.2f Hz  |  AC pk = %.6f V  |  THD = %.1f%%  |  SNR = %.1f dB]', ...
              VOLTAGE_COL, mV.freq_hz, V_pk, mV.thd_pct, mV.snr_db));
        grid on; box on;

        ax3 = subplot(3,1,3);
        plot(t_rel, voltage_ac, 'Color', C_V, 'LineWidth', 1.2);
        yline(0, '--k', 'LineWidth', 0.8);
        ylabel('Voltage AC (V)');
        xlabel('Time (s)');
        title(sprintf('Voltage col%d — AC only  [RMS = %.6f V  |  Crest = %.2f  |  Freq drift = %.1f%%]', ...
              VOLTAGE_COL, mV.ac_rms, mV.crest_factor, mV.freq_drift_pct));
        grid on; box on;

        linkaxes([ax1, ax2, ax3], 'x');
        xlim(ax1, [t_rel(1) t_rel(end)]);

        [~, base, ~] = fileparts(filename);
        out_sig = sprintf('%s_%s_Signal.%s', base, dt_str, SAVE_FORMAT);
        exportgraphics(fig_sig, fullfile(folder, out_sig), 'Resolution', 150);
        fprintf('  Signal plot saved: %s\n', out_sig);
        close(fig_sig);


        % --------------------------------------------------------
        %  2.8  PLOT B — METRICS SUMMARY TABLE (per file)
        %  Inputs:  mI, mV, filename, dt_str, I_dc, V_dc, I_pk, V_pk, Fs
        %  Outputs: PNG saved to folder
        % --------------------------------------------------------

        % --------------------------------------------------------
        %  2.8  SAVE METRICS SUMMARY AS A TEXT FILE (per file)
        %  Inputs:  mI, mV, filename, dt_str, I_dc, V_dc, I_pk, V_pk, Fs
        %  Outputs: TXT file saved to folder
        % --------------------------------------------------------
        I_name = sprintf('Current @ %.1f Hz', mI.freq_hz);
        V_name = sprintf('Voltage col%d @ %.1f Hz', VOLTAGE_COL, mV.freq_hz);
        clip_I = 'No'; if mI.clipping, clip_I = 'YES ⚠'; end
        clip_V = 'No'; if mV.clipping, clip_V = 'YES ⚠'; end
        
        [~, base, ~] = fileparts(filename);
        out_txt = sprintf('%s_%s_Metrics.txt', base, dt_str);
        txt_path = fullfile(folder, out_txt);
        
        fid = fopen(txt_path, 'w');
        if fid ~= -1
            fprintf(fid, '==================================================\n');
            fprintf(fid, 'SIGNAL QUALITY METRICS REPORT\n');
            fprintf(fid, 'File: %s\n', filename);
            fprintf(fid, 'Acquisition Datetime: %s\n', dt_str);
            fprintf(fid, '==================================================\n\n');
            
            % Print header format
            fprintf(fid, '%-35s | %-25s | %-25s\n', 'Metric Description', I_name, V_name);
            fprintf(fid, '%s\n', repmat('-', 1, 93));
            
            % Print rows
            fprintf(fid, '%-35s | %-25.4f | %-25.4f\n', 'Dominant Frequency (Hz)', mI.freq_hz, mV.freq_hz);
            fprintf(fid, '%-35s | %-25.6f A | %-25.8f V\n', 'DC Offset', I_dc, V_dc);
            fprintf(fid, '%-35s | %-25.6f A | %-25.8f V\n', 'AC Peak Amplitude', I_pk, V_pk);
            fprintf(fid, '%-35s | %-25.6f A | %-25.8f V\n', 'AC RMS', mI.ac_rms, mV.ac_rms);
            fprintf(fid, '%-35s | %-25.3f | %-25.3f\n', 'Crest Factor (pk/rms)', mI.crest_factor, mV.crest_factor);
            fprintf(fid, '%-35s | %-25.6f A | %-25.8f V\n', 'Signal RMS (full, with DC)', mI.full_rms, mV.full_rms);
            fprintf(fid, '%-35s | %-25.2f dB | %-25.2f dB\n', 'SNR (dB)', mI.snr_db, mV.snr_db);
            fprintf(fid, '%-35s | %-25.2f %% | %-25.2f %%\n', 'THD (%)', mI.thd_pct, mV.thd_pct);
            fprintf(fid, '%-35s | %-25.6f A | %-25.8f V\n', 'Noise Floor RMS', mI.noise_rms, mV.noise_rms);
            fprintf(fid, '%-35s | %-25.3f %% | %-25.3f %%\n', 'Noise-to-Signal Ratio (%)', mI.nsr_pct, mV.nsr_pct);
            fprintf(fid, '%-35s | %-25.2f %% | %-25.2f %%\n', 'Frequency Drift (%)', mI.freq_drift_pct, mV.freq_drift_pct);
            fprintf(fid, '%-35s | %-25.4f Hz | %-25.4f Hz\n', 'Frequency Std Dev (Hz)', mI.freq_std_hz, mV.freq_std_hz);
            fprintf(fid, '%-35s | %-25.2f %% | %-25.2f %%\n', 'Amplitude Modulation (%)', mI.am_pct, mV.am_pct);
            fprintf(fid, '%-35s | %-25.3f %% | %-25.3f %%\n', 'DC Drift (end-start, % of mean)', mI.dc_drift_pct, mV.dc_drift_pct);
            fprintf(fid, '%-35s | %-25.4f | %-25.4f\n', 'Waveform Symmetry (skewness)', mI.skewness, mV.skewness);
            fprintf(fid, '%-35s | %-25s | %-25s\n', 'Clipping Detected', clip_I, clip_V);
            fprintf(fid, '%-35s | %-25d | %-25d\n', 'Samples', mI.n_samples, mV.n_samples);
            fprintf(fid, '%-35s | %-25.1f Hz | %-25.1f Hz\n', 'Sampling Rate (Hz)', Fs, Fs);
            fprintf(fid, '%-35s | %-25.2f ms | %-25.2f ms\n', 'Signal Duration (ms)', mI.duration_ms, mV.duration_ms);
            
            fclose(fid);
            fprintf('  Metrics text file saved: %s\n', out_txt);
        else
            warning('  Could not create text file: %s', txt_path);
        end


        % --------------------------------------------------------
        %  2.9  APPEND ROW TO COMBINED SUMMARY
        %  Inputs:  filename, dt_str, mI, mV, I_dc, V_dc, Fs
        %  Outputs: row appended to all_metrics cell array
        % --------------------------------------------------------

        row = {
            filename, dt_str, ...
            Fs, mI.n_samples, mI.duration_ms, ...
            % --- Current ---
            mI.freq_hz, I_dc, I_pk, mI.ac_rms, mI.full_rms, ...
            mI.crest_factor, mI.snr_db, mI.thd_pct, ...
            mI.noise_rms, mI.nsr_pct, mI.freq_drift_pct, mI.freq_std_hz, ...
            mI.am_pct, mI.dc_drift_pct, mI.skewness, double(mI.clipping), ...
            % --- Voltage ---
            mV.freq_hz, V_dc, V_pk, mV.ac_rms, mV.full_rms, ...
            mV.crest_factor, mV.snr_db, mV.thd_pct, ...
            mV.noise_rms, mV.nsr_pct, mV.freq_drift_pct, mV.freq_std_hz, ...
            mV.am_pct, mV.dc_drift_pct, mV.skewness, double(mV.clipping)
        };
        all_metrics(end+1, :) = row; %#ok<AGROW>

    catch ME
        warning('  ERROR "%s": %s  (line %d in %s)', ...
                filename, ME.message, ME.stack(1).line, ME.stack(1).name);
    end

end % end file loop


%% ============================================================
%  SECTION 3 — COMBINED SUMMARY TABLE (all files)
%  Inputs:  all_metrics (cell array), folder
%  Outputs: summary CSV + combined metrics figure
% ============================================================

if isempty(all_metrics)
    disp('No files processed successfully.'); return;
end

col_headers = { ...
    'Filename', 'Datetime', ...
    'Fs_Hz', 'N_Samples', 'Duration_ms', ...
    'I_Freq_Hz',   'I_DC_A',       'I_Pk_A',      'I_AC_RMS_A',   'I_Full_RMS_A', ...
    'I_Crest',     'I_SNR_dB',     'I_THD_pct',   'I_Noise_RMS',  'I_NSR_pct', ...
    'I_FreqDrift', 'I_FreqStd_Hz', 'I_AM_pct',    'I_DCDrift_pct','I_Skewness', 'I_Clipping', ...
    'V_Freq_Hz',   'V_DC_V',       'V_Pk_V',      'V_AC_RMS_V',   'V_Full_RMS_V', ...
    'V_Crest',     'V_SNR_dB',     'V_THD_pct',   'V_Noise_RMS',  'V_NSR_pct', ...
    'V_FreqDrift', 'V_FreqStd_Hz', 'V_AM_pct',    'V_DCDrift_pct','V_Skewness', 'V_Clipping' ...
};

T_summary = cell2table(all_metrics, 'VariableNames', col_headers);

csv_path = fullfile(folder, 'SignalQuality_Summary.csv');
writetable(T_summary, csv_path);
fprintf('\nSummary CSV saved: SignalQuality_Summary.csv\n');

% --- Combined figure: scrollable uitable ---
fig_all = figure('Name', 'Signal Quality — All Files', ...
                 'NumberTitle', 'off', ...
                 'Position', [50 50 1600 600], ...
                 'Color', 'w');

sgtitle('Signal Quality Metrics — All Files', ...
        'FontSize', 13, 'FontWeight', 'bold');

% Show only human-readable subset (key columns) in figure
% Full data is in the CSV
display_cols = {'Filename', ...
    'I_Freq_Hz','I_SNR_dB','I_THD_pct','I_FreqDrift','I_AM_pct','I_Clipping', ...
    'V_Freq_Hz','V_SNR_dB','V_THD_pct','V_FreqDrift','V_AM_pct','V_Clipping'};

T_display = T_summary(:, display_cols);

% Format numerics to 3 decimal places for display
display_data = table2cell(T_display);
for col = 2:width(T_display)
    for row = 1:height(T_display)
        val = display_data{row, col};
        if isnumeric(val)
            display_data{row, col} = sprintf('%.3f', val);
        end
    end
end

uitable(fig_all, ...
    'Data',        display_data, ...
    'ColumnName',  display_cols, ...
    'Units',       'normalized', ...
    'Position',    [0.01 0.01 0.98 0.88], ...
    'FontSize',    9, ...
    'RowName',     [], ...
    'ColumnWidth', [200, repmat({90}, 1, length(display_cols)-1)]);

exportgraphics(fig_all, fullfile(folder, sprintf('SignalQuality_AllFiles.%s', SAVE_FORMAT)), ...
               'Resolution', 150);
fprintf('Combined summary figure saved: SignalQuality_AllFiles.%s\n', SAVE_FORMAT);

fprintf('\nAll done.\nOutputs in: %s\n', folder);


%% ============================================================
%  LOCAL FUNCTION — compute_signal_metrics
%
%  Computes all signal quality metrics for one signal channel.
%
%  Inputs:
%    sig_full  — raw signal with DC  [N×1]
%    sig_ac    — signal minus mean   [N×1]
%    t         — time vector [s]     [N×1]
%    Fs        — sampling frequency [Hz]
%    n_windows — number of STFT windows for frequency stability
%    noise_h   — harmonic multiple above which energy = noise
%
%  Outputs:
%    m  — struct with fields:
%          freq_hz        dominant frequency [Hz]
%          ac_rms         AC RMS (no DC)
%          full_rms       RMS of full signal (with DC)
%          crest_factor   peak / AC RMS
%          snr_db         signal-to-noise ratio [dB]
%          thd_pct        total harmonic distortion [%]
%          noise_rms      estimated noise RMS
%          nsr_pct        noise-to-signal ratio [%]
%          freq_drift_pct (max-min) / mean freq across windows [%]
%          freq_std_hz    std dev of per-window frequencies [Hz]
%          am_pct         amplitude modulation depth [%]
%          dc_drift_pct   DC drift end vs start [% of mean]
%          skewness       waveform skewness (asymmetry)
%          clipping       logical: true if likely clipped
%          n_samples      number of samples
%          duration_ms    signal duration [ms]
% ============================================================

function m = compute_signal_metrics(sig_full, sig_ac, t, Fs, n_windows, noise_h)

   % FORCE INPUTS TO BE VERTICAL COLUMN VECTORS TO PREVENT MATRICES MISMATCHES
    sig_full = sig_full(:);
    sig_ac   = sig_ac(:);
    t        = t(:);

    N  = length(sig_ac);
    dt = 1/Fs;
    m.n_samples   = N;
    m.duration_ms = (t(end) - t(1)) * 1000;

    % ----------------------------------------------------------
    % Dominant frequency via FFT on AC signal
    % ----------------------------------------------------------
    halfN     = floor(N/2);
    f_axis    = Fs * (0:halfN) / N;
    Y         = fft(sig_ac);
    Y_pos     = Y(1:halfN+1);
    amp       = abs(Y_pos) / N;
    amp(2:end-1) = 2 * amp(2:end-1);   % one-sided correction

    [~, idx_f]  = max(amp(2:end));     % skip DC bin
    idx_f       = idx_f + 1;
    m.freq_hz   = f_axis(idx_f);

    % Fundamental amplitude (at dominant frequency bin)
    A1 = amp(idx_f);

    % ----------------------------------------------------------
    % AC RMS, full RMS, crest factor
    % ----------------------------------------------------------
    m.ac_rms      = rms(sig_ac);
    m.full_rms    = rms(sig_full);
    if m.ac_rms > 0
        m.crest_factor = max(abs(sig_ac)) / m.ac_rms;
    else
        m.crest_factor = NaN;
    end

    % ----------------------------------------------------------
    % Noise estimation: energy above noise_h × fundamental
    % ----------------------------------------------------------
    noise_cutoff_hz = noise_h * m.freq_hz;
    noise_mask      = f_axis > noise_cutoff_hz;
    if any(noise_mask)
        % Noise power from high-frequency tail of one-sided spectrum
        noise_amp       = amp(noise_mask);
        m.noise_rms     = sqrt(sum(noise_amp.^2 / 2));  % approx RMS from amplitudes
    else
        m.noise_rms     = 0;
    end

    % SNR: signal power at fundamental vs noise floor
    if m.noise_rms > 0
        m.snr_db = 20 * log10(A1 / m.noise_rms);
    else
        m.snr_db = Inf;
    end

    % Noise-to-signal ratio as percentage
    if A1 > 0
        m.nsr_pct = (m.noise_rms / A1) * 100;
    else
        m.nsr_pct = NaN;
    end

    % ----------------------------------------------------------
    % THD: total harmonic distortion
    % THD = sqrt(sum of harmonic amplitudes^2) / fundamental × 100%
    % Harmonics: 2f, 3f, 4f, ... up to Nyquist
    % ----------------------------------------------------------
    harm_amp_sq = 0;
    h = 2;
    while h * m.freq_hz < Fs/2
        f_harm = h * m.freq_hz;
        % Find nearest FFT bin
        [~, idx_h] = min(abs(f_axis - f_harm));
        harm_amp_sq = harm_amp_sq + amp(idx_h)^2;
        h = h + 1;
    end
    if A1 > 0
        m.thd_pct = (sqrt(harm_amp_sq) / A1) * 100;
    else
        m.thd_pct = NaN;
    end

    % ----------------------------------------------------------
    % Frequency stability: short-time FFT across n_windows
    % Split signal into windows, find dominant freq in each
    % ----------------------------------------------------------
    win_len    = floor(N / n_windows);
    win_freqs  = zeros(1, n_windows);
    win_amps   = zeros(1, n_windows);

    for w = 1:n_windows
        i1 = (w-1)*win_len + 1;
        i2 = min(i1 + win_len - 1, N);
        seg = sig_ac(i1:i2);
        M   = length(seg);
        hM  = floor(M/2);
        fa  = Fs * (0:hM) / M;
        Ya  = fft(seg);
        aa  = abs(Ya(1:hM+1)) / M;
        aa(2:end-1) = 2*aa(2:end-1);
        [pk_a, pk_i] = max(aa(2:end));
        win_freqs(w) = fa(pk_i+1);
        win_amps(w)  = pk_a;
    end

    mean_f = mean(win_freqs);
    if mean_f > 0
        m.freq_drift_pct = (max(win_freqs) - min(win_freqs)) / mean_f * 100;
    else
        m.freq_drift_pct = NaN;
    end
    m.freq_std_hz = std(win_freqs);

    % ----------------------------------------------------------
    % Amplitude modulation depth
    % Envelope = abs of analytic signal (Hilbert transform)
    % AM % = (max_env - min_env) / mean_env × 100
    % ----------------------------------------------------------
    try
        env      = abs(hilbert(sig_ac));
        mean_env = mean(env);
        if mean_env > 0
            m.am_pct = (max(env) - min(env)) / mean_env * 100;
        else
            m.am_pct = NaN;
        end
    catch
        m.am_pct = NaN;
    end

    % ----------------------------------------------------------
    % DC drift: compare mean of first 10% vs last 10% of full signal
    % ----------------------------------------------------------
    seg_len   = max(1, floor(0.10 * N));
    dc_start  = mean(sig_full(1:seg_len));
    dc_end    = mean(sig_full(end-seg_len+1:end));
    mean_full = mean(sig_full);
    if abs(mean_full) > 1e-12
        m.dc_drift_pct = abs(dc_end - dc_start) / abs(mean_full) * 100;
    else
        m.dc_drift_pct = abs(dc_end - dc_start) * 100;
    end

    % ----------------------------------------------------------
    % Waveform skewness (asymmetry of AC signal distribution)
    % Pure sine = 0; asymmetric waveform ≠ 0
    % ----------------------------------------------------------
    if std(sig_ac) > 0
        m.skewness = mean((sig_ac - mean(sig_ac)).^3) / std(sig_ac)^3;
    else
        m.skewness = 0;
    end

    % ----------------------------------------------------------
    % Clipping detection:
    % Flag if >0.5% of samples sit within 1% of max or min value
    % ----------------------------------------------------------
    sig_range = max(sig_full) - min(sig_full);
    if sig_range > 0
        clip_thresh = 0.01 * sig_range;
        near_max = sum(sig_full >= max(sig_full) - clip_thresh);
        near_min = sum(sig_full <= min(sig_full) + clip_thresh);
        clip_frac = (near_max + near_min) / N;
        m.clipping = clip_frac > 0.005;
    else
        m.clipping = false;
    end

end