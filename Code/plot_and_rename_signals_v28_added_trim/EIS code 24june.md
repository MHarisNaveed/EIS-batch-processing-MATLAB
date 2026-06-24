% ===========================================================================
%% Selecting Source Folder
% ===========================================================================

% Select folder
folder = uigetdir('', 'Select Folder Containing Waveform CSV Files');
if folder == 0
    disp('Folder selection cancelled.');
    return;
end

% Create output folder
out_folder = fullfile(folder, 'solution');
if ~exist(out_folder, 'dir')
    mkdir(out_folder);
end

% Get all CSV files in folder
files = dir(fullfile(folder, '*.csv'));



% =========================================================================
%% ______________initilization Varaibles____________________________________
% =========================================================================



all_freqs         = [];  % dominant frequency per file

% Z1
all_mag_Z1_raw    = [];  % raw magnitude (mΩ)
all_mag_Z1_s      = [];  % smoothed magnitude (mΩ)
all_phase_V1I_raw = [];  % raw phase (°)
all_phase_V1I_s   = [];  % smoothed phase (°)
all_Z1_peak_raw   = [];  % raw complex Z1 at peak
all_Z1_peak_s     = [];  % smoothed complex Z1 at peak

% Z2
all_mag_Z2_raw    = [];  % raw magnitude (mΩ)
all_mag_Z2_s      = [];  % smoothed magnitude (mΩ)
all_phase_V2I_raw = [];  % raw phase (°)
all_phase_V2I_s   = [];  % smoothed phase (°)
all_Z2_peak_raw   = [];  % raw complex Z2 at peak
all_Z2_peak_s     = [];  % smoothed complex Z2 at peak

T_summary_data = {};





% ======================================================================
%% ---------------------Loading Data----------------------------------
% ======================================================================


for k = 1:length(files)
    filename = files(k).name;
    fullpath = fullfile(folder, filename);

    try
        % Read using readtable to handle mixed-type content
        opts = detectImportOptions(fullpath, 'NumHeaderLines', 15);
        T = readtable(fullpath, opts);
        
        % Remove all rows where the first 4 columns are NaN
        T = T(~all(ismissing(T(:, 1:4)), 2), :);
        
        % Extract and convert signals
        t_raw = T{:,1};  % Extract time column (could be duration, datetime, or numeric)
        if isduration(t_raw) || isdatetime(t_raw)
            t = seconds(t_raw);   % Convert to numeric seconds
        else
            t = double(t_raw);    % Already numeric
        end

        % --- Extract datetime from CSV header ---
        % Read first 15 lines with readtable (2 columns: Name + Value)
        optsHeader = detectImportOptions(fullpath);
        optsHeader.DataLines = [14 15];          % rows with date/time
        optsHeader.VariableNamesLine = 0;        % ignore any header names
        optsHeader.Delimiter = ',';              % adjust if CSV uses tab
        
        % Force second column (Value column) to be string
        optsHeader = setvartype(optsHeader, 2, 'string');
        
        Tinfo = readtable(fullpath, optsHeader);
        
        % Now extract safely
        rawDate = strtrim(Tinfo{1,2});      % "2025/07/30"
        rawTime = strtrim(Tinfo{2,2});      % "13:52:25.87803125"
        
        % Combine
        dt_csvscope = datetime(rawDate + " " + rawTime, ...
                               'InputFormat','yyyy/MM/dd HH:mm:ss.SSSSSSSSS');  
        
        % Format for filenames (ignore fractional seconds)
        dt_str = datestr(dt_csvscope,'yyyymmdd_HHMMSS');
        
        % fprintf('Formatted datetime string: %s\n', dt_str);

        if isempty(dt_str)
            % fallback to file save date
            fileinfo = dir(fullpath);
            dt_str = datestr(fileinfo.datenum, 'yyyymmdd_HHMMSS');
        end






% =====================================================================
%% -----------------Loading data into Variables------------------------
% =====================================================================


        % Extract other signals and convert to double
        v_shunt   = double(T{:,2});
        current   = (v_shunt/-0.0075);
        voltage1  = double(T{:,5});
        voltage2  = double(T{:,7});
        
        % % Trim first and last 10% — keep middle 80% only
        % n_total  = length(t);
        % i_start  = floor(0.5 * n_total) + 1;
        % i_end    = floor(0.95 * n_total);
        % 
        % t        = t(i_start:i_end);
        % current  = current(i_start:i_end);
        % voltage1 = voltage1(i_start:i_end);
        % voltage2 = voltage2(i_start:i_end);



        % Sanity check: must be numeric, non-empty, no NaNs
        if any(isnan(t)) || any(isnan(current)) || any(isnan(voltage1)) || any(isnan(voltage2)) ...
                || isempty(t) || length(t) < 10
            warning('"%s": Signal or time data is invalid or too short. Skipping.', filename);
            continue;
        end





% ======================================================
%% -------------FFT for Naming files and signal----------
% =======================================================


        % Estimate frequency from all 3 signals
        [freq_c, amp_c]   = estimate_freq_amp(current, t);
        [freq_v1, amp_v1] = estimate_freq_amp(voltage1, t);
        [freq_v2, amp_v2] = estimate_freq_amp(voltage2, t);

        % Use median to reduce outlier effect
        final_freq = median([freq_c, freq_v1, freq_v2]);
        final_amp = median([amp_c, amp_v1, amp_v2]); %usless btw

        % --- New file name with datetime + frequency ---
        newname = sprintf('Renamed_%s_%dHz.csv', dt_str, abs(round(final_freq)));
        newpath = fullfile(out_folder, newname);
        
        % Avoid overwrite
        if exist(newpath, 'file')
            [~, base, ~] = fileparts(newname);
            newname = sprintf('%s_%s_%dHz.csv', base, dt_str, abs(round(final_freq)));
            newpath = fullfile(out_folder, newname);
        end
        
        % Duplicate instead of renaming
        copyfile(fullpath, newpath); 
        % movefile(fullpath, newpath);
        fprintf('\nRenamed "%s" -> "%s" | Freq: %.2f Hz\n', filename, newname, final_freq);
        




