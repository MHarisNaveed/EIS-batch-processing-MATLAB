% ================================================================
%  EIS WAVEFORM PROCESSING PIPELINE  --  v2
%  Fixes applied vs v1:
%   A. CFC class auto-selected per file frequency (1 Hz to 5 kHz)
%   B. Time vector always absolute elapsed seconds from zero
%   C. Frame detection handles signals with DC offset / bad edges
% ================================================================

%% ---------------------------------------------------------------
%  USER-TUNABLE PARAMETERS
% ---------------------------------------------------------------
% --- CFC filter ---
% USE_CFC = true  : SAE J211 CFC, class auto-selected from final_freq
% USE_CFC = false : Butterworth at CFC_BUTTER_MULT x fundamental freq
USE_CFC            = true;
CFC_FORCE_CLASS    = 0;    % 0 = auto | or force: 60 / 180 / 600 / 1000
CFC_BUTTER_MULT    = 3;    % multiplier used when USE_CFC = false
%
%  Auto-select rules  (corner = class x 5/3):
%   CFC  60  ->  100 Hz corner  -> use when fund. freq <=  33 Hz
%   CFC 180  ->  300 Hz corner  -> use when fund. freq <= 100 Hz
%   CFC 600  -> 1000 Hz corner  -> use when fund. freq <= 333 Hz
%   CFC 1000 -> 1650 Hz corner  -> use when fund. freq <= 550 Hz
%   > 550 Hz -> no standard CFC; fallback to Butterworth 3x freq

% --- Drift correction ---
DRIFT_CORRECT      = true;
DRIFT_POLY_ORDER   = 2;      % 1=linear ramp, 2=bow, 3=cubic
DRIFT_THRESH_RATIO = 0.05;   % flag if trend amplitude > 5% of AC amp

% --- Frame detection (set false to pass all cycles through) ---
FRAME_DETECTION_ON = false;  % false = disabled, no frames skipped
FRAME_AMP_TOL      = 0.25;   % max amplitude deviation (fraction of median)
FRAME_PERIOD_TOL   = 0.20;   % max period deviation (fraction of median)
FRAME_MIN_SNR_DB   = 10;     % min per-frame SNR in dB
FRAME_BAD_MAX_FRAC = 0.40;   % skip file if more than 40% frames bad
FRAME_EDGE_GUARD_HALF_PERIODS = 1.0;  % half-periods to ignore at edges

% --- Trim fraction (keep middle 80% of raw record before framing) ---
TRIM_FRAC = 0.10;

% ================================================================

%% Select folder
folder = uigetdir('', 'Select Folder Containing Waveform CSV Files');
if folder == 0
    disp('Folder selection cancelled.');
    return;
end

files = dir(fullfile(folder, '*.csv'));

% --- Accumulators ---
all_freqs         = [];
all_mag_Z1_raw    = [];  all_mag_Z1_s      = [];
all_phase_V1I_raw = [];  all_phase_V1I_s   = [];
all_Z1_peak_raw   = [];  all_Z1_peak_s     = [];
all_mag_Z2_raw    = [];  all_mag_Z2_s      = [];
all_phase_V2I_raw = [];  all_phase_V2I_s   = [];
all_Z2_peak_raw   = [];  all_Z2_peak_s     = [];

T_summary_data = {};

