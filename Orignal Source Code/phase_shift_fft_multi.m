%% SECTION = 3 ////////////////////////////////////////////////////////////

% ---------------------------
% Phase function: Bode Point
% ---------------------------

function results = phase_shift_fft_multi(V, I, V_s, I_s, t)
    % -------------------------------
    % Generalized FFT Phase & Impedance
    % V     : [N x numVoltages] raw voltage matrix
    % I     : [N x 1] raw current
    % V_s   : [N x numVoltages] smoothed voltages
    % I_s   : [N x 1] smoothed current
    % t     : [N x 1] time vector
    %
    % OUTPUT:
    % results : struct containing
    %   .freq_main         : dominant frequency (from current)
    %   .volt_freq         : [1 x numVoltages] frequencies from each voltage
    %   .amp_raw           : [1 x numVoltages] peak amplitude (raw voltage)
    %   .amp_smooth        : [1 x numVoltages] peak amplitude (smoothed voltage)
    %   .V_amp_raw         : full FFT amplitude for each voltage (raw)
    %   .V_amp_smooth      : full FFT amplitude for each voltage (smoothed)
    %   .I_amp_raw         : full FFT amplitude of current (raw)
    %   .I_amp_smooth      : full FFT amplitude of current (smoothed)
    %   .Z_mag_raw         : [1 x numVoltages] impedance magnitudes (mΩ)
    %   .Z_mag_s           : smoothed impedance magnitudes (mΩ)
    %   .Z_phase_raw       : phases (deg)
    %   .Z_phase_s         : smoothed phases (deg)
    %   .Z_peak_raw        : complex impedance at dominant freq
    %   .Z_peak_s          : smoothed complex impedance at dominant freq
    % -------------------------------

    N = length(t);
    dt = mean(diff(t));
    Fs = 1/dt;
    halfN = floor(N/2);

    numVoltages = size(V,2);

    % --- FFT of current ---
    I_fft   = fft(I);
    I_s_fft = fft(I_s);

    % Frequency vector
    f = Fs*(0:halfN)/N;

    % One-sided FFT
    I_pos   = I_fft(1:halfN+1);
    I_s_pos = I_s_fft(1:halfN+1);

    % One-sided amplitude normalization
    I_amp   = abs(I_pos)/N;   I_amp(2:end-1) = 2*I_amp(2:end-1);
    I_amp_s = abs(I_s_pos)/N; I_amp_s(2:end-1) = 2*I_amp_s(2:end-1);

    % Dominant frequency from current
    [~, idx] = max(I_amp(2:end)); idx = idx + 1;
    freq_main = f(idx);

    % Prepare storage arrays
    volt_freq    = zeros(1,numVoltages);
    amp_raw      = zeros(1,numVoltages);
    amp_smooth   = zeros(1,numVoltages);
    V_amp_raw    = zeros(halfN+1,numVoltages);
    V_amp_smooth = zeros(halfN+1,numVoltages);
    Z_mag_raw    = zeros(1,numVoltages);
    Z_mag_s      = zeros(1,numVoltages);
    Z_phase_raw  = zeros(1,numVoltages);
    Z_phase_s    = zeros(1,numVoltages);
    Z_peak_raw   = zeros(1,numVoltages);
    Z_peak_s     = zeros(1,numVoltages);

    % Loop over voltages
    for k = 1:numVoltages
        V_fft   = fft(V(:,k));
        V_s_fft = fft(V_s(:,k));

        V_pos   = V_fft(1:halfN+1);
        V_s_pos = V_s_fft(1:halfN+1);

        V_amp   = abs(V_pos)/N;    V_amp(2:end-1)   = 2*V_amp(2:end-1);
        V_amp_s = abs(V_s_pos)/N;  V_amp_s(2:end-1) = 2*V_amp_s(2:end-1);

        % Store full amplitude spectra
        V_amp_raw(:,k)    = V_amp;
        V_amp_smooth(:,k) = V_amp_s;

        % Dominant frequency for this voltage
        [~, idx_v] = max(V_amp(2:end)); idx_v = idx_v + 1;
        volt_freq(k) = f(idx_v);

        % Impedance
        Z_raw   = V_pos ./ I_pos;
        Z_s     = V_s_pos ./ I_s_pos;

        Z_mag_raw(k)   = abs(Z_raw(idx)) * 1000;  % mΩ
        Z_mag_s(k)     = abs(Z_s(idx)) * 1000;

        Z_phase_raw(k) = rad2deg(angle(Z_raw(idx)));
        Z_phase_s(k)   = rad2deg(angle(Z_s(idx)));

        Z_peak_raw(k)  = Z_raw(idx);
        Z_peak_s(k)    = Z_s(idx);

        % Amplitude peak for summary
        amp_raw(k)    = max(V_amp);
        amp_smooth(k) = max(V_amp_s);
    end

    % Store results in struct
    results.freq_main     = freq_main;
    results.volt_freq     = volt_freq;
    results.amp_raw       = amp_raw;
    results.amp_smooth    = amp_smooth;
    results.V_amp_raw     = V_amp_raw;
    results.V_amp_smooth  = V_amp_smooth;
    results.I_amp_raw     = I_amp;
    results.I_amp_smooth  = I_amp_s;
    results.Z_mag_raw     = Z_mag_raw;
    results.Z_mag_s       = Z_mag_s;
    results.Z_phase_raw   = Z_phase_raw;
    results.Z_phase_s     = Z_phase_s;
    results.Z_peak_raw    = Z_peak_raw;
    results.Z_peak_s      = Z_peak_s;

    
    % --------------------------------------------
    % Printing Values for observing from terminal
    % --------------------------------------------
    fprintf('\n========== FFT / IMPEDANCE SUMMARY ==========\n');
    fprintf('Dominant Frequency (Current): %.3f Hz\n\n', freq_main);
    
    fprintf('--- CURRENT ---\n');
    fprintf('RAW     Amp (no DC): %.6f\n', I_amp(idx));
    fprintf('SMOOTH  Amp (no DC): %.6f\n\n', I_amp_s(idx));
    
    for k = 1:numVoltages
        fprintf('--- VOLTAGE %d ---\n', k);
        fprintf('RAW     Amp (no DC): %.6f\n', V_amp_raw(idx,k));
        fprintf('SMOOTH  Amp (no DC): %.6f\n', V_amp_smooth(idx,k));
        fprintf('Z_mag RAW     : %.6f mOhm\n', Z_mag_raw(k));
        fprintf('Z_mag SMOOTH  : %.6f mOhm\n', Z_mag_s(k));
        fprintf('Z_phase RAW   : %.2f deg\n', Z_phase_raw(k));
        fprintf('Z_phase SMOOTH: %.2f deg\n\n', Z_phase_s(k));
    end
end