% ============================================================================================
%% ---------------------Smoothing / Noise cancellation---------------------------------------
% ============================================================================================
        Fs = 1 / mean(diff(t));

        % 4PSF: fit and reconstruct — zero edge effects, exact phase
        [current_s, voltage1_s, voltage2_s] = ...
            fit_reconstruct_4psf(current, voltage1, voltage2, t, freq_c);

        % Extract complete cycles using current as master clock
        [current_s, voltage1_s, voltage2_s, cycle_idx] = ...
            extract_complete_cycles(current_s, voltage1_s, voltage2_s);
        t_s = t(cycle_idx);






% ============================================================================================
%% ---------------------Ploting Raw vs Processed Signal ---------------------------------------
% ============================================================================================
        figure('Name', [newname], 'NumberTitle', 'off');

        % ------------------ CURRENT ------------------
        subplot(3,1,1);
        plot(t, current, 'Color', [0.30 0.75 0.93], 'LineWidth', 2.4);
        hold on;
        plot(t_s, current_s, 'k', 'LineWidth', 1);
        title('Current vs Time');
        xlabel('Time (s)');
        ylabel('Current');
        legend('Raw','Smoothed');
        grid on;
        
        % ------------------ VOLTAGE 1 ------------------
        subplot(3,1,2);
        plot(t, voltage1, 'r', 'LineWidth', 1);
        hold on;
        plot(t_s, voltage1_s, 'k', 'LineWidth', 1);
        title('Voltage 1 vs Time');
        xlabel('Time (s)');
        ylabel('Voltage 1');
        legend('Raw','Smoothed');
        grid on;
        
        % ------------------ VOLTAGE 2 ------------------
        subplot(3,1,3);
        plot(t, voltage2, 'g', 'LineWidth', 1);
        hold on;
        plot(t_s, voltage2_s, 'k', 'LineWidth', 1);
        title('Voltage 2 vs Time');
        xlabel('Time (s)');
        ylabel('Voltage 2');
        legend('Raw','Smoothed');
        grid on;
        
        % Save plot as PNG
        [~, base, ~] = fileparts(newname);
        saveas(gcf, fullfile(out_folder, [base, '_plot.jpg']));





% ============================================================================================
%% ---------------------Generating Impedence and Phase angles --------------------------------
% ============================================================================================

        
     % --- RAW ---
[f_main, v1_main, v2_main, ...
 i_amp_yes_dc_raw, i_amp_no_dc_raw, ...
 v1_amp_yes_dc_raw, v1_amp_no_dc_raw, ...
 v2_amp_yes_dc_raw, v2_amp_no_dc_raw, ...
 Z1_mag_raw, Z2_mag_raw, Z1_phase_raw, Z2_phase_raw, Z1_peak_raw, Z2_peak_raw] ...
 = phase_shift_fft(voltage1, voltage2, current, t);

% --- SMOOTHED ---
[~, ~, ~, ...
 i_amp_yes_dc_s, i_amp_no_dc_s, ...
 v1_amp_yes_dc_s, v1_amp_no_dc_s, ...
 v2_amp_yes_dc_s, v2_amp_no_dc_s, ...
 Z1_mag_s, Z2_mag_s, Z1_phase_s, Z2_phase_s, Z1_peak_s, Z2_peak_s] ...
 = phase_shift_fft(voltage1_s, voltage2_s, current_s, t_s);

main_freq = f_main;

        % --- Round to 6 decimals
        fmt6 = @(x) round(x,6);
        
        % --- Create table row
        row = {
            fmt6(main_freq), ...
            fmt6(v1_main), ...
            fmt6(v2_main), ...
            fmt6(i_amp_yes_dc_raw), ...
            fmt6(i_amp_yes_dc_s), ...
            fmt6(i_amp_no_dc_raw), ...
            fmt6(i_amp_no_dc_s), ...
            fmt6(v1_amp_yes_dc_raw), ...
            fmt6(v1_amp_yes_dc_s), ...
            fmt6(v1_amp_no_dc_raw), ...
            fmt6(v1_amp_no_dc_s), ...
            fmt6(v2_amp_yes_dc_raw), ...
            fmt6(v2_amp_yes_dc_s), ...
            fmt6(v2_amp_no_dc_raw), ...
            fmt6(v2_amp_no_dc_s), ... 
            fmt6(Z1_mag_raw), ...
            fmt6(Z1_mag_s), ...
            fmt6(Z2_mag_raw), ...
            fmt6(Z2_mag_s), ...
            fmt6(Z1_phase_raw), ...
            fmt6(Z1_phase_s), ...
            fmt6(Z2_phase_raw), ...
            fmt6(Z2_phase_s)
        };
        
        % --- Append to main variables
        T_summary_data = [T_summary_data; row];






% ============================================================================================
%% ---------------------Appending data for Whole Frequency Domain------------------------------
% ============================================================================================

        % Store the dominant frequency and corresponding phases
        all_freqs(end+1)           = main_freq;

        all_mag_Z1_raw(end+1)      = Z1_mag_raw;
        all_mag_Z1_s(end+1)        = Z1_mag_s;
        all_phase_V1I_raw(end+1)   = Z1_phase_raw;
        all_phase_V1I_s(end+1)     = Z1_phase_s;
        all_Z1_peak_raw(end+1)     = Z1_peak_raw;
        all_Z1_peak_s(end+1)       = Z1_peak_s;
        
        all_mag_Z2_raw(end+1)      = Z2_mag_raw;
        all_mag_Z2_s(end+1)        = Z2_mag_s;
        all_phase_V2I_raw(end+1)   = Z2_phase_raw;
        all_phase_V2I_s(end+1)     = Z2_phase_s;
        all_Z2_peak_raw(end+1)     = Z2_peak_raw;
        all_Z2_peak_s(end+1)       = Z2_peak_s;
        
    catch ME
        warning('Error processing "%s": %s', filename, ME.message);
    end
end


disp('All files processed.');