for k = 1:length(files)
    filename = files(k).name;
    fullpath = fullfile(folder, filename);

    try
        %% ---------------------------------------------------
        %  READ CSV
        % ---------------------------------------------------
        opts = detectImportOptions(fullpath, 'NumHeaderLines', 15);
        T    = readtable(fullpath, opts);
        T    = T(~all(ismissing(T(:, 1:4)), 2), :);

        % --- FIX B: absolute elapsed time starting from zero ---
        % datetime: subtract first sample as reference, then to seconds.
        %   (calling seconds(datetime) gives seconds-since-year-0,
        %    a ~6e10 number that destroys relative spacing precision)
        % duration: convert to numeric then re-zero.
        % numeric:  just re-zero.
        t_raw = T{:,1};
        if isdatetime(t_raw)
            t = seconds(t_raw - t_raw(1));
        elseif isduration(t_raw)
            t = seconds(t_raw);
            t = t - t(1);
        else
            t = double(t_raw);
            t = t - t(1);
        end

        % --- Extract datetime from header rows 14-15 ---
        optsH = detectImportOptions(fullpath);
        optsH.DataLines        = [14 15];
        optsH.VariableNamesLine = 0;
        optsH.Delimiter        = ',';
        optsH = setvartype(optsH, 2, 'string');
        Tinfo   = readtable(fullpath, optsH);
        rawDate = strtrim(Tinfo{1,2});
        rawTime = strtrim(Tinfo{2,2});
        dt_csvscope = datetime(rawDate + " " + rawTime, ...
                               'InputFormat','yyyy/MM/dd HH:mm:ss.SSSSSSSSS');
        dt_str = datestr(dt_csvscope, 'yyyymmdd_HHMMSS');
        if isempty(dt_str)
            fi     = dir(fullpath);
            dt_str = datestr(fi.datenum, 'yyyymmdd_HHMMSS');
        end

        v_shunt  = double(T{:,2});
        current  = v_shunt / 0.0075;
        voltage1 = double(T{:,4});
        voltage2 = double(T{:,5});

        % --- Coarse trim: keep middle 80% ---
        n_total  = length(t);
        i_start  = floor(TRIM_FRAC * n_total) + 1;
        i_end    = floor((1 - TRIM_FRAC) * n_total);
        t        = t(i_start:i_end);
        current  = current(i_start:i_end);
        voltage1 = voltage1(i_start:i_end);
        voltage2 = voltage2(i_start:i_end);

        % Sanity check
        if any(isnan(t)) || any(isnan(current)) || any(isnan(voltage1)) || ...
                any(isnan(voltage2)) || isempty(t) || length(t) < 10
            warning('"%s": invalid or too-short data -- skipping.', filename);
            continue;
        end

        Fs = 1 / mean(diff(t));

        %% ---------------------------------------------------
        %  DRIFT DETECTION & CORRECTION
        %  Applied to full AC+DC signal before any filtering.
        %  Subtracts only the non-constant polynomial trend so
        %  the DC operating point and AC amplitude are preserved.
        % ---------------------------------------------------
        if DRIFT_CORRECT
            [current,  dI]  = correct_drift(current,  t, DRIFT_POLY_ORDER, DRIFT_THRESH_RATIO);
            [voltage1, dV1] = correct_drift(voltage1, t, DRIFT_POLY_ORDER, DRIFT_THRESH_RATIO);
            [voltage2, dV2] = correct_drift(voltage2, t, DRIFT_POLY_ORDER, DRIFT_THRESH_RATIO);
            if dI || dV1 || dV2
                fprintf('[DRIFT] "%s": corrected I:%d V1:%d V2:%d\n', ...
                        filename, dI, dV1, dV2);
            end
        end

        %% ---------------------------------------------------
        %  FRAME DETECTION (optional -- controlled by FRAME_DETECTION_ON)
        % ---------------------------------------------------
        [freq_est, ~] = estimate_freq_amp(current, t);

        if FRAME_DETECTION_ON
            [current, voltage1, voltage2, t, frame_report] = ...
                frame_sync_and_clean(current, voltage1, voltage2, t, ...
                                     freq_est, Fs, ...
                                     FRAME_AMP_TOL, FRAME_PERIOD_TOL, ...
                                     FRAME_MIN_SNR_DB, FRAME_BAD_MAX_FRAC, ...
                                     FRAME_EDGE_GUARD_HALF_PERIODS);

            if isempty(current)
                warning('"%s": too many bad frames -- skipping.', filename);
                continue;
            end

            fprintf('[FRAMES] "%s": %d total | %d dropped | %s\n', ...
                    filename, frame_report.n_total, ...
                    frame_report.n_dropped, frame_report.reason);
        end  % FRAME_DETECTION_ON

        %% ---------------------------------------------------
        %  FINAL FREQUENCY ESTIMATE (post-cleaning)
        % ---------------------------------------------------
        [fc_i, ~]   = estimate_freq_amp(current,  t);
        [fc_v1, ~]  = estimate_freq_amp(voltage1, t);
        [fc_v2, ~]  = estimate_freq_amp(voltage2, t);
        final_freq  = median([fc_i, fc_v1, fc_v2]);

        %% ---------------------------------------------------
        %  RENAME / COPY
        % ---------------------------------------------------
        newname = sprintf('Waveform_%s_%dHz.csv', dt_str, abs(round(final_freq)));
        newpath = fullfile(folder, newname);
        if exist(newpath, 'file')
            [~, base, ~] = fileparts(newname);
            newname = sprintf('%s_dup_%s.csv', base, dt_str);
            newpath = fullfile(folder, newname);
        end
        copyfile(fullpath, newpath);
        fprintf('[RENAME] "%s" -> "%s" | %.2f Hz\n', filename, newname, final_freq);
        [~, base, ~] = fileparts(newname);

        %% ---------------------------------------------------
        %  FIX A: FILTERING -- CFC auto-selected or Butterworth
        % ---------------------------------------------------
        if USE_CFC
            [current_s, voltage1_s, voltage2_s, filter_label] = ...
                apply_cfc_filter(current, voltage1, voltage2, Fs, ...
                                 final_freq, CFC_FORCE_CLASS, CFC_BUTTER_MULT);
        else
            fc_but = CFC_BUTTER_MULT * final_freq;
            Wn     = min(fc_but / (Fs/2), 0.99);
            [b, a] = butter(4, Wn, 'low');
            current_s  = filtfilt(b, a, current);
            voltage1_s = filtfilt(b, a, voltage1);
            voltage2_s = filtfilt(b, a, voltage2);
            filter_label = sprintf('Butter-%dx(%.1fHz)', CFC_BUTTER_MULT, final_freq);
        end

        %% ---------------------------------------------------
        %  WAVEFORM PLOT  -- saved as JPEG, no display
        % ---------------------------------------------------
        fh = figure('Name', newname, 'NumberTitle', 'off', 'Visible', 'off');

        subplot(3,1,1);
        plot(t, current,   'Color', [0.30 0.75 0.93], 'LineWidth', 2.4); hold on;
        plot(t, current_s, 'k', 'LineWidth', 1);
        title(sprintf('Current vs Time  [%s]', filter_label));
        xlabel('Time (s)'); ylabel('Current (A)');
        legend('Raw', 'Filtered'); grid on;

        subplot(3,1,2);
        plot(t, voltage1,   'r', 'LineWidth', 1); hold on;
        plot(t, voltage1_s, 'k', 'LineWidth', 1);
        title('Voltage 1 vs Time');
        xlabel('Time (s)'); ylabel('Voltage 1 (V)');
        legend('Raw', 'Filtered'); grid on;

        subplot(3,1,3);
        plot(t, voltage2,   'g', 'LineWidth', 1); hold on;
        plot(t, voltage2_s, 'k', 'LineWidth', 1);
        title('Voltage 2 vs Time');
        xlabel('Time (s)'); ylabel('Voltage 2 (V)');
        legend('Raw', 'Filtered'); grid on;

        saveas(fh, fullfile(folder, [base, '_waveform.jpg']));
        close(fh);

        %% ---------------------------------------------------
        %  IMPEDANCE & PHASE
        % ---------------------------------------------------
        [main_freq, v1_main, v2_main, ...
         i_amp_yes_dc_raw,  i_amp_yes_dc_s,  i_amp_no_dc_raw,  i_amp_no_dc_s, ...
         v1_amp_yes_dc_raw, v1_amp_yes_dc_s, v1_amp_no_dc_raw, v1_amp_no_dc_s, ...
         v2_amp_yes_dc_raw, v2_amp_yes_dc_s, v2_amp_no_dc_raw, v2_amp_no_dc_s, ...
         Z1_mag_raw, Z2_mag_raw, Z1_phase_raw, Z2_phase_raw, Z1_peak_raw, Z2_peak_raw, ...
         Z1_mag_s,   Z2_mag_s,   Z1_phase_s,   Z2_phase_s,   Z1_peak_s,   Z2_peak_s] ...
         = phase_shift_fft(voltage1, voltage2, current, ...
                           voltage1_s, voltage2_s, current_s, t);

        %% ---------------------------------------------------
        %  ACCUMULATE
        % ---------------------------------------------------
        fmt6 = @(x) round(x, 6);
        row = { fmt6(main_freq), fmt6(v1_main), fmt6(v2_main), ...
                fmt6(i_amp_yes_dc_raw),  fmt6(i_amp_yes_dc_s), ...
                fmt6(i_amp_no_dc_raw),   fmt6(i_amp_no_dc_s), ...
                fmt6(v1_amp_yes_dc_raw), fmt6(v1_amp_yes_dc_s), ...
                fmt6(v1_amp_no_dc_raw),  fmt6(v1_amp_no_dc_s), ...
                fmt6(v2_amp_yes_dc_raw), fmt6(v2_amp_yes_dc_s), ...
                fmt6(v2_amp_no_dc_raw),  fmt6(v2_amp_no_dc_s), ...
                fmt6(Z1_mag_raw),   fmt6(Z1_mag_s), ...
                fmt6(Z2_mag_raw),   fmt6(Z2_mag_s), ...
                fmt6(Z1_phase_raw), fmt6(Z1_phase_s), ...
                fmt6(Z2_phase_raw), fmt6(Z2_phase_s) };
        T_summary_data = [T_summary_data; row];

        all_freqs(end+1)         = main_freq;
        all_mag_Z1_raw(end+1)    = Z1_mag_raw;
        all_mag_Z1_s(end+1)      = Z1_mag_s;
        all_phase_V1I_raw(end+1) = Z1_phase_raw;
        all_phase_V1I_s(end+1)   = Z1_phase_s;
        all_Z1_peak_raw(end+1)   = Z1_peak_raw;
        all_Z1_peak_s(end+1)     = Z1_peak_s;
        all_mag_Z2_raw(end+1)    = Z2_mag_raw;
        all_mag_Z2_s(end+1)      = Z2_mag_s;
        all_phase_V2I_raw(end+1) = Z2_phase_raw;
        all_phase_V2I_s(end+1)   = Z2_phase_s;
        all_Z2_peak_raw(end+1)   = Z2_peak_raw;
        all_Z2_peak_s(end+1)     = Z2_peak_s;

    catch ME
        warning('Error processing "%s": %s', filename, ME.message);
    end
