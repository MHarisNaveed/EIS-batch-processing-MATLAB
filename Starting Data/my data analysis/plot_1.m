%% Dynamic Scaling with Dual Y-Axes
% Save this as dynamic_plot.m

% 1. Extract data from your table (referenced from image_864e8c.png)
t = testlissajou1.Time;
v_orig = testlissajou1.Voltage;
i = testlissajou1.Current;

% 2. Setup Figure
fig = figure('Name', 'Interactive Phase Analysis', 'Color', 'w');
ax = axes('Parent', fig, 'Position', [0.12 0.3 0.75 0.6]); 

% 3. Create Dual Axis Plot
yyaxis(ax, 'right')
plot(t, i, 'Color', [0.85 0.325 0.098], 'LineWidth', 1);
ylabel('Current (A)');
ylim([min(i)*1.2, max(i)*1.2]);

yyaxis(ax, 'left')
v_plot = plot(t, v_orig, 'b', 'LineWidth', 1.5);
ylabel('Scaled Voltage (V)');
title('Adjust Slider to Align Peaks');
grid on;

% 4. Add the Slider
% We use an anonymous function for the callback to avoid the "function" error
hSlider = uicontrol('Style', 'slider', ...
    'Min', 0.1, 'Max', 1000, 'Value', 1, ...
    'Position', [150 50 300 20], ...
    'Callback', @(src, event) updateVoltage(src, v_orig, v_plot, ax));

% Add a label to see the multiplier
hText = uicontrol('Style', 'text', ...
    'Position', [150 75 300 20], ...
    'String', 'Voltage Multiplier: 1x');

% 5. The "Logic" (Nested Function)
function updateVoltage(src, v_data, p_handle, axis_handle)
    multiplier = get(src, 'Value');
    new_v = v_data * multiplier;
    
    % Update the line data
    set(p_handle, 'YData', new_v);
    
    % Update the axis limits so it doesn't jump around
    yyaxis(axis_handle, 'left');
    ylim(axis_handle, [min(new_v)*1.2, max(new_v)*1.2]);
    
    % Update the text label
    hText.String = sprintf('Voltage Multiplier: %.1fx', multiplier);
end