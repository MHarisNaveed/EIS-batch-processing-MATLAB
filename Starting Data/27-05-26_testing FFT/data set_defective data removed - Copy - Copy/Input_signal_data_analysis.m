%% ============================================================
%  EIS Input Data Analysis — Raw Signal Inspection
%  Version: 2.0
%
%  CSV column layout (after 15-line header skip):
%    Col 1 — Time
%    Col 2 — Shunt voltage  → current = col2 / SHUNT_RESISTANCE
%    Col 3 — Unused / ignored
%    Col 4 — Voltage sense (default)
%    Col 5 — Voltage sense (optional)
%    Col 6 — Voltage sense (optional)
%    Col 7 — Voltage sense (optional)
%
%  Per-file output (3 subplots, shared X axis):
%    Subplot 1 — Current  (with DC offset)
%    Subplot 2 — Voltage  (with DC offset)   [column selected below]
%    Subplot 3 — Voltage  AC only            (DC mean removed)
%
%  No filtering applied — raw data inspection only.
%  One PNG saved per CSV file into the same folder.
% ============================================================


%% ============================================================
%  SECTION 0 — CONFIGURATION
%  Edit values here only. Nothing below needs to change.
% ============================================================

% --- Shunt resistor [Ω]: current = v_shunt / SHUNT_RESISTANCE
SHUNT_RESISTANCE = 0.0075;

% --- Voltage column to plot: 4, 5, 6, or 7
VOLTAGE_COL = 4;

% --- Trim: fraction removed from each end (match V28 logic)
TRIM_FRACTION = 0.10;   % 10% each side → middle 80% used

% --- CSV header lines before data
NUM_HEADER_LINES = 15;

% --- Header rows containing scope acquisition date / time
HEADER_ROW_DATE = 14;   % e.g. "2025/07/30"
HEADER_ROW_TIME = 15;   % e.g. "13:52:25.87803125"

% --- Output image format
SAVE_FORMAT = 'png';

% --- Figure size [width height] pixels
FIG_SIZE = [1400 800];


%% ============================================================
%  SECTION 1 — FOLDER SELECTION & FILE DISCOVERY
%  Outputs: folder (char), files (struct array)
% ============================================================

folder = uigetdir('', 'Select Folder Containing Waveform CSV Files');
if folder == 0
    disp('Cancelled.'); return;
end

files = dir(fullfile(folder, '*.csv'));
if isempty(files)
    errordlg('No CSV files found.', 'No Files'); return;
end

fprintf('\nFound %d CSV file(s) in:\n  %s\n\n', length(files), folder);


%% ============================================================
%  SECTION 2 — MAIN LOOP: READ → TRIM → PLOT → SAVE
%  Inputs:  folder, files, all Section 0 constants
%  Outputs: one PNG per CSV saved to folder
% ============================================================