end

disp('All files processed -- building summary outputs...');

%% ================================================================
%  SUMMARY TABLE  -- CSV + JPEG
% ================================================================
colNames = { ...
    'I Fr (Hz)', 'V1 Fr (Hz)', 'V2 Fr (Hz)', ...
    'I Amp DC raw',    'I Amp DC Sm', ...
    'I Amp NO DC raw', 'I Amp NO DC Sm', ...
    'V1 Amp DC raw',   'V1 Amp DC Sm', ...
    'V1 Amp NO DC raw','V1 Amp NO DC Sm', ...
    'V2 Amp DC raw',   'V2 Amp DC Sm', ...
    'V2 Amp NO DC raw','V2 Amp NO DC Sm', ...
    'Raw Imp Z1 (mOhm)',   'Smoothed Imp Z1 (mOhm)', ...
    'Raw Imp Z2 (mOhm)',   'Smoothed Imp Z2 (mOhm)', ...
    'Raw Phase Z1 (deg)',  'Smoothed Phase Z1 (deg)', ...
    'Raw Phase Z2 (deg)',  'Smoothed Phase Z2 (deg)' };

T_summary = cell2table(T_summary_data, 'VariableNames', colNames);
writetable(T_summary, fullfile(folder, 'summary_table.csv'));
disp('Saved: summary_table.csv');

