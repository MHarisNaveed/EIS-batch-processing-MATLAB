%% MATLAB Script to Plot Waveforms and Rename CSVs by Frequency
clc; 
clear;
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



% ===========================================================================
%% OUTER LOOP: iterate over each voltage channel Uz1-Uz16 (columns 3-18)
% ===========================================================================

combined = struct();   % persists across channels -- NOT reset inside the loop

col_start = 4;
col_end = 7;
for col_idx = col_start:col_end % depends upon the csv file channels sequences

    uz_num    = col_idx - 2;          % col 3 -> Uz1, col 4 -> Uz2, ... col 18 -> Uz16
    uz_label  = sprintf('Uz%d', uz_num);
    uz_folder = fullfile(out_folder, uz_label);
    if ~exist(uz_folder, 'dir')
        mkdir(uz_folder);
    end
    fprintf('\n\n========== Processing %s (column %d) ==========\n', uz_label, col_idx);


    % =========================================================================
    %% ______________initilization Varaibles____________________________________ (reset per channel)
    % =========================================================================



    all_freqs         = [];  % dominant frequency per file

    % Z1
    all_mag_Z1_raw    = [];  % raw magnitude (mOhm)
    all_mag_Z1_s      = [];  % smoothed magnitude (mOhm)
    all_phase_V1I_raw = [];  % raw phase (deg)
    all_phase_V1I_s   = [];  % smoothed phase (deg)
    all_Z1_peak_raw   = [];  % raw complex Z1 at peak
    all_Z1_peak_s     = [];  % smoothed complex Z1 at peak

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
            v_shunt  = double(T{:,2});
            current  = (v_shunt / -0.0075);
            voltage1 = double(T{:, col_idx});   % active channel for this iteration

            % % Trim first and last 10% -- keep middle 80% only
            % n_total  = length(t);
            % i_start  = floor(0.5 * n_total) + 1;
            % i_end    = floor(0.95 * n_total);
            %
            % t        = t(i_start:i_end);
            % current  = current(i_start:i_end);
            % voltage1 = voltage1(i_start:i_end);



            % Sanity check: must be numeric, non-empty, no NaNs
            if any(isnan(t)) || any(isnan(current)) || any(isnan(voltage1)) ...
                    || isempty(t) || length(t) < 10
                warning('"%s" [%s]: Signal or time data is invalid or too short. Skipping.', filename, uz_label);
                continue;
            end




    % ======================================================
    %% -------------FFT for Naming files and signal----------
    % =======================================================


            % Estimate frequency from current and voltage
            [freq_c,  amp_c ] = estimate_freq_amp(current,  t);
            [freq_v1, amp_v1] = estimate_freq_amp(voltage1, t);

            % Use median to reduce outlier effect
            final_freq = median([freq_c, freq_v1]);
            final_amp  = median([amp_c,  amp_v1]);  %usless btw

            % --- New file name with datetime + frequency + channel label ---
            newname = sprintf('Renamed_%s_%s_%dHz.csv', uz_label, dt_str, abs(round(final_freq)));
            newpath = fullfile(uz_folder, newname);

            % Avoid overwrite
            if exist(newpath, 'file')
                [~, base, ~] = fileparts(newname);
                newname = sprintf('%s_%s_%dHz.csv', base, dt_str, abs(round(final_freq)));
                newpath = fullfile(uz_folder, newname);
            end

            % Duplicate original CSV only once (first channel processed) --
            % all other channels reference the same underlying raw file, so
            % copying it again per channel is redundant.
            if col_idx == col_start
                copyfile(fullpath, newpath);
                fprintf('\nRenamed "%s" -> "%s" | Freq: %.2f Hz\n', filename, newname, final_freq);
            end




    % ============================================================================================
    %% ---------------------Smoothing / Noise cancellation---------------------------------------
    % ============================================================================================
            Fs = 1 / mean(diff(t));

            % 4PSF: fit and reconstruct -- zero edge effects, exact phase
            [current_s, voltage1_s] = fit_reconstruct_4psf(current, voltage1, t, freq_c);

            % Extract complete cycles using current as master clock
            [current_s, voltage1_s, cycle_idx] = extract_complete_cycles(current_s, voltage1_s);
            t_s = t(cycle_idx);




    % ============================================================================================
    %% ---------------------Ploting Raw vs Processed Signal ---------------------------------------
    % ============================================================================================
            figure('Name', [newname], 'NumberTitle', 'off');

            % ------------------ CURRENT ------------------
            subplot(2,1,1);
            plot(t, current, 'Color', [0.30 0.75 0.93], 'LineWidth', 2.4);
            hold on;
            plot(t_s, current_s, 'k', 'LineWidth', 1);
            title('Current vs Time');
            xlabel('Time (s)');
            ylabel('Current');
            legend('Raw','Smoothed');
            grid on;

            % ------------------ VOLTAGE ------------------
            subplot(2,1,2);
            plot(t, voltage1, 'r', 'LineWidth', 1);
            hold on;
            plot(t_s, voltage1_s, 'k', 'LineWidth', 1);
            title(sprintf('%s Voltage vs Time', uz_label));
            xlabel('Time (s)');
            ylabel(sprintf('Voltage (%s)', uz_label));
            legend('Raw','Smoothed');
            grid on;

            % Save plot as JPG + FIG
            [~, base, ~] = fileparts(newname);
            saveas(gcf, fullfile(uz_folder, [base, '_plot.jpg']));
            savefig(gcf, fullfile(uz_folder, [base, '_plot.fig']));
            close(gcf);




    % ============================================================================================
    %% ---------------------Generating Impedence and Phase angles --------------------------------
    % ============================================================================================


            % --- RAW ---
            [f_main, v1_main, ...
             i_amp_yes_dc_raw, i_amp_no_dc_raw, ...
             v1_amp_yes_dc_raw, v1_amp_no_dc_raw, ...
             Z1_mag_raw, Z1_phase_raw, Z1_peak_raw] ...
             = phase_shift_fft(voltage1, current, t);
            
            % Correct for inverted probe polarity on even channels
            if mod(uz_num, 2) == 0
                Z1_phase_raw = -Z1_phase_raw;
                Z1_peak_raw  = conj(Z1_peak_raw);
            end
            
            % --- SMOOTHED ---
            [~, ~, ...
             i_amp_yes_dc_s, i_amp_no_dc_s, ...
             v1_amp_yes_dc_s, v1_amp_no_dc_s, ...
             Z1_mag_s, Z1_phase_s, Z1_peak_s] ...
             = phase_shift_fft(voltage1_s, current_s, t_s);
            
            if mod(uz_num, 2) == 0
                Z1_phase_s = -Z1_phase_s;
                Z1_peak_s  = conj(Z1_peak_s);
            end

            main_freq = f_main;

            % --- Round to 6 decimals
            fmt6 = @(x) round(x,6);

            % --- Create table row
            row = {
                fmt6(main_freq), ...
                fmt6(v1_main), ...
                fmt6(i_amp_yes_dc_raw), ...
                fmt6(i_amp_yes_dc_s), ...
                fmt6(i_amp_no_dc_raw), ...
                fmt6(i_amp_no_dc_s), ...
                fmt6(v1_amp_yes_dc_raw), ...
                fmt6(v1_amp_yes_dc_s), ...
                fmt6(v1_amp_no_dc_raw), ...
                fmt6(v1_amp_no_dc_s), ...
                fmt6(Z1_mag_raw), ...
                fmt6(Z1_mag_s), ...
                fmt6(Z1_phase_raw), ...
                fmt6(Z1_phase_s)
            };

            % --- Append to main variables
            T_summary_data = [T_summary_data; row];




    % ============================================================================================
    %% ---------------------Appending data for Whole Frequency Domain------------------------------
    % ============================================================================================

            % Store the dominant frequency and corresponding phases
            all_freqs(end+1)         = main_freq;

            all_mag_Z1_raw(end+1)    = Z1_mag_raw;
            all_mag_Z1_s(end+1)      = Z1_mag_s;
            all_phase_V1I_raw(end+1) = Z1_phase_raw;
            all_phase_V1I_s(end+1)   = Z1_phase_s;
            all_Z1_peak_raw(end+1)   = Z1_peak_raw;
            all_Z1_peak_s(end+1)     = Z1_peak_s;

        catch ME
            warning('Error processing "%s" [%s]: %s', filename, uz_label, ME.message);
        end
    end  % end inner file loop


    disp(['All files processed for ' uz_label '.']);

    % -------------------------
    %% Create tables & save CSV
    % -------------------------
    colNames = {
        'I Fr (Hz)', ...
        'V1 Fr (Hz)', ...
        'I Amp DC raw', ...
        'I Amp DC Sm', ...
        'I Amp NO DC raw', ...
        'I Amp NO DC Sm', ...
        'V1 Amp DC raw', ...
        'V1 Amp DC Sm', ...
        'V1 Amp NO DC raw', ...
        'V1 Amp NO DC Sm', ...
        'Raw Imp Z1 (mOhm)', ...
        'Smoothed Imp Z1 (mOhm)', ...
        'Raw Phase Z1 (deg)', ...
        'Smoothed Phase Z1 (deg)'
    };

    if ~isempty(T_summary_data) && size(T_summary_data, 2) == length(colNames)
        T_summary = cell2table(T_summary_data, 'VariableNames', colNames);

    else
        warning('Summary table skipped for %s: column count mismatch or no data (%d rows, %d cols, %d expected).', ...
            uz_label, size(T_summary_data,1), size(T_summary_data,2), length(colNames));
        continue;
    end

    % Format all numeric values to 6 decimal places (for display only)
    data6 = arrayfun(@(x) sprintf('%.6f', x), T_summary{:,:}, 'UniformOutput', false);

    % --- Plotting Data Table ---
    fig_table = figure('Name', ['Signal Data Summary Table -- ' uz_label], ...
                       'NumberTitle','off','Position',[100 100 1200 400]);
    uitable('Data', data6, ...
            'ColumnName', T_summary.Properties.VariableNames, ...
            'Units','Normalized', ...
            'Position',[0 0 1 1], ...
            'FontSize',10);
    saveas(fig_table, fullfile(uz_folder, 'summary_table_figure.png'));
    savefig(fig_table, fullfile(uz_folder, 'summary_table_figure.fig'));
    close(fig_table);

    % Save to CSV
    writetable(T_summary, fullfile(uz_folder, 'summary_table.csv'));
    fprintf('Summary table saved as "summary_table.csv" in %s\n', uz_label);




    % ============================================================================================
    %% -- Average data points within +-5% frequency tolerance ---------------------------------
    % ============================================================================================

    tol = 0.05;  % 5% tolerance

    % Work on a copy so originals are untouched during grouping
    freqs_tmp      = all_freqs(:);
    mag_Z1_raw_tmp = all_mag_Z1_raw(:);
    mag_Z1_s_tmp   = all_mag_Z1_s(:);
    ph_Z1_raw_tmp  = all_phase_V1I_raw(:);
    ph_Z1_s_tmp    = all_phase_V1I_s(:);
    Zpk_Z1_raw_tmp = all_Z1_peak_raw(:);
    Zpk_Z1_s_tmp   = all_Z1_peak_s(:);

    % Sort by frequency ascending before grouping
    [freqs_tmp, sIdx] = sort(freqs_tmp);
    mag_Z1_raw_tmp = mag_Z1_raw_tmp(sIdx);  mag_Z1_s_tmp = mag_Z1_s_tmp(sIdx);
    ph_Z1_raw_tmp  = ph_Z1_raw_tmp(sIdx);   ph_Z1_s_tmp  = ph_Z1_s_tmp(sIdx);
    Zpk_Z1_raw_tmp = Zpk_Z1_raw_tmp(sIdx);  Zpk_Z1_s_tmp = Zpk_Z1_s_tmp(sIdx);

    % Group and average
    used           = false(size(freqs_tmp));
    avg_freqs      = [];
    avg_mag_Z1_raw = [];  avg_mag_Z1_s  = [];
    avg_ph_Z1_raw  = [];  avg_ph_Z1_s   = [];
    avg_Zpk_Z1_raw = [];  avg_Zpk_Z1_s  = [];

    for i = 1:length(freqs_tmp)
        if used(i), continue; end

        f_ref   = freqs_tmp(i);
        % +-5% band around this frequency
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

        n_grouped = sum(in_band);
        fprintf('Freq group ~%.2f Hz: averaged %d file(s)\n', avg_freqs(end), n_grouped);

        used(in_band) = true;
    end

    % -- Overwrite plotting variables with averaged versions ----------------
    all_freqs         = avg_freqs;
    all_mag_Z1_raw    = avg_mag_Z1_raw;  all_mag_Z1_s    = avg_mag_Z1_s;
    all_phase_V1I_raw = avg_ph_Z1_raw;   all_phase_V1I_s = avg_ph_Z1_s;
    all_Z1_peak_raw   = avg_Zpk_Z1_raw;  all_Z1_peak_s   = avg_Zpk_Z1_s;

    fprintf('\n%d raw files -> %d averaged frequency points\n', length(freqs_tmp), length(all_freqs));


    % ===============================================================
    %%  Ploting==============BODE PLOTS -- Linear Frequency Scale & Log Frequency Scale================
    % ===============================================================

    % Sort data
    [all_freqs, sortIdx] = sort(all_freqs);

    all_mag_Z1_raw    = all_mag_Z1_raw(sortIdx);
    all_mag_Z1_s      = all_mag_Z1_s(sortIdx);
    all_phase_V1I_raw = all_phase_V1I_raw(sortIdx);
    all_phase_V1I_s   = all_phase_V1I_s(sortIdx);

    % -- Shared plot config ------------------------------------------------
    xScales   = {'linear',               'log'};
    figTitles = {['Bode Plot -- Linear Frequency Scale -- ' uz_label], ...
                 ['Bode Plot -- Logarithmic Frequency Scale -- ' uz_label]};
    fileNames = {'bode_plot_linear.png', 'bode_plot_log.png'};

    for p = 1:2

        fig = figure('Name', figTitles{p}, 'NumberTitle','off', ...
                     'Color','w', 'Position',[100 100 1000 500]);

        % -- SUBPLOT : Z1 --------------------------------------------------
        yyaxis left
        plot(all_freqs, all_mag_Z1_raw, '-og', 'LineWidth',1.5, ...
             'MarkerSize',5, 'DisplayName','Z_1 Raw');
        hold on;
        plot(all_freqs, all_mag_Z1_s,   '--ok', 'LineWidth',1.5, ...
             'MarkerSize',5, 'DisplayName','Z_1 Smoothed');
        ylabel(['Z_1 Impedance (m\Omega) -- ' uz_label], 'FontSize',11, 'FontWeight','bold');

        yyaxis right
        plot(all_freqs, all_phase_V1I_raw, '-sr', 'LineWidth',1.5, ...
             'MarkerSize',5, 'DisplayName','Phase Z_1 Raw');
        hold on;
        plot(all_freqs, all_phase_V1I_s,   '--sm', 'LineWidth',1.5, ...
             'MarkerSize',5, 'DisplayName','Phase Z_1 Smoothed');
        ylabel('Phase (deg)', 'FontSize',11, 'FontWeight','bold');

        set(gca, 'XScale', xScales{p});
        xlim([min(all_freqs)*0.9  max(all_freqs)*1.1]);
        xlabel('Frequency (Hz)', 'FontSize',11, 'FontWeight','bold');
        title(['Z_1 = ' uz_label ' / I'], 'FontSize',12, 'FontWeight','bold');
        legend('Location','best', 'FontSize',10, 'Box','on');
        grid on; box on;
        ax = gca; ax.FontSize = 10; ax.LineWidth = 1.0;

        % -- Super-title ---------------------------------------------------
        sgtitle(figTitles{p}, 'FontSize',14, 'FontWeight','bold');

        % -- Save ----------------------------------------------------------
        [~, bodeBase, ~] = fileparts(fileNames{p});
        saveas(fig, fullfile(uz_folder, fileNames{p}));
        savefig(fig, fullfile(uz_folder, [bodeBase, '.fig']));
        fprintf('Saved: %s\n', fullfile(uz_folder, fileNames{p}));
        close(fig);

    end

    % ============================================================
    %% Ploting ======================== NYQUIST PLOT ======================
    % ============================================================

    %% -- Nyquist Plot ---------------------------------------------------
    % One complex impedance point per recording file, swept across frequencies.
    % Z1_peak is already complex (V/I at dominant bin) -> use directly.
    % Z magnitudes were stored in mOhm, but Z_peak is in Ohm (raw V/I ratio).
    % Convention: x = Re(Z),  y = -Im(Z)  (capacitive arc opens upward)

    % -- Sort by frequency (ascending) ------------------------------------
    [all_freqs_sorted, sortIdx] = sort(all_freqs);

    Z1_raw = all_Z1_peak_raw(sortIdx);   % complex, Ohm
    Z1_s   = all_Z1_peak_s(sortIdx);     % complex, Ohm

    combined.(uz_label).freqs     = all_freqs_sorted;
    combined.(uz_label).mag_raw   = all_mag_Z1_raw;    % already sorted earlier (Bode section)
    combined.(uz_label).mag_s     = all_mag_Z1_s;      % already sorted earlier (Bode section)
    combined.(uz_label).phase_raw = all_phase_V1I_raw; % already sorted earlier (Bode section)
    combined.(uz_label).phase_s   = all_phase_V1I_s;   % already sorted earlier (Bode section)
    combined.(uz_label).Zpeak_raw = Z1_raw;
    combined.(uz_label).Zpeak_s   = Z1_s;


    % -- Extract Re / -Im -------------------------------------------------
    x_Z1_raw =  real(Z1_raw);   y_Z1_raw = -imag(Z1_raw);
    x_Z1_s   =  real(Z1_s);     y_Z1_s   = -imag(Z1_s);

    % -- Figure ------------------------------------------------------------
    fig_ny = figure('Name', ['Nyquist Plot -- ' uz_label], 'Color','w', 'Position',[100 100 960 680]);
    hold on; grid on; box on;

    blue = [0.00 0.45 0.74];

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

    % -- Frequency labels along Z1 raw curve ------------------------------
    for kk = 1:length(all_freqs_sorted)
        f = all_freqs_sorted(kk);
        if f >= 1000
            lbl = sprintf('%.2f kHz', f/1000);
        else
            lbl = sprintf('%.1f Hz', f);
        end

    end
    % % -- Direction arrows: low -> high frequency --------------------------
    % % Mark lowest and highest frequency points explicitly
    % scatter(x_Z1_raw(1),   y_Z1_raw(1),   100, blue, 'p', 'filled', ...
    %     'DisplayName', 'Low f',  'HandleVisibility','off');
    % scatter(x_Z1_raw(end), y_Z1_raw(end), 100, blue, '^', 'filled', ...
    %     'DisplayName', 'High f', 'HandleVisibility','off');
    %
    % text(x_Z1_raw(1),   y_Z1_raw(1),   '  \leftarrow low f',  'FontSize',8,'Color',blue);
    % text(x_Z1_raw(end), y_Z1_raw(end), '  high f \rightarrow','FontSize',8,'Color',blue);

    % -- Reference lines at origin ----------------------------------------
    xline(0, ':', 'Color',[0.65 0.65 0.65], 'LineWidth',0.8, 'HandleVisibility','off');
    yline(0, ':', 'Color',[0.65 0.65 0.65], 'LineWidth',0.8, 'HandleVisibility','off');

    % -- Formatting --------------------------------------------------------
    xlabel('Re(Z)  [\Omega]',  'FontSize', 13, 'FontWeight', 'bold');
    ylabel('-Im(Z)  [\Omega]', 'FontSize', 13, 'FontWeight', 'bold');
    title(['Nyquist Plot -- EIS Impedance (one point per frequency) -- ' uz_label], ...
          'FontSize', 14, 'FontWeight', 'bold');

    legend([h1 h2], 'Location', 'best', 'FontSize', 11, 'Box', 'on');

    ax = gca;
    ax.FontSize   = 11;
    ax.LineWidth  = 1.1;
    ax.XMinorGrid = 'on';
    ax.YMinorGrid = 'on';
    axis equal;

    hold off;

    %% -- Save -------------------------------------------------------------
    saveas(fig_ny, fullfile(uz_folder, 'nyquist_plot.png'));
    savefig(fig_ny, fullfile(uz_folder, 'nyquist_plot.fig'));
    fprintf('Nyquist plot saved -> %s\n', fullfile(uz_folder, 'nyquist_plot.png'));
    close(fig_ny);



    % ============================================================
    %% ======================== SUMMARY TABLES =====================
    % ============================================================

    % Prepare raw data table
    Freq_noDC_raw   = all_freqs(:);
    Amp_noDC_raw    = all_mag_Z1_raw(:);  % approximate
    Freq_withDC_raw = Freq_noDC_raw;
    Amp_withDC_raw  = Amp_noDC_raw;

    % Format all numeric columns to 6 decimal points
    format6 = @(x) arrayfun(@(v)sprintf('%.6f', v), x, 'UniformOutput', false);

    T_raw_cell = [format6(Freq_noDC_raw), format6(Freq_withDC_raw), ...
                  format6(Amp_noDC_raw),  format6(Amp_withDC_raw), ...
                  format6(all_mag_Z1_raw(:)), format6(all_phase_V1I_raw(:))];

    T_s_cell   = [format6(Freq_noDC_raw), format6(Freq_withDC_raw), ...
                  format6(Amp_noDC_raw),  format6(Amp_withDC_raw), ...
                  format6(all_mag_Z1_s(:)), format6(all_phase_V1I_s(:))];

    colNamesPlot = {'Freq_NoDC','Freq_WithDC','Amp_NoDC','Amp_WithDC','Z1_Imp','Phase_Z1'};

    % Create figure with two table subplots
    fig_tbl = figure('Name', ['Summary Data Tables -- ' uz_label], ...
                     'NumberTitle','off','Position',[100 100 1200 600]);

    % Raw Data Table
    subplot(1,2,1);
    uitable('Data',T_raw_cell, ...
            'ColumnName',colNamesPlot, ...
            'Units','Normalized', 'Position',[0 0 0.48 1], ...
            'FontSize',10);
    title('Raw Data Table');

    % Smoothed Data Table
    subplot(1,2,2);
    uitable('Data',T_s_cell, ...
            'ColumnName',colNamesPlot, ...
            'Units','Normalized', 'Position',[0.52 0 0.48 1], ...
            'FontSize',10);
    title('Smoothed Data Table');

    saveas(fig_tbl, fullfile(uz_folder, 'summary_data_tables.png'));
    savefig(fig_tbl, fullfile(uz_folder, 'summary_data_tables.fig'));
    close(fig_tbl);


    fprintf('\n--- Finished %s ---\n', uz_label);