for k = 1:length(files)

    filename = files(k).name;
    fullpath = fullfile(folder, filename);
    fprintf('[%d/%d] %s\n', k, length(files), filename);

    try

        % --------------------------------------------------------
        %  2.1  READ CSV DATA
        %  Inputs:  fullpath, NUM_HEADER_LINES
        %  Outputs: t [s], current [A], voltage [V]
        % --------------------------------------------------------

        opts = detectImportOptions(fullpath, 'NumHeaderLines', NUM_HEADER_LINES);
        T    = readtable(fullpath, opts);

        % Drop fully-missing rows (scope artefacts at file boundaries)
        T = T(~all(ismissing(T(:, 1:4)), 2), :);

        % --- Time (col 1) ---
        t_raw = T{:, 1};
        if isduration(t_raw) || isdatetime(t_raw)
            t = seconds(t_raw);
        else
            t = double(t_raw);
        end

        % --- Current: col 2 is shunt voltage, convert to Amperes ---
        v_shunt = double(T{:, 2});
        current = v_shunt / SHUNT_RESISTANCE;

        % --- Col 3 is unused / ignored ---

        % --- Voltage: user-selected column (4–7) ---
        if VOLTAGE_COL < 4 || VOLTAGE_COL > width(T)
            error('VOLTAGE_COL=%d is out of range. Table has %d columns.', ...
                  VOLTAGE_COL, width(T));
        end
        voltage = double(T{:, VOLTAGE_COL});


        % --------------------------------------------------------
        %  2.2  PARSE ACQUISITION DATETIME FROM CSV HEADER
        %  Inputs:  fullpath, HEADER_ROW_DATE, HEADER_ROW_TIME
        %  Outputs: dt_str (char, 'yyyymmdd_HHMMSS')
        % --------------------------------------------------------

        dt_str = '';
        try
            optsH                  = detectImportOptions(fullpath);
            optsH.DataLines        = [HEADER_ROW_DATE, HEADER_ROW_TIME];
            optsH.VariableNamesLine = 0;
            optsH.Delimiter        = ',';
            optsH                  = setvartype(optsH, 2, 'string');
            Tinfo                  = readtable(fullpath, optsH);

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
        %  2.3  TRIM SIGNALS — keep middle (1-2*TRIM_FRACTION)
        %  Inputs:  t, current, voltage, TRIM_FRACTION
        %  Outputs: t, current, voltage  (trimmed in-place)
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

        if isempty(t) || length(t) < 10 ...
                || any(isnan(t)) || any(isnan(current)) || any(isnan(voltage))
            warning('  "%s": invalid or too-short data — skipping.', filename);
            continue;
        end


        % --------------------------------------------------------
        %  2.5  COMPUTE DERIVED SIGNALS
        %  Inputs:  current, voltage
        %  Outputs: current_dc [A], voltage_dc [V], voltage_ac [V]
        % --------------------------------------------------------

        current_dc  = mean(current);        % DC offset of current
        voltage_dc  = mean(voltage);        % DC offset of voltage
        voltage_ac  = voltage - voltage_dc; % AC-only component


        % --------------------------------------------------------
        %  2.6  PLOT — 3 subplots, shared X axis
        %  Inputs:  t, current, voltage, voltage_ac,
        %           current_dc, voltage_dc,
        %           filename, dt_str, VOLTAGE_COL
        %  Outputs: fig handle
        % --------------------------------------------------------

        t_rel = t - t(1);   % relative time, start at 0

        C_I = [0.20 0.55 0.85];   % blue  — current
        C_V = [0.85 0.33 0.10];   % red   — voltage

        fig = figure( ...
            'Name',        sprintf('%s | %s', filename, dt_str), ...
            'NumberTitle', 'off', ...
            'Position',    [50 50 FIG_SIZE(1) FIG_SIZE(2)], ...
            'Color',       'w');

        sgtitle( ...
            sprintf('Raw Input Signal Inspection\n%s   |   %s', filename, dt_str), ...
            'FontSize', 12, 'FontWeight', 'bold', 'Interpreter', 'none');

        % --- Subplot 1: Current with DC ---
        ax1 = subplot(3, 1, 1);
        plot(t_rel, current, 'Color', C_I, 'LineWidth', 1.2);
        yline(current_dc, '--k', sprintf('DC = %.4f A', current_dc), ...
              'LineWidth', 0.8, 'LabelHorizontalAlignment', 'left');
        ylabel('Current (A)');
        title('Current — raw (with DC)');
        grid on; box on;

        % --- Subplot 2: Voltage with DC ---
        ax2 = subplot(3, 1, 2);
        plot(t_rel, voltage, 'Color', C_V, 'LineWidth', 1.2);
        yline(voltage_dc, '--k', sprintf('DC = %.6f V', voltage_dc), ...
              'LineWidth', 0.8, 'LabelHorizontalAlignment', 'left');
        ylabel('Voltage (V)');
        title(sprintf('Voltage col %d — raw (with DC)', VOLTAGE_COL));
        grid on; box on;

        % --- Subplot 3: Voltage AC only ---
        ax3 = subplot(3, 1, 3);
        plot(t_rel, voltage_ac, 'Color', C_V, 'LineWidth', 1.2);
        yline(0, '--k', 'LineWidth', 0.8);
        ylabel('Voltage AC (V)');
        xlabel('Time (s)');
        title(sprintf('Voltage col %d — AC only (DC removed)', VOLTAGE_COL));
        grid on; box on;

        % Link all X axes
        linkaxes([ax1, ax2, ax3], 'x');
        xlim(ax1, [t_rel(1), t_rel(end)]);


        % --------------------------------------------------------
        %  2.7  SAVE FIGURE
        %  Inputs:  fig, folder, filename, dt_str, SAVE_FORMAT
        %  Outputs: PNG saved to folder
        % --------------------------------------------------------

        [~, base, ~] = fileparts(filename);
        outname = sprintf('%s_%s_InputAnalysis.%s', base, dt_str, SAVE_FORMAT);
        exportgraphics(fig, fullfile(folder, outname), 'Resolution', 150);
        fprintf('  Saved: %s\n', outname);
        close(fig);

    catch ME
        warning('  ERROR "%s": %s  (line %d)', filename, ME.message, ME.stack(1).line);
    end

end % file loop

fprintf('\nAll done. Plots saved to:\n  %s\n', folder);