data6   = arrayfun(@(x) sprintf('%.6f', x), T_summary{:,:}, 'UniformOutput', false);
fh_tbl  = figure('Name', 'Summary Table', 'NumberTitle', 'off', ...
                 'Position', [100 100 1400 400], 'Visible', 'off');
uitable('Data', data6, 'ColumnName', T_summary.Properties.VariableNames, ...
        'Units', 'Normalized', 'Position', [0 0 1 1], 'FontSize', 9);
saveas(fh_tbl, fullfile(folder, 'summary_table.jpg'));
close(fh_tbl);

%% ================================================================
%  BODE PLOT  -- JPEG
% ================================================================
if ~isempty(all_freqs)
    [all_freqs, sortIdx] = sort(all_freqs);
    all_mag_Z1_raw    = all_mag_Z1_raw(sortIdx);
    all_mag_Z1_s      = all_mag_Z1_s(sortIdx);
    all_phase_V1I_raw = all_phase_V1I_raw(sortIdx);
    all_phase_V1I_s   = all_phase_V1I_s(sortIdx);
    all_mag_Z2_raw    = all_mag_Z2_raw(sortIdx);
    all_mag_Z2_s      = all_mag_Z2_s(sortIdx);
    all_phase_V2I_raw = all_phase_V2I_raw(sortIdx);
    all_phase_V2I_s   = all_phase_V2I_s(sortIdx);
    all_Z1_peak_raw   = all_Z1_peak_raw(sortIdx);
    all_Z1_peak_s     = all_Z1_peak_s(sortIdx);
    all_Z2_peak_raw   = all_Z2_peak_raw(sortIdx);
    all_Z2_peak_s     = all_Z2_peak_s(sortIdx);

    fh_bode = figure('Name', 'Bode', 'NumberTitle', 'off', ...
                     'Visible', 'off', 'Position', [100 100 1200 800]);

    ax1 = subplot(2,1,1);
    yyaxis left
    plot(all_freqs, all_mag_Z1_raw, '-og', 'LineWidth', 1.5); hold on;
    plot(all_freqs, all_mag_Z1_s,   '--ok', 'LineWidth', 1.5);
    ylabel('Z1 Impedance (mOhm)');
    yyaxis right
    plot(all_freqs, all_phase_V1I_raw, '-sr', 'LineWidth', 1.5); hold on;
    plot(all_freqs, all_phase_V1I_s,   '--sk', 'LineWidth', 1.5);
    ylabel('Phase (deg)');
    set(ax1, 'XScale', 'log'); xlim([1 5000]);
    xlabel('Frequency (Hz)'); title('Bode Plot -- Z1 = V1/I');
    legend('Z1 Raw', 'Z1 Sm', 'Phase Raw', 'Phase Sm', 'Location', 'best');
    grid on;

    ax2 = subplot(2,1,2);
    yyaxis left
    plot(all_freqs, all_mag_Z2_raw, '-og', 'LineWidth', 1.5); hold on;
    plot(all_freqs, all_mag_Z2_s,   '--ok', 'LineWidth', 1.5);
    ylabel('Z2 Impedance (mOhm)');
    yyaxis right
    plot(all_freqs, all_phase_V2I_raw, '-sr', 'LineWidth', 1.5); hold on;
    plot(all_freqs, all_phase_V2I_s,   '--sk', 'LineWidth', 1.5);
    ylabel('Phase (deg)');
    set(ax2, 'XScale', 'log'); xlim([1 5000]);
    xlabel('Frequency (Hz)'); title('Bode Plot -- Z2 = V2/I');
    legend('Z2 Raw', 'Z2 Sm', 'Phase Raw', 'Phase Sm', 'Location', 'best');
    grid on;

    saveas(fh_bode, fullfile(folder, 'combined_bode_plot.jpg'));
    close(fh_bode);
    disp('Saved: combined_bode_plot.jpg');

    %% ============================================================
    %  NYQUIST PLOT  -- JPEG
    % ============================================================
    fh_nyq = figure('Name', 'Nyquist', 'NumberTitle', 'off', ...
                    'Visible', 'off', 'Position', [100 100 900 800]);

    subplot(2,1,1);
    plot(real(all_Z1_peak_raw)*1000, -imag(all_Z1_peak_raw)*1000, ...
         '-ob', 'MarkerSize', 8, 'LineWidth', 1.5); hold on;
    plot(real(all_Z1_peak_s)*1000,   -imag(all_Z1_peak_s)*1000, ...
         '--sk', 'MarkerSize', 8, 'LineWidth', 1.5);
    grid on;
    xlabel('Re(Z1) [mOhm]'); ylabel('-Im(Z1) [mOhm]');
    title('Nyquist Plot -- Z1 Peak Points');
    legend('Z1 Raw', 'Z1 Smoothed', 'Location', 'best');

    subplot(2,1,2);
    plot(real(all_Z2_peak_raw)*1000, -imag(all_Z2_peak_raw)*1000, ...
         '-ob', 'MarkerSize', 8, 'LineWidth', 1.5); hold on;
    plot(real(all_Z2_peak_s)*1000,   -imag(all_Z2_peak_s)*1000, ...
         '--sk', 'MarkerSize', 8, 'LineWidth', 1.5);
    grid on;
    xlabel('Re(Z2) [mOhm]'); ylabel('-Im(Z2) [mOhm]');
    title('Nyquist Plot -- Z2 Peak Points');
    legend('Z2 Raw', 'Z2 Smoothed', 'Location', 'best');

    saveas(fh_nyq, fullfile(folder, 'nyquist_plot.jpg'));
    close(fh_nyq);
    disp('Saved: nyquist_plot.jpg');