end  % end col_idx loop (Uz1-Uz16)

disp('All channels processed.');








%% ---------------------  COMBINED MULTI-CHANNEL PLOTS  ---------------------------------------

chLabels = fieldnames(combined);
nCh      = numel(chLabels);
cmap     = lines(nCh);

xScalesC   = {'linear', 'log'};
figTitlesC = {'Combined Bode Plot -- All Channels -- Linear Frequency Scale', ...
              'Combined Bode Plot -- All Channels -- Logarithmic Frequency Scale'};
fileNamesC = {'combined_bode_linear', 'combined_bode_log'};

for p = 1:2
    fig = figure('Name', figTitlesC{p}, 'NumberTitle','off', 'Color','w', 'Position',[80 80 1200 650]);

    rawLines = gobjects(nCh,1);
    sLines   = gobjects(nCh,1);

    yyaxis left
    hold on;
    for c = 1:nCh
        d = combined.(chLabels{c});
        col = cmap(c,:);
        rawLines(c) = plot(d.freqs, d.mag_raw, '--', 'Color', col, 'LineWidth',1.3, ...
            'Marker','o','MarkerSize',4, 'DisplayName',[chLabels{c} ' Raw'], 'HandleVisibility','off');
        sLines(c) = plot(d.freqs, d.mag_s, '-', 'Color', col, 'LineWidth',1.6, ...
            'Marker','o','MarkerSize',4, 'DisplayName',[chLabels{c} ' Smoothed']);
    end
    ylabel('Z_1 Impedance (m\Omega)', 'FontSize',11, 'FontWeight','bold');

    yyaxis right
    hold on;
    for c = 1:nCh
        d = combined.(chLabels{c});
        col = cmap(c,:);
        plot(d.freqs, d.phase_raw, '--', 'Color', col, 'LineWidth',1.0, 'Marker','s','MarkerSize',4, 'HandleVisibility','off');
        plot(d.freqs, d.phase_s, '-', 'Color', col, 'LineWidth',1.3, 'Marker','s','MarkerSize',4, 'HandleVisibility','off');
    end
    ylabel('Phase (deg)', 'FontSize',11, 'FontWeight','bold');

    set(gca, 'XScale', xScalesC{p});
    xlabel('Frequency (Hz)', 'FontSize',11, 'FontWeight','bold');
    title(figTitlesC{p}, 'FontSize',13, 'FontWeight','bold');
    legend(sLines, 'Location','eastoutside', 'FontSize',9, 'Box','on');
    grid on; box on;
    ax = gca; ax.FontSize = 10; ax.LineWidth = 1.0;

    uicontrol(fig, 'Style','checkbox', 'String','Show Raw', 'Units','normalized', ...
        'Position',[0.01 0.95 0.15 0.04], 'Value',1, 'BackgroundColor','w', ...
        'Callback', @(src,~) set(rawLines, 'Visible', logical_to_vis(src.Value)));

    uicontrol(fig, 'Style','checkbox', 'String','Show Smoothed', 'Units','normalized', ...
        'Position',[0.01 0.90 0.18 0.04], 'Value',1, 'BackgroundColor','w', ...
        'Callback', @(src,~) set(sLines, 'Visible', logical_to_vis(src.Value)));

    savefig(fig, fullfile(out_folder, [fileNamesC{p} '.fig']));
    saveas(fig, fullfile(out_folder, [fileNamesC{p} '.png']));
    close(fig);
