%% --- CONFIGURATION SECTION ---
Shut_R = 0.0075;

% 1. CHOOSE YOUR CHANNEL HERE (e.g., 'Uz1 [V]', 'Uz2 [V]', 'Ushunt [V]')
targetChannel = 'Uz2 [V]'; 

% 2. STFT WINDOW SETTING (Controls time chunk width, keep at 512)
win_len = 5000; 

% 3. CHOOSE MAX DISPLAY FREQUENCY (Hz) TO ZOOM Y-AXIS AUTOMATICALLY
% Since your interest is around 400Hz, let's cap the plot view to 2000Hz 
% so you don't look at miles of empty blue space up to 10000Hz!
max_display_freq = 6000; 
%% -----------------------------

% Step 1: Read CSV File
[filename, filepath] = uigetfile('*.csv', 'Select Scope CSV File');
if isequal(filename, 0), disp('Cancelled.'); return; end
fullpath = fullfile(filepath, filename);

fid = fopen(fullpath, 'r');
raw = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
fclose(fid);
lines = raw{1};

% Parse SampleRate
srLine = lines{find(contains(lines, '"SampleRate"'), 1)};
srParts = strtrim(split(srLine, ','));
Fs = str2double(srParts{2});

% Step 2: Import Data Table
opts = detectImportOptions(fullpath, 'NumHeaderLines', 16);
opts.VariableNamesLine = 0; 
T = readtable(fullpath, opts);

% Extract Channel Names from header
traceLine = lines{find(contains(lines, '"TraceName"'), 1)};
parts = strtrim(split(traceLine, ','));
parts = regexprep(parts, '"', '');
channelNames = strtrim(parts(2:end));
T.Properties.VariableNames = ['Time', channelNames'];

% Process Time and clean rows
T = T(1:end-3, :);
T.Time = erase(string(T.Time), ',');
T.Time = duration(T.Time, 'InputFormat', 'hh:mm:ss.SSSSSSSS');
t_sec = seconds(T.Time - T.Time(1));

% Step 3: Extract and Demean Chosen Signal
if ~any(strcmp(T.Properties.VariableNames, targetChannel))
    error('Channel "%s" not found in the CSV! Check spelling.', targetChannel);
end

signal_raw = double(T.(targetChannel));
signal_AC = signal_raw - mean(signal_raw); 
N = length(t_sec);

% =====================================================================
% Step 4: Normal Global FFT (Whole Signal)
% =====================================================================
Y = fft(signal_AC);
halfN = floor(N/2);
f_fft = Fs * (0:halfN) / N;

amp_fft = abs(Y(1:halfN+1)) / N;   
amp_fft(2:end-1) = 2 * amp_fft(2:end-1);

[~, order] = sort(amp_fft(2:end), 'descend');

fprintf('\n==================================================\n');
fprintf('  GLOBAL FFT RESULTS FOR: %s\n', targetChannel);
fprintf('==================================================\n');
for k = 1:3
    idx = order(k) + 1;
    fprintf('  Peak #%d: %.2f Hz | Amplitude: %.6f V\n', k, f_fft(idx), amp_fft(idx));
end

% Plot 1: Normal Global FFT
figure('Name', ['Global FFT - ' targetChannel], 'NumberTitle', 'off', 'Color', 'w');
plot(f_fft, amp_fft, 'Color', [0 0.5 0], 'LineWidth', 1.2);
xlabel('Frequency (Hz)', 'FontWeight', 'bold');
ylabel('Physical Amplitude (V)', 'FontWeight', 'bold');
title(sprintf('%s Global FFT Spectrum — %s', targetChannel, filename), 'Interpreter', 'none');
xlim([0, max_display_freq]); % Zoom X axis automatically to your region of interest
grid on;

ax1 = gca;
ax1.XAxis.Exponent = 0;          
ax1.YAxis.Exponent = 0;          
ax1.XAxis.TickLabelFormat = '%g'; 
ax1.YAxis.TickLabelFormat = '%g';


% =====================================================================
% Step 5: Short-Time Fourier Transform (STFT Chunks)
% =====================================================================
win = hann(min(win_len, floor(N/4)));
overlap = floor(length(win) * 0.75); 

% --- THE RESOLUTION FIX ---
% We force MATLAB to pad the 512-sample window with zeros up to 16,384 points.
% This interpolates the frequency pixels, giving you razor-sharp rows.
nfft = 16384; 

[S, F_stft, Time_stft] = stft(signal_AC, Fs, 'Window', win, 'OverlapLength', overlap, 'FFTLength', nfft);

% Normalize STFT matrix (Must scale by window length, NOT nfft)
S_mag = abs(S) / length(win);
S_mag(2:end-1, :) = 2 * S_mag(2:end-1, :);

% Keep positive spectrum frequencies
pos_idx = F_stft >= 0;
F_plot = F_stft(pos_idx);
S_plot = S_mag(pos_idx, :);

% Calculate and Display STFT Stats
chunk_duration_ms = (length(win) / Fs) * 1000;
time_step_ms = ((length(win) - overlap) / Fs) * 1000;
freq_resolution_hz = Fs / nfft;

fprintf('\n==================================================\n');
fprintf('  STFT HIGH-RESOLUTION CHUNK STATS\n');
fprintf('==================================================\n');
fprintf('  Each time chunk width : %.2f ms\n', chunk_duration_ms);
fprintf('  Time step between columns : %.2f ms\n', time_step_ms);
fprintf('  Frequency bin resolution : %.2f Hz per pixel row (WAS ~200+ Hz!)\n', freq_resolution_hz);
fprintf('==================================================\n\n');

% Plot 2: Beautiful 2D Spectrogram Heat Map
figure('Name', ['STFT Heatmap - ' targetChannel], 'NumberTitle', 'off', 'Color', 'w');
imagesc(Time_stft, F_plot, S_plot);
set(gca, 'YDir', 'normal'); 
xlabel('Time (seconds)', 'FontWeight', 'bold');
ylabel('Frequency (Hz)', 'FontWeight', 'bold');
title(sprintf('%s High-Res STFT Spectrogram — %s', targetChannel, filename), 'Interpreter', 'none');

% Limit display to your region of interest (e.g., 0 to 2000Hz) so 400Hz is huge
ylim([0, max_display_freq]);

% Intelligent percentile-based color scaling restricted to our viewable area
visible_rows = F_plot <= max_display_freq;
max_brightness = prctile(reshape(S_plot(visible_rows, :), [], 1), 99.5); 
if max_brightness > 0, clim([0, max_brightness]); end

colorbar;
colormap(jet); 
grid on;

ax2 = gca;
ax2.XAxis.Exponent = 0;          
ax2.YAxis.Exponent = 0;          
ax2.XAxis.TickLabelFormat = '%g'; 
ax2.YAxis.TickLabelFormat = '%g';