end

disp('Pipeline complete.');

%% ================================================================
%  LOCAL FUNCTIONS
% ================================================================

% ----------------------------------------------------------------
%  estimate_freq_amp
%  FFT peak frequency and amplitude on DC-removed signal.
% ----------------------------------------------------------------
function [freq, amp] = estimate_freq_amp(signal, t)
    N     = length(signal);
    dt    = mean(diff(t));
    Fs    = 1 / dt;
    halfN = floor(N/2);
    Y     = fft(signal - mean(signal));
    f     = Fs * (0:halfN) / N;
    Y_pos = Y(1:halfN+1);
    A     = abs(Y_pos) / N;
    A(2:end-1) = 2 * A(2:end-1);
    [amp, idx] = max(A(2:end));
    freq = f(idx + 1);
end

% ----------------------------------------------------------------
%  correct_drift
%  Polynomial trend fitted to the full AC+DC signal.
%  Only the non-constant (AC) part of the trend is subtracted,
%  so the DC operating point is preserved.
%  Correction is only applied when drift amplitude exceeds
%  thresh_ratio x AC amplitude -- avoids over-correcting clean data.
% ----------------------------------------------------------------
function [signal_out, detected] = correct_drift(signal_in, t, poly_order, thresh_ratio)
    % Force column vectors -- polyfit/polyval require consistent orientation
    signal_in = signal_in(:);
    t         = t(:);
    t_norm  = (t - t(1)) / (t(end) - t(1) + eps);
    p       = polyfit(t_norm, signal_in, poly_order);
    trend   = polyval(p, t_norm);

    % AC part of trend (remove its mean so DC level is untouched)
    trend_ac   = trend - mean(trend);
    residual   = signal_in - trend;
    ac_amp     = (max(residual) - min(residual)) / 2 + eps;
    drift_amp  = (max(trend_ac) - min(trend_ac)) / 2;

    if (drift_amp / ac_amp) > thresh_ratio
        detected   = true;
        signal_out = signal_in - trend_ac;
    else
        detected   = false;
        signal_out = signal_in;
    end
end