% -------------------------
%% Create tables & save CSV
% -------------------------
colNames = {
    'I Fr (Hz)', ...
    'V1 Fr (Hz)', ...
    'V2 Fr (Hz)', ...
    'I Amp DC raw', ...
    'I Amp DC Sm', ...
    'I Amp NO DC raw', ...
    'I Amp NO DC Sm', ...
    'V1 Amp DC raw', ...
    'V1 Amp DC Sm', ...
    'V1 Amp NO DC raw', ...
    'V1 Amp NO DC Sm', ...
    'V2 Amp DC raw', ...
    'V2 Amp DC Sm', ...
    'V2 Amp NO DC raw', ...
    'V2 Amp NO DC Sm', ...
    'Raw Imp Z1 (mΩ)', ... 
    'Smoothed Imp Z1 (mΩ)', ...
    'Raw Imp Z2 (mΩ)', ... 
    'Smoothed Imp Z2 (mΩ)', ...
    'Raw Phase Z1 (∠)', ... 
    'Smoothed Phase Z1 (∠)', ...
    'Raw Phase Z2 (∠)', ... 
    'Smoothed Phase Z2 (∠)'
};

if ~isempty(T_summary_data) && size(T_summary_data, 2) == length(colNames)
    T_summary = cell2table(T_summary_data, 'VariableNames', colNames);
    
else
    warning('Summary table skipped: column count mismatch or no data (%d rows, %d cols, %d expected).', ...
        size(T_summary_data,1), size(T_summary_data,2), length(colNames));
end

% Format all numeric values to 6 decimal places (for display only)
data6 = arrayfun(@(x) sprintf('%.6f', x), T_summary{:,:}, 'UniformOutput', false);

% --- Plotting Data Table ---
figure('Name','Signal Data Summary Table','NumberTitle','off','Position',[100 100 1200 400]);

uitable('Data', data6, ...
        'ColumnName', T_summary.Properties.VariableNames, ...
        'Units','Normalized', ...
        'Position',[0 0 1 1], ...
        'FontSize',10);

% Save to CSV
writetable(T_summary, fullfile(out_folder, 'summary_table.csv'));
disp('Summary table saved as "summary_table.csv"');












% ============================================================================================
%% ---------------------  Functions Definitions ---------------------------------------
% ============================================================================================





% ---------------------------------------------
%% Frequency & Amplitude function: FFT estimate
% ---------------------------------------------
function [freq, amp] = estimate_freq_amp(signal, t)

    N  = length(signal);        % number of samples
    dt = mean(diff(t));         % sampling period (s)
    Fs = 1 / dt;                % sampling frequency (Hz)
    halfN = floor(N/2);         % half length
    
    % FFT (from time domain to frequency domain conversion, gives comples number: coefficient & angle)
    signal_noDC = signal - mean(signal);
    Y = fft(signal_noDC);
    
    % Symmetric frequency range when using fft but half part (i.e. to match [0, +Δf, ..., +Fs/2−Δf])
    f = Fs*(0:halfN)/N;
    
    % Extract positive-frequency part
    Y_pos = Y(1:halfN+1);
    
    % One-sided amplitude normalization
    amplitude_one_sided = abs(Y_pos)/N;
    amplitude_one_sided(2:end-1) = 2*amplitude_one_sided(2:end-1);

    % Find peak amplitude and corresponding frequency
    [max_amp, idx] = max(amplitude_one_sided);
    peak_freq = f(idx);
    freq = peak_freq;
    amp = max_amp;
    
    fprintf('\nPeak Amplitude (Without DC component): %.6f\n', amp);
    fprintf('Peak Frequency (Without DC component): %.6f Hz\n', freq);

    % --- Plot one-sided amplitude spectrum ---
    % figure;
    % plot(f, amplitude_one_sided, 'LineWidth', 1.5);
    % title('One-Sided Amplitude Spectrum (FFT)');
    % xlabel('Frequency (Hz)');
    % ylabel('Amplitude');
    % grid on;
end


% ============================================================================================
%% ── 4PSF Fit + Reconstruct (replaces lockin_reconstruct) ────────────────────────────────────
% ============================================================================================
function [i_out, v1_out, v2_out] = fit_reconstruct_4psf(current, voltage1, voltage2, t, f0_init)
    % Four-Parameter Sine Fit — IEEE 1241 method
    % Model: x(t) = A*cos(2πf₀t) + B*sin(2πf₀t) + C + D*t
    %
    % Zero edge effects — no filter, no convolution, no padding.
    % Phase preserved exactly — voltage uses same f0 as current, no independent fit.
    % Transient rejection — pass 1 finds bad samples, pass 2 refits on clean ones.
    %
    % C = DC offset  (voltage DC bias handled automatically)
    % D = linear drift (handles any slow ramp in background)

    t = t(:);

    % ── Refine frequency from current (Gauss-Newton, IEEE 1241 Annex B) ──
    f0 = refine_freq_gauss_newton(current, t, f0_init);
    fprintf('4PSF | f0_fft=%.4f Hz → f0_refined=%.6f Hz\n', f0_init, f0);

    % ── Pass 1: full fit on current to locate transient samples ──────────
    resid1      = fit_4psf_residual(current, t, f0);
    global_mad  = median(abs(resid1 - median(resid1)));

    % Relaxed threshold — only flag severe outliers
    bad = abs(resid1) > 6.0 * global_mad;

    % Minimum clean samples needed: 3 full cycles or 30% of signal
    min_clean = max(round(3 * (1/mean(diff(t))) / f0), round(0.3*length(t)));

    if sum(~bad) < min_clean
        % Fallback: find longest contiguous clean region dynamically
        % Try progressively relaxed thresholds: 8x, 12x, 20x MAD
        for thresh = [8.0, 12.0, 20.0]
            bad_try = abs(resid1) > thresh * global_mad;
            if sum(~bad_try) >= min_clean
                bad = bad_try;
                fprintf('4PSF | relaxed threshold %.0fx MAD used\n', thresh);
                break;
            end
        end

        % Still not enough — find longest contiguous good block
        if sum(~bad) < min_clean
            good_runs    = ~bad;
            run_starts   = find(diff([0; good_runs]) == 1);
            run_ends     = find(diff([good_runs; 0]) == -1);
            if ~isempty(run_starts)
                [~, best_run] = max(run_ends - run_starts);
                bad(:)        = true;
                bad(run_starts(best_run):run_ends(best_run)) = false;
                fprintf('4PSF | longest clean block: samples %d-%d\n', ...
                        run_starts(best_run), run_ends(best_run));
            else
                % Last resort: middle 70%
                n = length(t);
                bad(:) = false;
                bad(1:floor(0.15*n))       = true;
                bad(floor(0.85*n)+1:end)   = true;
                fprintf('4PSF | last resort: middle 70%%\n');
            end
        end
    else
        fprintf('4PSF | pass1: %d/%d samples clean (%.1f%%)\n', ...
                sum(~bad), length(t), 100*mean(~bad));
    end

    good = ~bad;

    % ── Pass 2: refit all signals on clean samples, same mask ────────────
    % Current drives f0 — voltage uses identical f0, phase never touched
    [A_I,  B_I,  C_I,  D_I ] = solve_4psf(current(good),  t(good), f0);
    [A_V1, B_V1, C_V1, D_V1] = solve_4psf(voltage1(good), t(good), f0);
    [A_V2, B_V2, C_V2, D_V2] = solve_4psf(voltage2(good), t(good), f0);

    % ── Reconstruct on full original time axis ────────────────────────────
    % Analytically evaluated — no filter, no edge artifact
    i_out  = eval_4psf(t, A_I,  B_I,  C_I,  D_I,  f0);
    v1_out = eval_4psf(t, A_V1, B_V1, C_V1, D_V1, f0);
    v2_out = eval_4psf(t, A_V2, B_V2, C_V2, D_V2, f0);

    fprintf('4PSF | I:  amp=%.5f  phase=%.4f deg\n', ...
            sqrt(A_I^2+B_I^2), atan2d(B_I, A_I));
    fprintf('4PSF | V1: amp=%.6f  phase=%.4f deg\n', ...
            sqrt(A_V1^2+B_V1^2), atan2d(B_V1, A_V1));
    fprintf('4PSF | ΔΦ(V1-I) = %.6f deg\n', ...
            atan2d(B_V1,A_V1) - atan2d(B_I,A_I));