end

fig_ny = figure('Name', 'Combined Nyquist Plot -- All Channels', 'Color','w', 'Position',[80 80 1100 750]);
hold on; grid on; box on;

rawLinesNy = gobjects(nCh,1);
sLinesNy   = gobjects(nCh,1);

for c = 1:nCh
    d   = combined.(chLabels{c});
    col = cmap(c,:);
    x_raw =  real(d.Zpeak_raw);  y_raw = -imag(d.Zpeak_raw);
    x_s   =  real(d.Zpeak_s);    y_s   = -imag(d.Zpeak_s);

    rawLinesNy(c) = plot(x_raw, y_raw, 'o--', 'Color', col, 'LineWidth',1.3, ...
        'MarkerSize',5, 'MarkerFaceColor','w', 'DisplayName',[chLabels{c} ' Raw'], 'HandleVisibility','off');
    sLinesNy(c) = plot(x_s, y_s, 'o-', 'Color', col, 'LineWidth',1.7, ...
        'MarkerSize',5, 'MarkerFaceColor',col, 'DisplayName',[chLabels{c} ' Smoothed']);
end

xline(0, ':', 'Color',[0.65 0.65 0.65], 'LineWidth',0.8, 'HandleVisibility','off');
yline(0, ':', 'Color',[0.65 0.65 0.65], 'LineWidth',0.8, 'HandleVisibility','off');

