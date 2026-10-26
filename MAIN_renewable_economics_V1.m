% Main power market simulation script
% this script does NOT simulate the renewable contracts, but using power
% market simulation to derive the key grid-related exogenous assumptions

clear; clc;

addpath(genpath('B:\Ph.D_research\Renewable_economics\simulation\Storage_Pricing_for_Social_Welfare_Maximization-main\code\YALMIP-develop'));  % YALMIP
addpath('C:\gurobi1001\win64\matlab');  % Gurobi
gurobi_setup

%% Test run single case and plot

% Set parameters
wind_ratio = 0.3;       % 30% wind penetration
storage_ratio = 0.2;    % 20% of peak load as storage power capacity
price_sigma = 30;       % Price volatility used in value function
forwecast_error = 0;

% Call your new simulation function
[price_series, dispatch_info] = run_rt_price_simple(wind_ratio, storage_ratio, price_sigma, 5, forwecast_error);

%
% Plot results
mean_price = mean(price_series, 1);
std_price = std(price_series, 1);

figure;
plot(1:24, mean_price, 'LineWidth', 2);
hold on;
fill([1:24, fliplr(1:24)], ...
     [mean_price + std_price, fliplr(mean_price - std_price)], ...
     [0.8 0.8 1], 'EdgeColor', 'none', 'FaceAlpha', 0.4);
xlabel('Hour of Day');
ylabel('Real-Time Price ($/MWh)');
title('Real-Time Price with Storage Participation');
grid on;
legend('Mean Price', '±1 Std Dev');

% Optional: print key summary
fprintf('Avg price over 24 hrs: %.2f $/MWh\n', mean(mean_price));
fprintf('Peak price: %.2f $/MWh\n', max(mean_price));
fprintf('Min price: %.2f $/MWh\n', min(mean_price));


carbon_intensity_series = dispatch_info.carbon_intensity_series;

mean_carbon = mean(carbon_intensity_series, 1);
std_carbon = std(carbon_intensity_series, 1);

figure;
plot(1:24, mean_carbon, 'LineWidth', 2);
hold on;
fill([1:24, fliplr(1:24)], ...
     [mean_carbon + std_carbon, fliplr(mean_carbon - std_carbon)], ...
     [1 0.8 0.8], 'EdgeColor', 'none', 'FaceAlpha', 0.4);
xlabel('Hour of Day');
ylabel('Carbon Intensity (ton CO₂ / MWh)');
title('Carbon Intensity of Real-Time Dispatch');
grid on;
legend('Mean Carbon Intensity', '±1 Std Dev');

fprintf('Avg carbon intensity: %.2f ton/MWh\n', mean(mean_carbon));
fprintf('Max carbon intensity: %.2f ton/MWh\n', max(mean_carbon));
fprintf('Min carbon intensity: %.2f ton/MWh\n', min(mean_carbon));


wind_fraction_series = dispatch_info.wind_fraction_series;

mean_wind = mean(wind_fraction_series, 1);
std_wind = std(wind_fraction_series, 1);

figure;
plot(1:24, mean_wind * 100, 'LineWidth', 2); % convert to %
hold on;
fill([1:24, fliplr(1:24)], ...
     [(mean_wind + std_wind)*100, fliplr((mean_wind - std_wind)*100)], ...
     [0.8 1 0.8], 'EdgeColor', 'none', 'FaceAlpha', 0.4);
xlabel('Hour of Day');
ylabel('Wind Generation Share (%)');
title('Wind Penetration in Real-Time Dispatch');
grid on;
legend('Mean Wind Share', '±1 Std Dev');

fprintf('Avg wind share: %.1f%%\n', mean(mean_wind) * 100);
fprintf('Max wind share: %.1f%%\n', max(mean_wind) * 100);
fprintf('Min wind share: %.1f%%\n', min(mean_wind) * 100);