end

% ── Gauss-Newton frequency refinement ────────────────────────────────────────
function f1 = refine_freq_gauss_newton(x, t, f0_init)
    t  = t(:) - t(1);   % ← shift to start from zero
    x  = x(:);
    f1 = f0_init;
    f_best = f0_init;
    cost_best = inf;

    for iter = 1:20
        w  = 2*pi*f1;
        c  =  cos(w.*t);
        s  =  sin(w.*t);
        D  = [c, s, ones(size(t)), t];
        cf = D \ x;
        A  = cf(1);  B = cf(2);
        r  = x - D*cf;
        cost = sum(r.^2);
        if cost < cost_best
            cost_best = cost;  f_best = f1;
        end
        dc   = -sin(w.*t).*(2*pi*t);
        ds   =  cos(w.*t).*(2*pi*t);
        Jf   = A.*dc + B.*ds;
        grad = Jf' * r;
        H    = Jf'*Jf + 1e-10;
        df   = grad / H;
        df   = sign(df) * min(abs(df), 0.1*f0_init);
        f1   = max(min(f1+df, f0_init*2), f0_init*0.5);
        if abs(df) < 1e-7, break; end
    end
    f1 = f_best;
end

% ── Single 4PSF solve ─────────────────────────────────────────────────────────
function [A, B, C, D] = solve_4psf(x, t, f0)
    t  = t(:) - t(1);   % ← shift to start from zero
    x  = x(:);
    w  = 2*pi*f0;
    M  = [cos(w.*t), sin(w.*t), ones(size(t)), t];
    cf = M \ x;
    A  = cf(1);  B = cf(2);  C = cf(3);  D = cf(4);
end

% ── Residual from full-data 4PSF ─────────────────────────────────────────────
function r = fit_4psf_residual(x, t, f0)
    [A, B, C, D] = solve_4psf(x, t, f0);
    r = x(:) - eval_4psf(t, A, B, C, D, f0);
end

% ── Evaluate 4PSF model ───────────────────────────────────────────────────────
function y = eval_4psf(t, A, B, C, D, f0)
    t  = t(:) - t(1);   % ← shift to start from zero
    w  = 2*pi*f0;
    y  = A.*cos(w.*t) + B.*sin(w.*t) + C + D.*t;
end