xlabel('Re(Z)  [\Omega]', 'FontSize',13, 'FontWeight','bold');
ylabel('-Im(Z)  [\Omega]', 'FontSize',13, 'FontWeight','bold');
title('Combined Nyquist Plot -- All Channels', 'FontSize',14, 'FontWeight','bold');
legend(sLinesNy, 'Location','eastoutside', 'FontSize',9, 'Box','on');

ax = gca; ax.FontSize = 11; ax.LineWidth = 1.1; ax.XMinorGrid = 'on'; ax.YMinorGrid = 'on';
axis equal;
hold off;

uicontrol(fig_ny, 'Style','checkbox', 'String','Show Raw', 'Units','normalized', ...
    'Position',[0.01 0.95 0.15 0.04], 'Value',1, 'BackgroundColor','w', ...
    'Callback', @(src,~) set(rawLinesNy, 'Visible', logical_to_vis(src.Value)));

uicontrol(fig_ny, 'Style','checkbox', 'String','Show Smoothed', 'Units','normalized', ...
    'Position',[0.01 0.90 0.18 0.04], 'Value',1, 'BackgroundColor','w', ...
    'Callback', @(src,~) set(sLinesNy, 'Visible', logical_to_vis(src.Value)));

savefig(fig_ny, fullfile(out_folder, 'combined_nyquist.fig'));
saveas(fig_ny, fullfile(out_folder, 'combined_nyquist.png'));
close(fig_ny);