%% Run number of cases 
%{
% Set constants
price_sigma = 30;
num_runs = 5;

% Define wind and storage combinations
wind_values = 0.1:0.1:1.0;        % 10 values
storage_values = 0.1:0.1:1.0;       % 10 values
[W, S] = ndgrid(wind_values, storage_values);
combos = [W(:), S(:)];            % 100 x 2

% Preallocate results
num_cases = size(combos, 1);
results(num_cases) = struct( ...
    'wind_ratio', [], ...
    'storage_ratio', [], ...
    'price_series', [], ...
    'carbon_intensity_series', [], ...
    'wind_fraction_series', []);

% Run simulation
for i = 1:num_cases
    wind_ratio = combos(i, 1);
    storage_ratio = combos(i, 2);

    [price_series, dispatch_info] = run_rt_price_simple(wind_ratio, storage_ratio, price_sigma, num_runs);

    % Save results
    results(i).wind_ratio = wind_ratio;
    results(i).storage_ratio = storage_ratio;
    results(i).price_series = price_series;
    results(i).carbon_intensity_series = dispatch_info.carbon_intensity_series;
    results(i).wind_fraction_series = dispatch_info.wind_fraction_series;
end
%}

% Set constants
price_sigma = 0;
forwecast_error = 0;
num_runs = 3;

% Define wind and storage values (diagonal only)
values = 0.1:0.1:1.0;  % 10 values where wind == storage
num_cases = numel(values);

% Preallocate results
results(num_cases) = struct( ...
    'wind_ratio', [], ...
    'storage_ratio', [], ...
    'price_series', [], ...
    'carbon_intensity_series', [], ...
    'wind_fraction_series', []);

% Run simulation only for diagonal combinations
for i = 1:num_cases
    wind_ratio = values(i);
    storage_ratio = values(i);  % same as wind_ratio

    [price_series, dispatch_info] = run_rt_price_simple(wind_ratio, storage_ratio, price_sigma, num_runs, forwecast_error);

    % Save results
    results(i).wind_ratio = wind_ratio;
    results(i).storage_ratio = storage_ratio;
    results(i).price_series = price_series;
    results(i).carbon_intensity_series = dispatch_info.carbon_intensity_series;
    results(i).wind_fraction_series = dispatch_info.wind_fraction_series;
end


%% Read the pre-stored data and examine the functions

%load rt_price_simulation_results_20250804.mat
load rt_price_simulation_results_perfect_prediction_20250806.mat

d=5; % sample day number