% ---------------------------
%% Phase function: Bode Point
% ---------------------------
function [f_main, v1_main, v2_main, ...
          i_amp_yes_dc, i_amp_no_dc, ...
          v1_amp_yes_dc, v1_amp_no_dc, ...
          v2_amp_yes_dc, v2_amp_no_dc, ...
          Z1_mag, Z2_mag, Z1_phase_main, Z2_phase_main, Z1_peak, Z2_peak] ...
          = phase_shift_fft(V1, V2, I, t)

    % -----------------------------------------------------
    % Compute FFT-based impedance magnitude and phase
    % (call once for raw, once for smoothed)
    % -----------------------------------------------------

    N     = length(t);
    dt    = mean(diff(t));
    Fs    = 1/dt;
    halfN = floor(N/2);

    % --- FFT ---
    I_fft  = fft(I);
    V1_fft = fft(V1);
    V2_fft = fft(V2);

    f = Fs*(0:halfN)/N;

    % --- One-sided spectrum ---
    I_pos  = I_fft(1:halfN+1);
    V1_pos = V1_fft(1:halfN+1);
    V2_pos = V2_fft(1:halfN+1);

    % --- Amplitude: normalize ---
    I_amp  = abs(I_pos)/N;
    V1_amp = abs(V1_pos)/N;
    V2_amp = abs(V2_pos)/N;

    % --- Amplitude: one-sided correction (double all bins except DC and Nyquist) ---
    I_amp(2:end-1)  = 2*I_amp(2:end-1);
    V1_amp(2:end-1) = 2*V1_amp(2:end-1);
    V2_amp(2:end-1) = 2*V2_amp(2:end-1);

    % --- Amplitude summary ---
    i_amp_yes_dc  = max(I_amp);
    i_amp_no_dc   = max(I_amp(2:end));

    v1_amp_yes_dc = max(V1_amp);
    v1_amp_no_dc  = max(V1_amp(2:end));

    v2_amp_yes_dc = max(V2_amp);
    v2_amp_no_dc  = max(V2_amp(2:end));

    fprintf('\n --- I:  Amplitude (WITH DC):    %.6f\n', i_amp_yes_dc);
    fprintf('\n --- I:  Amplitude (WITHOUT DC): %.6f\n', i_amp_no_dc);
    fprintf('\n --- V1: Amplitude (WITH DC):    %.6f\n', v1_amp_yes_dc);
    fprintf('\n --- V1: Amplitude (WITHOUT DC): %.6f\n', v1_amp_no_dc);
    fprintf('\n --- V2: Amplitude (WITH DC):    %.6f\n', v2_amp_yes_dc);
    fprintf('\n --- V2: Amplitude (WITHOUT DC): %.6f\n', v2_amp_no_dc);

    % --- Dominant frequency from current (ignore DC bin) ---
    [~, idx] = max(I_amp(2:end));
    idx      = idx + 1;
    f_main   = f(idx);
    fprintf('\n --- Peak frequency from I  (Hz): %.6f\n', f_main);

    % --- Dominant frequency from V1 ---
    [~, idx_v1] = max(V1_amp(2:end));
    idx_v1      = idx_v1 + 1;
    v1_main     = f(idx_v1);
    fprintf('\n --- Peak frequency from V1 (Hz): %.6f\n', v1_main);

    % --- Dominant frequency from V2 ---
    [~, idx_v2] = max(V2_amp(2:end));
    idx_v2      = idx_v2 + 1;
    v2_main     = f(idx_v2);
    fprintf('\n --- Peak frequency from V2 (Hz): %.6f\n', v2_main);

    % --- Complex impedance spectrum ---
    Z1 = V1_pos ./ I_pos;
    Z2 = V2_pos ./ I_pos;

    % --- Magnitude at dominant frequency (mΩ) ---
    Z1_mag = abs(Z1(idx)) * 1000;
    Z2_mag = abs(Z2(idx)) * 1000;

    % --- Phase spectrum (deg) ---
    Z1_phase = rad2deg(angle(Z1));
    Z2_phase = rad2deg(angle(Z2));

    % --- Phase at dominant frequency ---
    Z1_phase_main = Z1_phase(idx);
    Z2_phase_main = Z2_phase(idx);

    % --- Complex peak value at dominant frequency ---
    Z1_peak = Z1(idx);
    Z2_peak = Z2(idx);

    fprintf('\n--- Impedance ---\n');
    fprintf('Z1 = %.3f mΩ | Phase = %.2f deg\n', Z1_mag, Z1_phase_main);
    fprintf('Z2 = %.3f mΩ | Phase = %.2f deg\n', Z2_mag, Z2_phase_main);

end

%=============================================
%% ---- Lock IN Reconstruct Alog ----
%=============================================

function y = lockin_reconstruct(x, t, f0, Fs, ref_signal)
    % Lock-in amplifier using current as reference
    % Removes DC offset before demodulation, restores after
    
    N      = length(t);
    df     = Fs / N;
    idx    = round(f0 / df) + 1;
    
    % Extract phase of current at fundamental
    R_fft     = fft(ref_signal);
    ref_phase = angle(R_fft(idx));
    
    % Reference quadrature pair locked to current phase
    ref_cos = cos(2*pi*f0*t + ref_phase);
    ref_sin = sin(2*pi*f0*t + ref_phase);
    
    % Remove DC before demodulation
    dc_offset = mean(x);
    x_ac      = x - dc_offset;
    
    % Demodulate AC part only
    I_comp = x_ac .* ref_cos;
    Q_comp = x_ac .* ref_sin;
    
    % Lowpass — one cycle moving average
    win    = max(3, round(Fs / f0));
    b_lp   = ones(win, 1) / win;
    
    I_filt = filtfilt(b_lp, 1, I_comp);
    Q_filt = filtfilt(b_lp, 1, Q_comp);
    
    % Reconstruct AC fundamental, then restore DC
    y = 2 * (I_filt .* ref_cos + Q_filt .* ref_sin) + dc_offset;
end
% ---- END ADD ----


%===============================================
%% -----framing and frame dropping
%====================================================
function [i_out, v1_out, v2_out, idx_range] = extract_complete_cycles(current_s, voltage1_s, voltage2_s)
    n           = length(current_s);
    i_start     = floor(0.20 * n) + 1;
    i_end       = floor(0.80 * n);
    robust_mean = mean(current_s(i_start:i_end));
    i_centered  = current_s - robust_mean;
    crossings   = find(i_centered(1:end-1) < 0 & i_centered(2:end) >= 0);

    % Default fallback
    idx_range = (1:n)';

    if length(crossings) < 3
        warning('Not enough zero crossings — returning original signals.');
        i_out  = current_s;
        v1_out = voltage1_s;
        v2_out = voltage2_s;
        return;
    end

    % Estimate one cycle length from crossings
    cycle_len = mean(diff(crossings));

    % How many samples exist before first crossing
    samples_before = crossings(1) - 1;

    % Threshold: if first partial frame is smaller than 20% of a cycle
    % it is a tiny fragment — drop it by moving to next crossing
    tiny_threshold = 0.20 * cycle_len;

    if samples_before < tiny_threshold
        % Tiny fragment at start — drop it, use next crossing
        c_start = crossings(2);
        fprintf('Tiny start fragment (%d samples < %.1f threshold) — dropped first partial frame\n', ...
            samples_before, tiny_threshold);
    else
        % Big enough partial frame — crossings(1) is already a good start
        c_start = crossings(1);
        fprintf('Large start fragment (%d samples >= %.1f threshold) — kept from first crossing\n', ...
            samples_before, tiny_threshold);
    end

    % Same logic for end
    samples_after = n - crossings(end);

    if samples_after < tiny_threshold
        c_end = crossings(end-1);
        fprintf('Tiny end fragment (%d samples < %.1f threshold) — dropped last partial frame\n', ...
            samples_after, tiny_threshold);
    else
        c_end = crossings(end);
        fprintf('Large end fragment (%d samples >= %.1f threshold) — kept to last crossing\n', ...
            samples_after, tiny_threshold);
    end

    if c_start >= c_end
        warning('Cycle extraction empty range — returning original signals.');
        i_out  = current_s;
        v1_out = voltage1_s;
        v2_out = voltage2_s;
        return;
    end

    fprintf('Cycle extraction: kept samples %d to %d of %d\n', c_start, c_end, n);

    idx_range = (c_start:c_end)';
    i_out     = current_s(idx_range);
    v1_out    = voltage1_s(idx_range);
    v2_out    = voltage2_s(idx_range);
