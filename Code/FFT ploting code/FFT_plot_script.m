
% Initialization:
Shut_R = 0.0075;




%step 1 READ CSV FILE
[filename, filepath] = uigetfile('*.csv', 'Select Scope CSV File');
if isequal(filename, 0)
    disp('Cancelled.');
    return;
end
fullpath = fullfile(filepath, filename);
fprintf('File: %s\n\n', filename);

fid = fopen(fullpath, 'r');
raw = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
fclose(fid);
lines = raw{1};

fprintf('Total lines: %d\n', length(lines));
%====================================================================
%Step 2 Phrasing header data
%======================================================================

% Find data start (first line beginning with hh:mm:ss)
dataStart = find(~cellfun(@isempty, regexp(lines, '^\d{2}:\d{2}:\d{2}')), 1);
fprintf('Data starts at line: %d\n', dataStart);

% TraceName line → split by comma, strip quotes, skip first part
traceLine = lines{find(contains(lines, '"TraceName"'), 1)};
parts = strtrim(split(traceLine, ','));
parts = regexprep(parts, '"', '');
channelNames = strtrim(parts(2:end));

% Date — split line, take 2nd value
dateLine = lines{find(contains(lines, '"Date"'), 1)};
dateParts = strtrim(split(dateLine, ','));
dateStr = regexprep(dateParts{2}, '"', '');

% Time — split line, take 2nd value
timeLine = lines{find(contains(lines, '"Time"'), 1)};
timeParts = strtrim(split(timeLine, ','));
timeStr = regexprep(timeParts{2}, '"', '');

% SampleRate — split line, take 2nd value
srLine = lines{find(contains(lines, '"SampleRate"'), 1)};
srParts = strtrim(split(srLine, ','));
Fs = str2double(srParts{2});

fprintf('Channels (%d): %s\n', length(channelNames), strjoin(channelNames, ', '));
fprintf('Date: %s\n', dateStr);
fprintf('Time: %s\n', timeStr);
fprintf('SampleRate: %.0f Hz\n', Fs);

%==========================================
%step 3
%=========================================

% Step 3: Read data, skip first 16 header lines
opts = detectImportOptions(fullpath, 'NumHeaderLines', 16);
opts.VariableNamesLine = 0;   % no header line in data
T = readtable(fullpath, opts);

% Give columns proper names
T.Properties.VariableNames = ['Time', channelNames'];

% Fix Time column: remove comma, convert to duration
T.Time = erase(string(T.Time), ',');
T.Time = duration(T.Time, 'InputFormat', 'hh:mm:ss.SSSSSSSS');
T.Time.Format = 'hh:mm:ss.SSSSSSSS';
t_sec = seconds(T.Time);
t_sec = t_sec - t_sec(1);

% Show what we got
head(T)
fprintf('Rows: %d | dT: %.9f s\n', height(T), mean(diff(t_sec)));

% ===============================================
% Step4 calc current form shunt voltage
% ===============================================

% Remove last 3 rows
T = T(1:end-3, :);
% Calculate current from shunt voltage
T.Current = double(T.("Ushunt [V]")) / Shut_R; %add this as a variable

head(T)
fprintf('Rows: %d\n', height(T));

% ===============================================
% Step 5 FFT
% ===============================================


% Remove DC offset
I = T.Current - mean(T.Current);
V1 = T.("Uz2 [V]") - mean(T.("Uz2 [V]"));
V2 = T.("Uz3 [V]") - mean(T.("Uz3 [V]"));

N = length(t_sec);

% Compute FFTs
Y_I  = fft(I);
Y_V1 = fft(V1);
Y_V2 = fft(V2);

% One-sided spectrum
halfN = floor(N/2);
f = Fs * (0:halfN) / N;

amp_I  = abs(Y_I(1:halfN+1)) / N;   amp_I(2:end-1)  = 2*amp_I(2:end-1);
amp_V1 = abs(Y_V1(1:halfN+1)) / N;  amp_V1(2:end-1) = 2*amp_V1(2:end-1);
amp_V2 = abs(Y_V2(1:halfN+1)) / N;  amp_V2(2:end-1) = 2*amp_V2(2:end-1);

% Plot
figure('Name', 'FFT Spectrum', 'NumberTitle', 'off');

subplot(3,1,1);
plot(f, amp_I, 'b', 'LineWidth', 1.2);
title('Current'); ylabel('Amplitude (A)'); xlabel('Frequency (Hz)'); grid on;

subplot(3,1,2);
plot(f, amp_V1, 'r', 'LineWidth', 1.2);
title('Uz2 [V]'); ylabel('Amplitude (V)'); xlabel('Frequency (Hz)'); grid on;

subplot(3,1,3);
plot(f, amp_V2, 'g', 'LineWidth', 1.2);
title('Uz3 [V]'); ylabel('Amplitude (V)'); xlabel('Frequency (Hz)'); grid on;

sgtitle(filename, 'Interpreter', 'none');

%===================================================

% Find top 3 peaks (skip DC bin f=0)
[~, order_I]  = sort(amp_I(2:end), 'descend');
[~, order_V1] = sort(amp_V1(2:end), 'descend');
[~, order_V2] = sort(amp_V2(2:end), 'descend');

fprintf('\n--- Top 3 Frequencies ---\n');

fprintf('\nCurrent:\n');
for k = 1:3
    idx = order_I(k) + 1;
    fprintf('  #%d: %.2f Hz | Amplitude: %.6f A\n', k, f(idx), amp_I(idx));
end

fprintf('\nUz2 [V]:\n');
for k = 1:3
    idx = order_V1(k) + 1;
    fprintf('  #%d: %.2f Hz | Amplitude: %.6f V\n', k, f(idx), amp_V1(idx));
end

fprintf('\nUz3 [V]:\n');
for k = 1:3
    idx = order_V2(k) + 1;
    fprintf('  #%d: %.2f Hz | Amplitude: %.6f V\n', k, f(idx), amp_V2(idx));
end

% ========================================
% step 6 removing cell voltage bias Uz2 (selceted)
% ========================================


bias_Uz2 = mean(T.("Uz2 [V]"));
fprintf('Uz2 DC Bias: %.6f V\n', bias_Uz2);

T.Uz2_AC = T.("Uz2 [V]") - bias_Uz2;

head(T)



% ==========================================
% step 7 amplify Uz2 voltage to better see current and coltage peak in same scale
% ==========================================



% Find peak-to-peak of Current and Uz2_AC
I_pp = max(T.Current) - min(T.Current);
Uz2_pp = max(T.Uz2_AC) - min(T.Uz2_AC);

% Scale Uz2_AC to match Current amplitude
scaleFactor = I_pp / Uz2_pp;
T.Uz2_AC_scaled = T.Uz2_AC * scaleFactor;

fprintf('Current peak-to-peak: %.4f A\n', I_pp);
fprintf('Uz2_AC peak-to-peak: %.6f V\n', Uz2_pp);
fprintf('Scale factor: %.2f\n', scaleFactor);

head(T)


% =======================
% printing plot for voltage and current
% ===========================


t_ms = seconds(T.Time - T.Time(1)) * 1000;

figure('Name', 'Current vs Amplified Voltage', 'NumberTitle', 'off');

plot(t_ms, double(T.Current));
hold on;
plot(t_ms, double(T.Uz2_AC_scaled));
hold off;

xlabel('Time (ms)');
ylabel('Amplitude');
title(sprintf('Current & Uz2 AC (scaled %.0fx) — %s', scaleFactor, filename), 'Interpreter', 'none');
legend('Current (A)', 'Uz2 AC (scaled)');
grid on;