disp('Combined multi-channel plots complete.');


% ============================================================================================
%% ---------------------  Functions Definitions ---------------------------------------
% ============================================================================================

function v = logical_to_vis(val)
    if val
        v = 'on';
    else
        v = 'off';
    end
end


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

    % Symmetric frequency range when using fft but half part (i.e. to match [0, +Df, ..., +Fs/2-Df])
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
    amp  = max_amp;

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
%% -- 4PSF Fit + Reconstruct (replaces lockin_reconstruct) -- single channel version ---------
% ============================================================================================
function [i_out, v1_out] = fit_reconstruct_4psf(current, voltage1, t, f0_init)
    % Four-Parameter Sine Fit -- IEEE 1241 method
    % Model: x(t) = A*cos(2*pi*f0*t) + B*sin(2*pi*f0*t) + C + D*t
    %
    % Zero edge effects -- no filter, no convolution, no padding.
    % Phase preserved exactly -- voltage uses same f0 as current, no independent fit.
    % Transient rejection -- pass 1 finds bad samples, pass 2 refits on clean ones.
    %
    % C = DC offset  (voltage DC bias handled automatically)
    % D = linear drift (handles any slow ramp in background)

    t = t(:);

    % -- Refine frequency from current (Gauss-Newton, IEEE 1241 Annex B) --
    f0 = refine_freq_gauss_newton(current, t, f0_init);
    fprintf('4PSF | f0_fft=%.4f Hz -> f0_refined=%.6f Hz\n', f0_init, f0);

    % -- Pass 1: full fit on current to locate transient samples ----------
    resid1     = fit_4psf_residual(current, t, f0);
    global_mad = median(abs(resid1 - median(resid1)));

    % Relaxed threshold -- only flag severe outliers
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

        % Still not enough -- find longest contiguous good block
        if sum(~bad) < min_clean
            good_runs  = ~bad;
            run_starts = find(diff([0; good_runs]) == 1);
            run_ends   = find(diff([good_runs; 0]) == -1);
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
                bad(1:floor(0.15*n))     = true;
                bad(floor(0.85*n)+1:end) = true;
                fprintf('4PSF | last resort: middle 70%%\n');
            end
        end
    else
        fprintf('4PSF | pass1: %d/%d samples clean (%.1f%%)\n', ...
                sum(~bad), length(t), 100*mean(~bad));
    end

    good = ~bad;

    % -- Pass 2: refit all signals on clean samples, same mask ------------
    % Current drives f0 -- voltage uses identical f0, phase never touched
    [A_I,  B_I,  C_I,  D_I ] = solve_4psf(current(good),  t(good), f0);
    [A_V1, B_V1, C_V1, D_V1] = solve_4psf(voltage1(good), t(good), f0);

    % -- Reconstruct on full original time axis ----------------------------
    % Analytically evaluated -- no filter, no edge artifact
    i_out  = eval_4psf(t, A_I,  B_I,  C_I,  D_I,  f0);
    v1_out = eval_4psf(t, A_V1, B_V1, C_V1, D_V1, f0);

    fprintf('4PSF | I:  amp=%.5f  phase=%.4f deg\n', ...
            sqrt(A_I^2+B_I^2), atan2d(B_I, A_I));
    fprintf('4PSF | V1: amp=%.6f  phase=%.4f deg\n', ...
            sqrt(A_V1^2+B_V1^2), atan2d(B_V1, A_V1));
    fprintf('4PSF | DeltaPhi(V1-I) = %.6f deg\n', ...
            atan2d(B_V1,A_V1) - atan2d(B_I,A_I));