% ----------------------------------------------------------------
%  frame_sync_and_clean
%
%  FIX C details:
%  -- Mean of current is removed BEFORE zero-crossing search so
%     a DC-biased signal (not passing through zero) still yields
%     valid crossings.
%  -- An edge guard (FRAME_EDGE_GUARD_HALF_PERIODS half-periods)
%     discards crossings too close to the start/end of the record,
%     where the oscillator may not yet be settled.
%  -- Bad interior frames: samples dropped from I, V1, V2 together.
%  -- Bad edge frames: trimmed (not grounds for skipping the file).
%  -- If bad_frac > bad_max_frac: return empty, caller skips file.
% ----------------------------------------------------------------
function [I_out, V1_out, V2_out, t_out, report] = ...
         frame_sync_and_clean(I, V1, V2, t, freq_est, Fs, ...
                              amp_tol, period_tol, snr_db_min, ...
                              bad_max_frac, edge_guard_hp)

    report.n_total   = 0;
    report.n_dropped = 0;
    report.reason    = 'ok';

    % ---- Mean-remove current for zero-crossing (FIX C) ----
    % Use robust mean: median avoids skew from large transients.
    I_ac = I - median(I);

    % Edge guard: minimum sample distance from record boundary
    % Require at least edge_guard_hp half-periods of clearance.
    if freq_est > 0
        half_period_samps = round((0.5 / freq_est) * Fs);
        edge_guard_samps  = round(edge_guard_hp * half_period_samps);
    else
        edge_guard_samps = 0;
    end

    zc_idx = find_positive_zero_crossings(I_ac, edge_guard_samps, length(I));

    % Need at least 3 crossings (2 complete cycles) to do anything
    if length(zc_idx) < 3
        fprintf('[FRAMES] "%s": fewer than 2 cycles after edge guard -- no frame trimming.\n', '');
        I_out = I; V1_out = V1; V2_out = V2; t_out = t;
        report.reason = 'too few cycles after edge guard';
        return;
    end

    n_frames       = length(zc_idx) - 1;
    report.n_total = n_frames;

    % ---- Per-frame metrics ----
    frame_amp    = zeros(n_frames, 1);
    frame_period = zeros(n_frames, 1);
    frame_snr    = zeros(n_frames, 1);

    for fi = 1:n_frames
        idx_s = zc_idx(fi);
        idx_e = zc_idx(fi+1) - 1;
        seg   = I_ac(idx_s:idx_e);

        frame_amp(fi)    = (max(seg) - min(seg)) / 2;
        frame_period(fi) = t(idx_e) - t(idx_s);

        % Per-frame SNR: ratio of fundamental power to residual power
        N_seg  = length(seg);
        dt_seg = mean(diff(t(idx_s:idx_e)));
        Fs_seg = 1 / (dt_seg + eps);
        fvec   = Fs_seg * (0:floor(N_seg/2)) / N_seg;
        Yf     = fft(seg);
        Yf_pos = Yf(1:floor(N_seg/2)+1);
        [~, pk_i] = max(abs(Yf_pos(2:end)));
        pk_i   = pk_i + 1;

        A_c    =  2 * real(Yf(pk_i)) / N_seg;
        B_c    = -2 * imag(Yf(pk_i)) / N_seg;
        t_seg  = t(idx_s:idx_e) - t(idx_s);
        f_fund = fvec(pk_i);
        recon  = A_c * cos(2*pi*f_fund*t_seg) + B_c * sin(2*pi*f_fund*t_seg);
        noise  = seg - recon;

        frame_snr(fi) = 10 * log10((mean(recon.^2) + eps) / (mean(noise.^2) + eps));
    end

    % ---- Flag bad frames ----
    med_amp    = median(frame_amp);
    med_period = median(frame_period);

    bad = false(n_frames, 1);
    for fi = 1:n_frames
        amp_dev    = abs(frame_amp(fi)    - med_amp)    / (med_amp    + eps);
        period_dev = abs(frame_period(fi) - med_period) / (med_period + eps);
        if amp_dev > amp_tol || period_dev > period_tol || frame_snr(fi) < snr_db_min
            bad(fi) = true;
        end
    end

    % ---- Skip file if too many bad frames ----
    bad_frac = sum(bad) / n_frames;
    if bad_frac > bad_max_frac
        I_out = []; V1_out = []; V2_out = []; t_out = [];
        report.n_dropped = sum(bad);
        report.reason = sprintf('%.0f%% bad frames exceeds limit', bad_frac * 100);
        return;
    end

    % ---- Build keep mask (same for all channels -- sync preserved) ----
    keep = false(length(I), 1);
    for fi = 1:n_frames
        if ~bad(fi)
            idx_s = zc_idx(fi);
            idx_e = zc_idx(fi+1) - 1;
            keep(idx_s:idx_e) = true;
        end
    end

    I_out  = I(keep);
    V1_out = V1(keep);
    V2_out = V2(keep);
    t_out  = t(keep);

    report.n_dropped = sum(bad);
    if sum(bad) == 0
        report.reason = 'all frames good';
    else
        report.reason = sprintf('%d bad frame(s) dropped', sum(bad));
    end