end


% ============================================================================================
%% ── Average data points within ±5% frequency tolerance ─────────────────────────────────────
% ============================================================================================

tol = 0.05;  % 5% tolerance

% Work on a copy so originals are untouched during grouping
freqs_tmp       = all_freqs(:);
mag_Z1_raw_tmp  = all_mag_Z1_raw(:);
mag_Z1_s_tmp    = all_mag_Z1_s(:);
ph_Z1_raw_tmp   = all_phase_V1I_raw(:);
ph_Z1_s_tmp     = all_phase_V1I_s(:);
Zpk_Z1_raw_tmp  = all_Z1_peak_raw(:);
Zpk_Z1_s_tmp    = all_Z1_peak_s(:);

mag_Z2_raw_tmp  = all_mag_Z2_raw(:);
mag_Z2_s_tmp    = all_mag_Z2_s(:);
ph_Z2_raw_tmp   = all_phase_V2I_raw(:);
ph_Z2_s_tmp     = all_phase_V2I_s(:);
Zpk_Z2_raw_tmp  = all_Z2_peak_raw(:);
Zpk_Z2_s_tmp    = all_Z2_peak_s(:);

% Sort by frequency ascending before grouping
[freqs_tmp, sIdx] = sort(freqs_tmp);
mag_Z1_raw_tmp  = mag_Z1_raw_tmp(sIdx);   mag_Z1_s_tmp  = mag_Z1_s_tmp(sIdx);
ph_Z1_raw_tmp   = ph_Z1_raw_tmp(sIdx);    ph_Z1_s_tmp   = ph_Z1_s_tmp(sIdx);
Zpk_Z1_raw_tmp  = Zpk_Z1_raw_tmp(sIdx);   Zpk_Z1_s_tmp  = Zpk_Z1_s_tmp(sIdx);
mag_Z2_raw_tmp  = mag_Z2_raw_tmp(sIdx);   mag_Z2_s_tmp  = mag_Z2_s_tmp(sIdx);
ph_Z2_raw_tmp   = ph_Z2_raw_tmp(sIdx);    ph_Z2_s_tmp   = ph_Z2_s_tmp(sIdx);
Zpk_Z2_raw_tmp  = Zpk_Z2_raw_tmp(sIdx);   Zpk_Z2_s_tmp  = Zpk_Z2_s_tmp(sIdx);

% Group and average
used    = false(size(freqs_tmp));
avg_freqs        = [];
avg_mag_Z1_raw   = [];  avg_mag_Z1_s   = [];
avg_ph_Z1_raw    = [];  avg_ph_Z1_s    = [];
avg_Zpk_Z1_raw   = [];  avg_Zpk_Z1_s   = [];
avg_mag_Z2_raw   = [];  avg_mag_Z2_s   = [];
avg_ph_Z2_raw    = [];  avg_ph_Z2_s    = [];
avg_Zpk_Z2_raw   = [];  avg_Zpk_Z2_s   = [];

for i = 1:length(freqs_tmp)
    if used(i), continue; end

    f_ref   = freqs_tmp(i);
    % ±5% band around this frequency
    in_band = ~used & ...
              freqs_tmp >= f_ref * (1 - tol) & ...
              freqs_tmp <= f_ref * (1 + tol);

    % Averaged values
    avg_freqs(end+1)      = mean(freqs_tmp(in_band));
    avg_mag_Z1_raw(end+1) = mean(mag_Z1_raw_tmp(in_band));
    avg_mag_Z1_s(end+1)   = mean(mag_Z1_s_tmp(in_band));
    avg_ph_Z1_raw(end+1)  = mean(ph_Z1_raw_tmp(in_band));
    avg_ph_Z1_s(end+1)    = mean(ph_Z1_s_tmp(in_band));
    avg_Zpk_Z1_raw(end+1) = mean(Zpk_Z1_raw_tmp(in_band));
    avg_Zpk_Z1_s(end+1)   = mean(Zpk_Z1_s_tmp(in_band));

    avg_mag_Z2_raw(end+1) = mean(mag_Z2_raw_tmp(in_band));
    avg_mag_Z2_s(end+1)   = mean(mag_Z2_s_tmp(in_band));
    avg_ph_Z2_raw(end+1)  = mean(ph_Z2_raw_tmp(in_band));
    avg_ph_Z2_s(end+1)    = mean(ph_Z2_s_tmp(in_band));
    avg_Zpk_Z2_raw(end+1) = mean(Zpk_Z2_raw_tmp(in_band));
    avg_Zpk_Z2_s(end+1)   = mean(Zpk_Z2_s_tmp(in_band));

    n_grouped = sum(in_band);
    fprintf('Freq group ~%.2f Hz: averaged %d file(s)\n', avg_freqs(end), n_grouped);

    used(in_band) = true;
end

% ── Overwrite plotting variables with averaged versions ───────────────────────
all_freqs         = avg_freqs;
all_mag_Z1_raw    = avg_mag_Z1_raw;   all_mag_Z1_s    = avg_mag_Z1_s;
all_phase_V1I_raw = avg_ph_Z1_raw;    all_phase_V1I_s  = avg_ph_Z1_s;
all_Z1_peak_raw   = avg_Zpk_Z1_raw;   all_Z1_peak_s    = avg_Zpk_Z1_s;
all_mag_Z2_raw    = avg_mag_Z2_raw;   all_mag_Z2_s    = avg_mag_Z2_s;
all_phase_V2I_raw = avg_ph_Z2_raw;    all_phase_V2I_s  = avg_ph_Z2_s;
all_Z2_peak_raw   = avg_Zpk_Z2_raw;   all_Z2_peak_s    = avg_Zpk_Z2_s;

fprintf('\n%d raw files → %d averaged frequency points\n', length(freqs_tmp), length(all_freqs));



% ===============================================================
%%  Ploting==============BODE PLOTS — Linear Frequency Scale & Log Frequency Scale================
% ===============================================================