end

% -- Gauss-Newton frequency refinement ------------------------------------
function f1 = refine_freq_gauss_newton(x, t, f0_init)
    t  = t(:) - t(1);   % <- shift to start from zero
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

% -- Single 4PSF solve ----------------------------------------------------
function [A, B, C, D] = solve_4psf(x, t, f0)
    t  = t(:) - t(1);   % <- shift to start from zero
    x  = x(:);
    w  = 2*pi*f0;
    M  = [cos(w.*t), sin(w.*t), ones(size(t)), t];
    cf = M \ x;
    A  = cf(1);  B = cf(2);  C = cf(3);  D = cf(4);
end

% -- Residual from full-data 4PSF -----------------------------------------
function r = fit_4psf_residual(x, t, f0)
    [A, B, C, D] = solve_4psf(x, t, f0);
    r = x(:) - eval_4psf(t, A, B, C, D, f0);
end

% -- Evaluate 4PSF model --------------------------------------------------
function y = eval_4psf(t, A, B, C, D, f0)
    t  = t(:) - t(1);   % <- shift to start from zero
    w  = 2*pi*f0;
    y  = A.*cos(w.*t) + B.*sin(w.*t) + C + D.*t;
end

% ---------------------------
%% Phase function: Bode Point  -- single channel version
% ---------------------------
function [f_main, v1_main, ...
          i_amp_yes_dc, i_amp_no_dc, ...
          v1_amp_yes_dc, v1_amp_no_dc, ...
          Z1_mag, Z1_phase_main, Z1_peak] ...
          = phase_shift_fft(V1, I, t)

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

    f = Fs*(0:halfN)/N;

    % --- One-sided spectrum ---
    I_pos  = I_fft(1:halfN+1);
    V1_pos = V1_fft(1:halfN+1);

    % --- Amplitude: normalize ---
    I_amp  = abs(I_pos)/N;
    V1_amp = abs(V1_pos)/N;

    % --- Amplitude: one-sided correction (double all bins except DC and Nyquist) ---
    I_amp(2:end-1)  = 2*I_amp(2:end-1);
    V1_amp(2:end-1) = 2*V1_amp(2:end-1);

    % --- Amplitude summary ---
    i_amp_yes_dc  = max(I_amp);
    i_amp_no_dc   = max(I_amp(2:end));

    v1_amp_yes_dc = max(V1_amp);
    v1_amp_no_dc  = max(V1_amp(2:end));

    fprintf('\n --- I:  Amplitude (WITH DC):    %.6f\n', i_amp_yes_dc);
    fprintf('\n --- I:  Amplitude (WITHOUT DC): %.6f\n', i_amp_no_dc);
    fprintf('\n --- V1: Amplitude (WITH DC):    %.6f\n', v1_amp_yes_dc);
    fprintf('\n --- V1: Amplitude (WITHOUT DC): %.6f\n', v1_amp_no_dc);

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

    % --- Complex impedance spectrum ---
    Z1 = V1_pos ./ I_pos;

    % --- Magnitude at dominant frequency (mOhm) ---
    Z1_mag = abs(Z1(idx)) * 1000;

    % --- Phase spectrum (deg) ---
    Z1_phase = rad2deg(angle(Z1));

    % --- Phase at dominant frequency ---
    Z1_phase_main = Z1_phase(idx);

    % --- Complex peak value at dominant frequency ---
    Z1_peak = Z1(idx);

    fprintf('\n--- Impedance ---\n');
    fprintf('Z1 = %.3f mOhm | Phase = %.2f deg\n', Z1_mag, Z1_phase_main);

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

    % Lowpass -- one cycle moving average
    win    = max(3, round(Fs / f0));
    b_lp   = ones(win, 1) / win;

    I_filt = filtfilt(b_lp, 1, I_comp);
    Q_filt = filtfilt(b_lp, 1, Q_comp);

    % Reconstruct AC fundamental, then restore DC
    y = 2 * (I_filt .* ref_cos + Q_filt .* ref_sin) + dc_offset;