end

% ----------------------------------------------------------------
%  find_positive_zero_crossings
%  Returns sample indices of upward (negative-to-positive) crossings.
%  edge_guard: crossings within this many samples of the record
%  start or end are rejected (unsettled signal edges -- FIX C).
% ----------------------------------------------------------------
function idx = find_positive_zero_crossings(x, edge_guard, N_total)
    diffs   = diff(sign(x));
    cross_i = find(diffs > 0);  % samples just BEFORE upward crossing

    % Sub-sample linear interpolation
    idx = zeros(size(cross_i));
    for n = 1:length(cross_i)
        i0     = cross_i(n);
        i1     = i0 + 1;
        frac   = -x(i0) / (x(i1) - x(i0) + eps);
        idx(n) = round(i0 + frac);
        idx(n) = max(1, min(N_total, idx(n)));
    end
    idx = unique(idx);

    % Apply edge guard
    idx = idx(idx > edge_guard & idx < (N_total - edge_guard));
end

% ----------------------------------------------------------------
%  apply_cfc_filter
%
%  FIX A: CFC class is chosen automatically from final_freq.
%  Rule: pick the lowest CFC class whose corner frequency (class x 5/3)
%  is at least 3x the signal fundamental frequency.
%  If freq > 550 Hz (above CFC-1000 range), fall back to Butterworth
%  at butter_mult x freq with a warning.
%  Manual override: set force_class to 60/180/600/1000.
% ----------------------------------------------------------------
function [I_f, V1_f, V2_f, label] = apply_cfc_filter(I, V1, V2, Fs, ...
                                     sig_freq, force_class, butter_mult)

    % CFC class table: [class, corner_Hz]
    cfc_table  = [60, 100; 180, 300; 600, 1000; 1000, 1650];
    min_corner = 3 * sig_freq;   % corner must be >= 3x fundamental

    if force_class > 0
        % Manual override
        row = cfc_table(cfc_table(:,1) == force_class, :);
        if isempty(row)
            error('apply_cfc_filter: invalid force_class %d', force_class);
        end
        fc    = row(2);
        label = sprintf('CFC-%d(forced)', force_class);
    else
        % Auto-select lowest class whose corner >= min_corner
        valid = cfc_table(cfc_table(:,2) >= min_corner, :);
        if isempty(valid)
            % Signal frequency too high for any CFC standard class
            fc_but = butter_mult * sig_freq;
            Wn_but = min(fc_but / (Fs/2), 0.99);
            [b, a] = butter(4, Wn_but, 'low');
            I_f    = filtfilt(b, a, I);
            V1_f   = filtfilt(b, a, V1);
            V2_f   = filtfilt(b, a, V2);
            label  = sprintf('Butter-%dx(%.0fHz)', butter_mult, sig_freq);
            fprintf('[FILTER] %.1f Hz signal: above CFC-1000 range, using %s\n', ...
                    sig_freq, label);
            return;
        end
        fc    = valid(1, 2);              % lowest valid corner
        cls   = valid(1, 1);
        label = sprintf('CFC-%d(auto)', cls);
    end

    % SAE J211 minimum Fs check
    if Fs < 8 * fc
        msg = sprintf('CFC filter: Fs=%.1f Hz below recommended 8x corner (%.1f Hz)', ...
                      Fs, 8*fc);
        warning(msg);
    end

    Wn     = min(fc / (Fs/2), 0.99);
    [b, a] = butter(4, Wn, 'low');
    I_f    = filtfilt(b, a, I);
    V1_f   = filtfilt(b, a, V1);
    V2_f   = filtfilt(b, a, V2);

    fprintf('[FILTER] %.1f Hz signal -> %s | corner %.0f Hz | Wn=%.4f\n', ...
            sig_freq, label, fc, Wn);
end