% Sort data
[all_freqs, sortIdx] = sort(all_freqs);

all_mag_Z1_raw    = all_mag_Z1_raw(sortIdx);
all_mag_Z1_s      = all_mag_Z1_s(sortIdx);
all_phase_V1I_raw = all_phase_V1I_raw(sortIdx);
all_phase_V1I_s   = all_phase_V1I_s(sortIdx);

all_mag_Z2_raw    = all_mag_Z2_raw(sortIdx);
all_mag_Z2_s      = all_mag_Z2_s(sortIdx);
all_phase_V2I_raw = all_phase_V2I_raw(sortIdx);
all_phase_V2I_s   = all_phase_V2I_s(sortIdx);

% ── Shared plot config ────────────────────────────────────────
xScales   = {'linear',               'log'};
figTitles = {'Bode Plot — Linear Frequency Scale', ...
             'Bode Plot — Logarithmic Frequency Scale'};
fileNames = {'bode_plot_linear.png', 'bode_plot_log.png'};

for p = 1:2

    fig = figure('Name', figTitles{p}, 'NumberTitle','off', ...
                 'Color','w', 'Position',[100 100 1000 700]);

    % ── SUBPLOT 1 : Z1 ────────────────────────────────────────
    subplot(2,1,1);

    yyaxis left
    plot(all_freqs, all_mag_Z1_raw, '-og', 'LineWidth',1.5, ...
         'MarkerSize',5, 'DisplayName','Z_1 Raw');
    hold on;
    plot(all_freqs, all_mag_Z1_s,   '--ok', 'LineWidth',1.5, ...
         'MarkerSize',5, 'DisplayName','Z_1 Smoothed');
    ylabel('Z_1 Impedance (m\Omega)', 'FontSize',11, 'FontWeight','bold');

    yyaxis right
    plot(all_freqs, all_phase_V1I_raw, '-sr', 'LineWidth',1.5, ...
         'MarkerSize',5, 'DisplayName','Phase Z_1 Raw');
    hold on;
    plot(all_freqs, all_phase_V1I_s,   '--sm', 'LineWidth',1.5, ...
         'MarkerSize',5, 'DisplayName','Phase Z_1 Smoothed');
    ylabel('Phase (°)', 'FontSize',11, 'FontWeight','bold');

    set(gca, 'XScale', xScales{p});
    xlim([min(all_freqs)*0.9  max(all_freqs)*1.1]);
    xlabel('Frequency (Hz)', 'FontSize',11, 'FontWeight','bold');
    title('Z_1 = V_1 / I', 'FontSize',12, 'FontWeight','bold');
    legend('Location','best', 'FontSize',10, 'Box','on');
    grid on; box on;
    ax = gca; ax.FontSize = 10; ax.LineWidth = 1.0;

    % ── SUBPLOT 2 : Z2 ────────────────────────────────────────
    subplot(2,1,2);

    yyaxis left
    plot(all_freqs, all_mag_Z2_raw, '-og', 'LineWidth',1.5, ...
         'MarkerSize',5, 'DisplayName','Z_2 Raw');
    hold on;
    plot(all_freqs, all_mag_Z2_s,   '--ok', 'LineWidth',1.5, ...
         'MarkerSize',5, 'DisplayName','Z_2 Smoothed');
    ylabel('Z_2 Impedance (m\Omega)', 'FontSize',11, 'FontWeight','bold');

    yyaxis right
    plot(all_freqs, all_phase_V2I_raw, '-sr', 'LineWidth',1.5, ...
         'MarkerSize',5, 'DisplayName','Phase Z_2 Raw');
    hold on;
    plot(all_freqs, all_phase_V2I_s,   '--sm', 'LineWidth',1.5, ...
         'MarkerSize',5, 'DisplayName','Phase Z_2 Smoothed');
    ylabel('Phase (°)', 'FontSize',11, 'FontWeight','bold');

    set(gca, 'XScale', xScales{p});
    xlim([min(all_freqs)*0.9  max(all_freqs)*1.1]);
    xlabel('Frequency (Hz)', 'FontSize',11, 'FontWeight','bold');
    title('Z_2 = V_2 / I', 'FontSize',12, 'FontWeight','bold');
    legend('Location','best', 'FontSize',10, 'Box','on');
    grid on; box on;
    ax = gca; ax.FontSize = 10; ax.LineWidth = 1.0;

    % ── Super-title ───────────────────────────────────────────
    sgtitle(figTitles{p}, 'FontSize',14, 'FontWeight','bold');

    % ── Save ──────────────────────────────────────────────────
    saveas(fig, fullfile(out_folder, fileNames{p}));
    fprintf('Saved: %s\n', fullfile(out_folder, fileNames{p}));

end

% ============================================================
%% Ploting ======================== NYQUIST PLOT ======================
% ============================================================

%% ── Nyquist Plot ─────────────────────────────────────────────────────────────
% One complex impedance point per recording file, swept across frequencies.
% Z1_peak / Z2_peak are already complex (V/I at dominant bin) → use directly.
% Z magnitudes were stored in mΩ, but Z_peak is in Ω (raw V/I ratio).
% Convention: x = Re(Z),  y = -Im(Z)  (capacitive arc opens upward)

% ── Sort by frequency (ascending) ────────────────────────────────────────────
[all_freqs_sorted, sortIdx] = sort(all_freqs);

Z1_raw = all_Z1_peak_raw(sortIdx);   % complex, Ω
Z1_s   = all_Z1_peak_s(sortIdx);     % complex, Ω
Z2_raw = all_Z2_peak_raw(sortIdx);   % complex, Ω
Z2_s   = all_Z2_peak_s(sortIdx);     % complex, Ω

% ── Extract Re / -Im ──────────────────────────────────────────────────────────
x_Z1_raw =  real(Z1_raw);   y_Z1_raw = -imag(Z1_raw);
x_Z1_s   =  real(Z1_s);     y_Z1_s   = -imag(Z1_s);
x_Z2_raw =  real(Z2_raw);   y_Z2_raw = -imag(Z2_raw);
x_Z2_s   =  real(Z2_s);     y_Z2_s   = -imag(Z2_s);