load data.mat
wind_gen_ideal = max(max(load_real))*(wind_real)*wind_ratio; % wind generation
wind_gen_ideal=reshape(wind_gen_ideal',96,365)';
load_ideal = load_real; % load data

for i = 1:365
    reshapedRow = reshape(wind_gen_ideal(i, :), 4, 24);
    wind_data(i, :) = mean(reshapedRow, 1);
    reshapedRow = reshape(load_ideal(i, :), 4, 24);
    load_data(i, :) = mean(reshapedRow, 1);
end

wind_sample_day = wind_data(d,:);
load_sample_day = load_data(d,:);

%% Fixed storage ratio
% Target storage ratio
target_storage = 0.5;

% Initialize arrays to store results
wind_ratios = [];
avg_carbon_intensities = [];

% Loop through results
for i = 1:length(results)
    if abs(results(i).storage_ratio - target_storage) < 1e-6  % Use tolerance for float comparison
        wind_ratios(end+1) = results(i).wind_ratio;
        
        % Compute scalar average over the 5x24 matrix
        avg_ci = mean(results(i).carbon_intensity_series(:));
        avg_carbon_intensities(end+1) = avg_ci;
    end
end

% Sort results for plotting
[wind_ratios_sorted, idx] = sort(wind_ratios);
avg_ci_sorted = avg_carbon_intensities(idx);

% Plot
figure;
plot(wind_ratios_sorted, avg_ci_sorted, '-o', 'LineWidth', 2);
xlabel('Wind Ratio');
ylabel('Avg Carbon Intensity (ton CO₂ / MWh)');
title(sprintf('Carbon Intensity vs Wind Ratio (Storage Ratio = %.1f)', target_storage));
grid on;

%% sample day wind and load plot

figure;

% First y-axis: load
yyaxis left;
plot(1:24, load_sample_day, '-o', 'LineWidth', 2);
ylabel('Load (MW)');
ylim([0, max(load_sample_day) * 1.1]);  % Adjust as needed
ax = gca;
ax.YColor = 'b';

% Second y-axis: wind generation
yyaxis right;
plot(1:24, wind_sample_day, '-s', 'LineWidth', 2);
ylabel('Wind Generation (MW)');
ylim([0, max(wind_sample_day) * 1.1]);  % Adjust as needed
ax.YColor = 'g';

xlabel('Hour of Day');
title(sprintf('Load and Wind Generation on Day %d', d));
grid on;
legend('Load', 'Wind Generation', 'Location', 'best');



%% carbon intensity, Equivalent storage-wind ratio

% Initialize arrays to store results
matched_ratios = [];
avg_carbon_intensities = [];

% Loop through the results struct
for i = 1:length(results)
    if abs(results(i).wind_ratio - results(i).storage_ratio) < 1e-6  % Float comparison with tolerance
        matched_ratios(end+1) = results(i).wind_ratio;
        
        % Compute scalar average of 5x24 matrix
        avg_ci = mean(results(i).carbon_intensity_series(:));
        avg_carbon_intensities(end+1) = avg_ci;
    end
end

% Sort for plotting
[matched_ratios_sorted, idx] = sort(matched_ratios);
avg_ci_sorted = avg_carbon_intensities(idx);

% Plot results
figure;
plot(matched_ratios_sorted, avg_ci_sorted, '-o', 'LineWidth', 2);
xlabel('Wind Ratio = Storage Ratio');
ylabel('Avg Carbon Intensity (ton CO₂ / MWh)');
title('Carbon Intensity When Wind Ratio = Storage Ratio');
grid on;

%% Effective price that wind receives

wind_prices = [];  % Store final values per matched case
matched_ratios = [];

for i = 1:length(results)
    if abs(results(i).wind_ratio - results(i).storage_ratio) < 1e-6  % Equal ratio check
        matched_ratios(end+1) = results(i).wind_ratio;

        % Get price and wind fraction (num_runsx24)
        price = results(i).price_series;
        wind_frac = results(i).wind_fraction_series;

        % Get actual dispatched wind: wind_frac * load (broadcasted)
        % Result: 5x24 matrix
        wind_used = wind_frac .* repmat(load_sample_day, num_runs, 1);

        % Element-wise revenue = price .* wind_used
        revenue = price .* wind_used;

        % Sum over all time and scenarios
        total_revenue = sum(revenue(:));
        total_wind = sum(wind_used(:));

        % Avoid division by zero
        if total_wind > 0
            avg_wind_price = total_revenue / total_wind;
        else
            avg_wind_price = NaN;  % or 0
        end

        wind_prices(end+1) = avg_wind_price;
    end
end

% Sort for plotting
[matched_ratios_sorted, idx] = sort(matched_ratios);
wind_prices_sorted = wind_prices(idx);

% Plot
figure;
plot(matched_ratios_sorted, wind_prices_sorted, '-o', 'LineWidth', 2);
xlabel('Wind = Storage Ratio');
ylabel('Weighted Avg Price Received by Wind ($/MWh)');
title('Effective Wind Price vs Wind-Storage Ratio');
grid on;

% Set target storage ratio
target_storage = 0.2;

% Initialize result storage
wind_ratios = [];
wind_prices = [];

for i = 1:length(results)
    if abs(results(i).storage_ratio - target_storage) < 1e-6
        wind_ratios(end+1) = results(i).wind_ratio;

        price = results(i).price_series;                % num_runs×24
        wind_frac = results(i).wind_fraction_series;    % num_runs×24

        % Actual wind used = wind fraction * load
        wind_used = wind_frac .* repmat(load_sample_day, num_runs, 1);  % num_runs×24

        revenue = price .* wind_used;
        total_revenue = sum(revenue(:));
        total_wind = sum(wind_used(:));

        % Avoid division by zero
        if total_wind > 0
            avg_price = total_revenue / total_wind;
        else
            avg_price = NaN;
        end

        wind_prices(end+1) = avg_price;
    end
end

% Sort for plotting
[wind_ratios_sorted, idx] = sort(wind_ratios);
wind_prices_sorted = wind_prices(idx);

% Plot
figure;
plot(wind_ratios_sorted, wind_prices_sorted, '-o', 'LineWidth', 2);
xlabel('Wind Ratio');
ylabel('Weighted Avg Price Received by Wind ($/MWh)');
title(sprintf('Effective Wind Price (Storage Ratio = %.1f)', target_storage));
grid on;