% ----------------------------------------------------------------
%  phase_shift_fft
%  FFT impedance magnitude and phase at dominant frequency.
% ----------------------------------------------------------------
function [f_main, v1_main, v2_main, ...
          i_amp_yes_dc_raw,  i_amp_yes_dc_s,  i_amp_no_dc_raw,  i_amp_no_dc_s, ...
          v1_amp_yes_dc_raw, v1_amp_yes_dc_s, v1_amp_no_dc_raw, v1_amp_no_dc_s, ...
          v2_amp_yes_dc_raw, v2_amp_yes_dc_s, v2_amp_no_dc_raw, v2_amp_no_dc_s, ...
          Z1_mag_raw, Z2_mag_raw, Z1_phase_main_raw, Z2_phase_main_raw, ...
          Z1_peak_raw, Z2_peak_raw, ...
          Z1_mag_s,   Z2_mag_s,   Z1_phase_main_s,   Z2_phase_main_s, ...
          Z1_peak_s,  Z2_peak_s] ...
          = phase_shift_fft(V1, V2, I, V1_s, V2_s, I_s, t)

    N     = length(t);
    dt    = mean(diff(t));
    Fs    = 1 / dt;
    halfN = floor(N/2);

    I_fft    = fft(I);     V1_fft   = fft(V1);    V2_fft   = fft(V2);
    I_s_fft  = fft(I_s);   V1_s_fft = fft(V1_s);  V2_s_fft = fft(V2_s);

    f = Fs * (0:halfN) / N;

    I_pos    = I_fft(1:halfN+1);     V1_pos   = V1_fft(1:halfN+1);
    V2_pos   = V2_fft(1:halfN+1);
    I_s_pos  = I_s_fft(1:halfN+1);  V1_s_pos = V1_s_fft(1:halfN+1);
    V2_s_pos = V2_s_fft(1:halfN+1);

    I_amp    = onesided_amp(I_pos,    N);
    V1_amp   = onesided_amp(V1_pos,   N);
    V2_amp   = onesided_amp(V2_pos,   N);
    I_amp_s  = onesided_amp(I_s_pos,  N);
    V1_amp_s = onesided_amp(V1_s_pos, N);
    V2_amp_s = onesided_amp(V2_s_pos, N);

    i_amp_yes_dc_raw  = max(I_amp);
    i_amp_yes_dc_s    = max(I_amp_s);
    i_amp_no_dc_raw   = max(I_amp(2:end));
    i_amp_no_dc_s     = max(I_amp_s(2:end));
    v1_amp_yes_dc_raw = max(V1_amp);
    v1_amp_yes_dc_s   = max(V1_amp_s);
    v1_amp_no_dc_raw  = max(V1_amp(2:end));
    v1_amp_no_dc_s    = max(V1_amp_s(2:end));
    v2_amp_yes_dc_raw = max(V2_amp);
    v2_amp_yes_dc_s   = max(V2_amp_s);
    v2_amp_no_dc_raw  = max(V2_amp(2:end));
    v2_amp_no_dc_s    = max(V2_amp_s(2:end));

    [~, ii]   = max(I_amp(2:end));   idx    = ii + 1;
    [~, iv1]  = max(V1_amp(2:end));  idx_v1 = iv1 + 1;
    [~, iv2]  = max(V2_amp(2:end));  idx_v2 = iv2 + 1;
    f_main    = f(idx);
    v1_main   = f(idx_v1);
    v2_main   = f(idx_v2);

    Z1_raw    = V1_pos  ./ I_pos;
    Z2_raw    = V2_pos  ./ I_pos;
    Z1_smooth = V1_s_pos ./ I_s_pos;
    Z2_smooth = V2_s_pos ./ I_s_pos;

    Z1_mag_raw = abs(Z1_raw(idx))    * 1000;
    Z2_mag_raw = abs(Z2_raw(idx))    * 1000;
    Z1_mag_s   = abs(Z1_smooth(idx)) * 1000;
    Z2_mag_s   = abs(Z2_smooth(idx)) * 1000;

    Z1_ph_raw = rad2deg(angle(Z1_raw));
    Z2_ph_raw = rad2deg(angle(Z2_raw));
    Z1_ph_s   = rad2deg(angle(Z1_smooth));
    Z2_ph_s   = rad2deg(angle(Z2_smooth));

    Z1_phase_main_raw = Z1_ph_raw(idx);
    Z2_phase_main_raw = Z2_ph_raw(idx);
    Z1_phase_main_s   = Z1_ph_s(idx);
    Z2_phase_main_s   = Z2_ph_s(idx);

    Z1_peak_raw = Z1_raw(idx);
    Z2_peak_raw = Z2_raw(idx);
    Z1_peak_s   = Z1_smooth(idx);
    Z2_peak_s   = Z2_smooth(idx);

    fprintf('\n--- RAW  Z1=%.3f mOhm | phi=%.2f deg   Z2=%.3f mOhm | phi=%.2f deg\n', ...
            Z1_mag_raw, Z1_phase_main_raw, Z2_mag_raw, Z2_phase_main_raw);
    fprintf('--- SMTH Z1=%.3f mOhm | phi=%.2f deg   Z2=%.3f mOhm | phi=%.2f deg\n', ...
            Z1_mag_s, Z1_phase_main_s, Z2_mag_s, Z2_phase_main_s);
end

% ----------------------------------------------------------------
%  onesided_amp  -- one-sided normalised amplitude from FFT output
% ----------------------------------------------------------------
function A = onesided_amp(Y_pos, N)
    A = abs(Y_pos) / N;
    A(2:end-1) = 2 * A(2:end-1);
end