% ── Figure ────────────────────────────────────────────────────────────────────
figure('Name','Nyquist Plot','Color','w','Position',[100 100 960 680]);
hold on; grid on; box on;

blue = [0.00 0.45 0.74];
red  = [0.85 0.33 0.10];

% Z1 raw
h1 = plot(x_Z1_raw, y_Z1_raw, ...
    'o-', 'Color', blue, 'LineWidth', 1.4, ...
    'MarkerSize', 6, 'MarkerFaceColor', blue, ...
    'DisplayName', 'Z_1 Raw');

% Z1 smoothed
h2 = plot(x_Z1_s, y_Z1_s, ...
    's--', 'Color', blue, 'LineWidth', 1.8, ...
    'MarkerSize', 6, 'MarkerFaceColor', 'w', ...
    'DisplayName', 'Z_1 Smoothed');

% Z2 raw
h3 = plot(x_Z2_raw, y_Z2_raw, ...
    'o-', 'Color', red, 'LineWidth', 1.4, ...
    'MarkerSize', 6, 'MarkerFaceColor', red, ...
    'DisplayName', 'Z_2 Raw');

% Z2 smoothed
h4 = plot(x_Z2_s, y_Z2_s, ...
    's--', 'Color', red, 'LineWidth', 1.8, ...
    'MarkerSize', 6, 'MarkerFaceColor', 'w', ...
    'DisplayName', 'Z_2 Smoothed');

% ── Frequency labels along Z1 raw curve ───────────────────────────────────────
for k = 1:length(all_freqs_sorted)
    f = all_freqs_sorted(k);
    if f >= 1000
        lbl = sprintf('%.2f kHz', f/1000);
    else
        lbl = sprintf('%.1f Hz', f);
    end
    
end
% % ── Direction arrows: low → high frequency ────────────────────────────────────
% % Mark lowest and highest frequency points explicitly
% scatter(x_Z1_raw(1),   y_Z1_raw(1),   100, blue, 'p', 'filled', ...
%     'DisplayName', 'Low f',  'HandleVisibility','off');
% scatter(x_Z1_raw(end), y_Z1_raw(end), 100, blue, '^', 'filled', ...
%     'DisplayName', 'High f', 'HandleVisibility','off');
% scatter(x_Z2_raw(1),   y_Z2_raw(1),   100, red,  'p', 'filled', ...
%     'HandleVisibility','off');
% scatter(x_Z2_raw(end), y_Z2_raw(end), 100, red,  '^', 'filled', ...
%     'HandleVisibility','off');
% 
% text(x_Z1_raw(1),   y_Z1_raw(1),   '  \leftarrow low f',  'FontSize',8,'Color',blue);
% text(x_Z1_raw(end), y_Z1_raw(end), '  high f \rightarrow','FontSize',8,'Color',blue);

% ── Reference lines at origin ─────────────────────────────────────────────────
xline(0, ':', 'Color',[0.65 0.65 0.65], 'LineWidth',0.8, 'HandleVisibility','off');
yline(0, ':', 'Color',[0.65 0.65 0.65], 'LineWidth',0.8, 'HandleVisibility','off');

% ── Formatting ────────────────────────────────────────────────────────────────
xlabel('Re(Z)  [\Omega]',  'FontSize', 13, 'FontWeight', 'bold');
ylabel('-Im(Z)  [\Omega]', 'FontSize', 13, 'FontWeight', 'bold');
title('Nyquist Plot — EIS Impedance (one point per frequency)', ...
      'FontSize', 14, 'FontWeight', 'bold');

legend([h1 h2 h3 h4], 'Location', 'best', 'FontSize', 11, 'Box', 'on');

ax = gca;
ax.FontSize   = 11;
ax.LineWidth  = 1.1;
ax.XMinorGrid = 'on';
ax.YMinorGrid = 'on';
axis equal;

hold off;

%% ── Save ─────────────────────────────────────────────────────────────────────
saveas(gcf, fullfile(out_folder, 'nyquist_plot.png'));
fprintf('Nyquist plot saved → %s\n', fullfile(out_folder, 'nyquist_plot.png'));



% ============================================================
%% ======================== SUMMARY TABLES =====================
% ============================================================

% Prepare raw data table
Freq_noDC_raw = all_freqs(:);
Amp_noDC_raw  = max([all_mag_Z1_raw; all_mag_Z2_raw], [], 1)'; % approximate
Freq_withDC_raw = Freq_noDC_raw;   
Amp_withDC_raw  = Amp_noDC_raw;  

% Format all numeric columns to 6 decimal points
format6 = @(x) arrayfun(@(v)sprintf('%.6f', v), x, 'UniformOutput', false);

T_raw_cell = [format6(Freq_noDC_raw), format6(Freq_withDC_raw), ...
              format6(Amp_noDC_raw), format6(Amp_withDC_raw), ...
              format6(all_mag_Z1_raw(:)), format6(all_mag_Z2_raw(:)), ...
              format6(all_phase_V1I_raw(:)), format6(all_phase_V2I_raw(:))];

T_s_cell = [format6(Freq_noDC_raw), format6(Freq_withDC_raw), ...
            format6(Amp_noDC_raw), format6(Amp_withDC_raw), ...
            format6(all_mag_Z1_s(:)), format6(all_mag_Z2_s(:)), ...
            format6(all_phase_V1I_s(:)), format6(all_phase_V2I_s(:))];

colNames = {'Freq_NoDC','Freq_WithDC','Amp_NoDC','Amp_WithDC', ...
            'Z1_Imp','Z2_Imp','Phase_Z1','Phase_Z2'};

% Create figure with two table subplots
figure('Name','Summary Data Tables','NumberTitle','off','Position',[100 100 1200 600]);

% Raw Data Table
subplot(1,2,1);
uitable('Data',T_raw_cell, ...
        'ColumnName',colNames, ...
        'Units','Normalized', 'Position',[0 0 0.48 1], ...
        'FontSize',10);
title('Raw Data Table');

% Smoothed Data Table
subplot(1,2,2);
uitable('Data',T_s_cell, ...
        'ColumnName',colNames, ...
        'Units','Normalized', 'Position',[0.52 0 0.48 1], ...
        'FontSize',10);
title('Smoothed Data Table');