end
% ---- END ADD ----


%===============================================
%% -----framing and frame dropping -- single channel version
%====================================================
function [i_out, v1_out, idx_range] = extract_complete_cycles(current_s, voltage1_s)
    n           = length(current_s);
    i_start     = floor(0.20 * n) + 1;
    i_end       = floor(0.80 * n);
    robust_mean = mean(current_s(i_start:i_end));
    i_centered  = current_s - robust_mean;
    crossings   = find(i_centered(1:end-1) < 0 & i_centered(2:end) >= 0);

    % Default fallback
    idx_range = (1:n)';

    if length(crossings) < 3
        warning('Not enough zero crossings -- returning original signals.');
        i_out  = current_s;
        v1_out = voltage1_s;
        return;
    end

    % Estimate one cycle length from crossings
    cycle_len = mean(diff(crossings));

    % How many samples exist before first crossing
    samples_before = crossings(1) - 1;

    % Threshold: if first partial frame is smaller than 20% of a cycle
    % it is a tiny fragment -- drop it by moving to next crossing
    tiny_threshold = 0.20 * cycle_len;

    if samples_before < tiny_threshold
        % Tiny fragment at start -- drop it, use next crossing
        c_start = crossings(2);
        fprintf('Tiny start fragment (%d samples < %.1f threshold) -- dropped first partial frame\n', ...
            samples_before, tiny_threshold);
    else
        % Big enough partial frame -- crossings(1) is already a good start
        c_start = crossings(1);
        fprintf('Large start fragment (%d samples >= %.1f threshold) -- kept from first crossing\n', ...
            samples_before, tiny_threshold);
    end

    % Same logic for end
    samples_after = n - crossings(end);

    if samples_after < tiny_threshold
        c_end = crossings(end-1);
        fprintf('Tiny end fragment (%d samples < %.1f threshold) -- dropped last partial frame\n', ...
            samples_after, tiny_threshold);
    else
        c_end = crossings(end);
        fprintf('Large end fragment (%d samples >= %.1f threshold) -- kept to last crossing\n', ...
            samples_after, tiny_threshold);
    end

    if c_start >= c_end
        warning('Cycle extraction empty range -- returning original signals.');
        i_out  = current_s;
        v1_out = voltage1_s;
        return;
    end

    fprintf('Cycle extraction: kept samples %d to %d of %d\n', c_start, c_end, n);

    idx_range = (c_start:c_end)';
    i_out     = current_s(idx_range);
    v1_out    = voltage1_s(idx_range);
end