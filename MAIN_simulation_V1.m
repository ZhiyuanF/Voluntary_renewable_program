%% Renewable Credit Platform — Simulation Driver
% This script declares all assumptions and function handles required for the
% renewable credit market simulation, then executes the multi-period run.

clear; clc;

%% Basic assumption for common use
Q = linspace(0,10,20);

%% Renewable cost function: c_L(Q)

% CAPEX is fully paid upfront by the vertically integrated utility during capacity expansion,
% therefore it is not included here.

% Parameters
alphaL = 0.015*1400;      % baseline O&M cost [$M/GW·yr]
betaL  = 5;     % slight convexity for site quality depletion

% Cost function handle
cL = @(Q) alphaL.*Q + betaL.*Q.^2;

%% System operating cost: c_sys(Q) — simple linear + gentle convexity
% Assumptions:
% - Battery storage scales 1:1 with wind capacity (GW:GW).
% - No CRF; we lump CAPEX+O&M into an effective *annual* system cost per GW.
% - Use a linear term plus a small convex term to reflect harder integration at higher Q.

% Parameters (edit as needed)
alphaS = 0.08*120;    % effective annual system cost per GW [M$/GW·yr], 8% payment per year, 120 M$/GWh, 4 hour battery
betaS  = 1;    % gentle convexity [M$/GW^2·yr]

% Cost function handle
cSys = @(Q) alphaS.*Q + betaS.*Q.^2;

%% Read the pre-stored data and examine the grid-related functions

%load rt_price_simulation_results_20250804.mat
load rt_price_simulation_results_perfect_prediction_20250806.mat

d=5; % sample day number

% Set parameters
wind_ratio = 0.3;       % 30% wind penetration

load data.mat
wind_gen_ideal = max(max(load_real))*(wind_real)*wind_ratio; % wind generation
wind_gen_ideal=reshape(wind_gen_ideal',96,365)';
load_ideal = load_real; % load data
Full_capacity = max(max(load_real))/1000; % (GW) wind capacity that will lead to 100% peak load

for i = 1:365
    reshapedRow = reshape(wind_gen_ideal(i, :), 4, 24);
    wind_data(i, :) = mean(reshapedRow, 1);
    reshapedRow = reshape(load_ideal(i, :), 4, 24);
    load_data(i, :) = mean(reshapedRow, 1);
end

wind_sample_day = wind_data(d,:);
load_sample_day = load_data(d,:);

%% carbon intensity function: f(Q)
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
wind_storage_capacity = matched_ratios_sorted*Full_capacity;

%% Effective price function that wind received: pi(Q)

num_runs = 3;

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
wind_storage_capacity = matched_ratios_sorted*Full_capacity;

%% Effective renewable output function: h(Q)
% Goal: compute usable renewable electricity after curtailment (concave in Q).
% We use wind_fraction_series (wind_gen / load). If wind_fraction > 1, curtailment occurs.
% For each matched case (wind_ratio == storage_ratio), we compute the average
% GW-equivalent wind actually used on the sample day:
%   used_wind_hour = min(wind_fraction_hour, 1) * load_hour
% Then average over hours (and runs) to obtain h(Q) in GW.

matched_ratios = [];
h_values_GW    = [];

for i = 1:length(results)
    if abs(results(i).wind_ratio - results(i).storage_ratio) < 1e-6
        matched_ratios(end+1) = results(i).wind_ratio;

        % wind_fraction_series: [num_runs x 24], each entry = wind_gen / load
        wind_frac = results(i).wind_fraction_series;              % num_runs x 24
        [num_runs, ~] = size(wind_frac);

        % Broadcast load for runs
        load_mat = repmat(load_sample_day, num_runs, 1);          % num_runs x 24

        % Curtailment: only up to load can be served → min(fraction, 1)
        used_wind = min(wind_frac, 1) .* load_mat;               % num_runs x 24

        % Average over hours and runs → GW-equivalent average power used that day
        % (mean across hours of each run, then mean across runs)
        avg_used_per_run = mean(used_wind, 2);                    % num_runs x 1  (GW if load is GW)
        h_GW = mean(avg_used_per_run);                            % scalar (GW)

        h_values_GW(end+1) = h_GW/1000;
    end
end

% Sort for plotting
[matched_ratios_sorted, idx] = sort(matched_ratios);
h_sorted_GW = h_values_GW(idx);
wind_storage_capacity = matched_ratios_sorted * Full_capacity;    % Q in GW

%% plot input functions

figure;
plot(Q, cL(Q), 'LineWidth',2);
xlabel('Installed renewable capacity Q [GW]');
ylabel('Annual generation cost c_L(Q) [M$ / yr]');
title('Renewable Generation Cost (O&M-based, no CAPEX)');
grid on;

% Plot
figure;
plot(Q, cSys(Q), 'LineWidth', 2);
xlabel('Installed renewable capacity Q [GW]');
ylabel('Annual system cost c_{sys}(Q) [M$ / yr]');
title('System Cost (Battery 1:1 with Wind): Linear + Gentle Convexity');
grid on;

% Plot results
figure;
plot(wind_storage_capacity, avg_ci_sorted, '-o', 'LineWidth', 2);
xlabel('Wind Capacity (GW)');
ylabel('Avg Carbon Intensity (ton CO₂ / MWh)');
title('Carbon Intensity When Wind Ratio = Storage Ratio');
grid on;

% Plot
figure;
plot(wind_storage_capacity, wind_prices_sorted, '-o', 'LineWidth', 2);
xlabel('Wind Capacity (GW)');
ylabel('Weighted Avg Price Received by Wind ($/MWh)');
title('Effective Wind Price vs Wind-Storage Ratio');
grid on;

% Plot h(Q)
figure;
plot(wind_storage_capacity, h_sorted_GW, '-o', 'LineWidth', 2);
xlabel('Wind Capacity Q (GW)');
ylabel('Usable Renewable Output f(Q) (GW-average over day)');
title('Effective Renewable Output f(Q) vs Capacity (Curtailment-adjusted)');
grid on;
%}


%% Convert numerical data into function handles with linear interpolation
% Linear interpolation between points; linear extrapolation beyond range.

f   = @(Q) interp1(wind_storage_capacity, avg_ci_sorted, Q, 'linear', 'extrap');
piE = @(Q) interp1(wind_storage_capacity, wind_prices_sorted, Q, 'linear', 'extrap');
h   = @(Q) interp1(wind_storage_capacity, h_sorted_GW, Q, 'linear', 'extrap');

%% Baseline-demand function testing
%
% Single episode function test run
Q0      = 0.5;        % sample initial condition, deafult 0.5, ISONE 2.0 initial
C       = 10;      % market size (scaling factor for demand)
epsilon = 0.0045;      % demand sensitivity, default 0.0045, ISONE 0.004 match real situation
lambda  = 1000;       % install cost per GW [M$ / GW]
wind_cf = 0.35; % Full demand generation per unit ratio of wind

[p, q, gamma] = single_episode_baseline(Q0, epsilon, C, f, h, piE, cL, cSys, lambda, wind_cf);


% Demand and revenue vs price (dual y-axis + dual x-axis)
Q_plot = 2;                      % fixed capacity level
fQ     = f(Q_plot);

% Demand and revenue functions
L_fun = @(pp) C .* exp(-epsilon .* pp ./ fQ);
p_grid = linspace(0, 3*fQ/epsilon, 400);   % [M$/GW]
L_vals = L_fun(p_grid);
R_vals = p_grid .* L_vals;

% Optimal price (max revenue)
p_star = fQ / epsilon;
L_star = L_fun(p_star);
R_star = p_star * L_star;

figure;

% --- Primary axes (M$/GW) ---
yyaxis left
plot(p_grid, L_vals, 'b-', 'LineWidth', 2); grid on; hold on;
ylabel('Demand  L(p)');
ylim([0, 1.1*max(L_vals)]);

yyaxis right
plot(p_grid, R_vals, 'Color', [1 0 0 0.5], 'LineWidth', 2);
ylabel('Revenue  p·L(p)');
ylim([0, 1.1*max(R_vals)]);

xlabel('Price  p [M$ / GW]');
hold on;

% Highlight optimal point
plot(p_star, R_star, 'o', 'MarkerEdgeColor',[0.8 0 0], 'MarkerFaceColor',[1 0 0], 'MarkerSize',6);
xline(p_star, ':k', sprintf('  p^* = %.0f', p_star), ...
    'LabelVerticalAlignment','bottom', 'LabelHorizontalAlignment','left');

legend({'Demand L(p)','Revenue p·L(p)'}, 'Location','northeast');

% --- Secondary x-axis in $/MWh ---
ax1 = gca;
ax2 = axes('Position', get(ax1, 'Position'), ...
           'XAxisLocation','top', ...
           'YAxisLocation','right', ...
           'Color','none', ...
           'XColor','k', 'YColor','none');

% Conversion: 1 [M$/GW] = 10^6 $ / (8760 h * wind_cf * 1000 MW/GW)
% wind_cf = 0.35;
conv_factor = 1e6 / (8760 * wind_cf * 1000);  % → $/MWh per (M$/GW)
p_grid_MWh = p_grid * conv_factor;

set(ax2, 'XLim', get(ax1, 'XLim'));
x_ticks_MGW = get(ax1, 'XTick');
x_ticks_MWh = x_ticks_MGW * conv_factor;
set(ax2, 'XTick', x_ticks_MGW, 'XTickLabel', sprintfc('%.0f', x_ticks_MWh));
xlabel(ax2, 'Equivalent Price  p [$ / MWh]');

set(gcf, 'Position', get(gcf, 'Position') + [0 0 0 80]);   % give figure more vertical space
set(gca, 'LooseInset', max(get(gca,'TightInset'), 0.02));  % prevent cropping


%% Multi-period loop (baseline demand) using single_episode_baseline_update

% Stops when expansion is tiny: q_t < 0.01 GW or when max periods reached.

% --- Inputs you already defined ---
% Q0, C, epsilon, lambda, wind_cf, and function handles f, h, piE, cL, cSys
% single_episode_baseline_update must be on path or below this script.

tol_q     = 0.01;   % GW, stopping threshold
max_steps = 200;    % hard cap to avoid infinite loops

% Storage
Q_hist      = zeros(1, max_steps+1);
p_hist      = nan(1, max_steps);
q_hist      = nan(1, max_steps);
gamma_hist  = nan(1, max_steps);

% Init
Q_hist(1) = Q0;
t = 1;

while t <= max_steps
    [p_t, q_t, gamma_t] = single_episode_baseline( ...
        Q_hist(t), epsilon, C, f, h, piE, cL, cSys, lambda, wind_cf);

    % Record decisions
    p_hist(t)     = p_t;
    q_hist(t)     = q_t;
    gamma_hist(t) = gamma_t;

    % Update state
    if ~isfinite(q_t) || q_t < tol_q
        % Stop if infeasible or expansion is too small
        fprintf('[STOP] t=%d, q_t=%.4f < %.4f (GW). Ending simulation.\n', t, q_t, tol_q);
        break;
    end
    Q_hist(t+1) = Q_hist(t) + q_t;

    t = t + 1;
end

% Trim to actual length
T = t;  % last index used (episode count possibly including the stopping episode)
Q_hist = Q_hist(1:T);
p_hist = p_hist(1:T-1);
q_hist = q_hist(1:T-1);
gamma_hist = gamma_hist(1:T-1);

% Summarize
results_tbl = table((1:T-1)', Q_hist(1:T-1)', p_hist', q_hist', gamma_hist', Q_hist(2:T)', ...
    'VariableNames', {'t','Q_t_GW','p_$perMWh','q_t_GW','gamma_t','Q_tplus1_GW'});
disp(results_tbl);

%% Plot: Baseline simulation — compact single-column figure

font_name  = 'Times New Roman';
font_size  = 9;
line_width = 1.25;

main_color = [0.10 0.33 0.55];
alt_color  = [0.70 0.30 0.12];
bar_color  = [0.72 0.72 0.72];

% Use the existing simulation outputs without changing calculations.
n_plot = numel(p_hist);
if n_plot == 0
    error('No completed simulation periods are available for plotting.');
end

t_axis     = 1:n_plot;
Q_plot     = Q_hist(1:n_plot);
q_plot     = q_hist(1:n_plot);
e_plot     = arrayfun(f, Q_plot);    % f is emissions intensity in this script
gamma_plot = gamma_hist(1:n_plot);

% Preserve the original conversion to cents/kWh.
conv_factor = 1e6 / (8760 * wind_cf * 1000);
p_plot      = p_hist(1:n_plot) * conv_factor / 10;

% Sparse markers and common time ticks.
marker_step = max(1, ceil(n_plot/10));
marker_idx  = unique([1:marker_step:n_plot, n_plot]);
time_ticks  = unique(round(linspace(0, n_plot, 5)));

% Single-column width; short, wide panels.
fig2 = figure('Color', 'w', ...
    'Units', 'inches', ...
    'Position', [1 1 3.5 3.2], ...
    'PaperPositionMode', 'auto');

tl2 = tiledlayout(fig2, 3, 1, ...
    'TileSpacing', 'compact', ...
    'Padding', 'compact');

%% (a) Cumulative capacity and annual additions

ax21 = nexttile(tl2, 1);

% Plot additions first so that the capacity line remains prominent.
yyaxis(ax21, 'right');
h_add = bar(ax21, t_axis, q_plot, 0.8, ...
    'FaceColor', bar_color, ...
    'EdgeColor', 'none', ...
    'FaceAlpha', 0.45);
ylabel(ax21, {'q_t', '(GW/year)'});
ylim(ax21, [0, max(0.01, 1.15*max(q_plot))]);

hold(ax21, 'on');

yyaxis(ax21, 'left');
h_cap = plot(ax21, t_axis, Q_plot, '-o', ...
    'Color', main_color, ...
    'LineWidth', line_width, ...
    'MarkerSize', 3, ...
    'MarkerFaceColor', 'w', ...
    'MarkerIndices', marker_idx);
ylabel(ax21, {'Q_t', '(GW)'});
ylim(ax21, [0 8]);

title(ax21, '(a) Renewable expansion');

legend(ax21, [h_cap, h_add], {'Q_t', 'q_t'}, ...
    'Location', 'east', ...
    'NumColumns', 1, ...
    'Box', 'off', ...
    'FontName', font_name, ...
    'FontSize', font_size);

%% (b) Emissions intensity and optimal premium

ax22 = nexttile(tl2, 2);

yyaxis(ax22, 'left');
h_emis = plot(ax22, t_axis, e_plot, '-o', ...
    'Color', main_color, ...
    'LineWidth', line_width, ...
    'MarkerSize', 3, ...
    'MarkerFaceColor', 'w', ...
    'MarkerIndices', marker_idx);
ylabel(ax22, {'e(Q_t)', '(tCO_2/MWh)'});
ylim(ax22, [0 0.4]);
yticks(ax22, [0 0.2 0.4]);

hold(ax22, 'on');

yyaxis(ax22, 'right');
h_price = plot(ax22, t_axis, p_plot, '--', ...
    'Color', alt_color, ...
    'LineWidth', line_width);
ylabel(ax22, {'p_t', '(cents/kWh)'});
ylim(ax22, [0, max(0.01, 1.15*max(p_plot))]);

title(ax22, '(b) Emissions and premium');

legend(ax22, [h_emis, h_price], {'e(Q_t)', 'p_t'}, ...
    'Location', 'northeast', ...
    'NumColumns', 1, ...
    'Box', 'off', ...
    'FontName', font_name, ...
    'FontSize', font_size);

% Use the left axis for horizontal gridlines.
yyaxis(ax22, 'left');

%% (c) Revenue share transferred to generators

ax23 = nexttile(tl2, 3);

plot(ax23, t_axis, gamma_plot, '-o', ...
    'Color', main_color, ...
    'LineWidth', line_width, ...
    'MarkerSize', 3, ...
    'MarkerFaceColor', 'w', ...
    'MarkerIndices', marker_idx);

ylabel(ax23, '\gamma_t');
xlabel(ax23, 'Program year, t');
title(ax23, '(c) Revenue sharing');

ylim(ax23, [-0.03 1.03]);
yticks(ax23, [0 0.5 1]);

%% Common formatting

for ax = [ax21, ax22, ax23]
    set(ax, ...
        'FontName', font_name, ...
        'FontSize', font_size, ...
        'FontWeight', 'normal', ...
        'LabelFontSizeMultiplier', 1, ...
        'TitleFontSizeMultiplier', 1, ...
        'TitleFontWeight', 'normal', ...
        'TickLabelInterpreter', 'tex', ...
        'LineWidth', 0.65, ...
        'TickDir', 'out', ...
        'Box', 'off', ...
        'XColor', 'k', ...
        'XGrid', 'on', ...
        'YGrid', 'on', ...
        'GridAlpha', 0.10, ...
        'Layer', 'top');

    % Keep both vertical axes black; distinguish series by style and legend.
    for r = 1:numel(ax.YAxis)
        ax.YAxis(r).Color = 'k';
    end

    xlim(ax, [0 n_plot+1]);
    xticks(ax, time_ticks);
end

linkaxes([ax21, ax22, ax23], 'x');

% Show time labels only on the bottom panel.
set([ax21, ax22], 'XTickLabel', []);

set(findall(fig2, 'Type', 'text'), ...
    'FontName', font_name, ...
    'FontSize', font_size, ...
    'FontWeight', 'normal', ...
    'Interpreter', 'tex');

drawnow;

%}

%% Price points where demand is a given fraction of C
Q_plot = 5;                 % capacity level to reference
fQ     = f(Q_plot);         % emission intensity at Q_plot

fractions = [1/3, 0.10, 0.02];                    % θ values
names     = {'33.3% of C','10% of C','2% of C'};

% Conversion from M$/GW -> $/MWh
conv_factor = 1e6 / (8760 * wind_cf * 1000);      % $/MWh per (M$/GW)

fprintf('\nPrice points at Q=%.1f (epsilon=%.4g, wind_cf=%.2f):\n', Q_plot, epsilon, wind_cf);
for k = 1:numel(fractions)
    theta = fractions(k);
    p_MGW = (fQ / epsilon) * log(1/theta);        % M$/GW
    p_MWh = p_MGW * conv_factor;                  % $/MWh
    fprintf('  L = %-8s  ->  p = %8.2f M$/GW   (~ %8.2f $/MWh)\n', names{k}, p_MGW, p_MWh);
end


%% Heterogeneous demand testing
%{
Q0      = 0.5;        % sample initial condition
C       = 10;      % market size (scaling factor for demand)
epsilon = 0.0018;      % demand sensitivity
lambda  = 1400;       % install cost per GW [M$ / GW]
wind_cf = 0.35; % Full demand generation per unit ratio of wind

% Heterogeneous demand parameters (linear alpha, linear phi)
a = 0.1; 
b = 0.2; 
c = 0.7;     % a+b+c = 1

% --- Concave increasing α(q) >= 1 ---
% Form: alpha(q) = 1 + A * (1 - exp(-k*q))
% - Increases with q
% - Concave (alpha''(q) <= 0)
% - alpha(0)=1; alpha(∞)=1+A
A_alpha = 3;     % “headroom” above 1 at very large q (try 0.5–1.5)
k_alpha = 0.5;     % curvature (larger k -> faster early rise)
alpha_fun = @(q) 1 + A_alpha * (1 - exp(-k_alpha * max(q,0)));

% --- Convex increasing φ(Q) in [0, φ_max) ---
% Form: phi(Q) = φ_max * min(1, (Q / Qscale)^m),  with m>1 (convex on [0,Qscale])
% - Increases with Q
% - Convex (m>1) up to Qscale, then caps < 1
phi_max = 0.95;    % upper cap (<1 as required)
Qscale  = max(1, max(wind_storage_capacity));  % scale where φ approaches cap
m_phi   = 0.5;     % convexity exponent (>1) — try 2–3 for stronger convexity
phi_fun = @(Q) min(phi_max, phi_max * (max(Q,0)./Qscale).^m_phi);

% quick visual check vs the old linear versions
Qgrid = linspace(0, max(Qscale, 1.0), 200);
qgrid = Qgrid;  % same grid units (GW) for illustration

alpha_linear = 1 + qgrid;                       % your previous linear α
phi_linear   = min(0.999, Qgrid/10);               % your previous linear φ (capped)

figure;
subplot(1,2,1);
plot(qgrid, alpha_fun(qgrid), 'LineWidth',2); hold on;
plot(qgrid, alpha_linear, '--', 'LineWidth',1.5);
grid on; xlabel('q [GW]'); ylabel('\alpha(q)');
title('Concave \alpha(q) vs Linear');
legend({'concave','linear'});

subplot(1,2,2);
plot(Qgrid, phi_fun(Qgrid), 'LineWidth',2); hold on;
plot(Qgrid, phi_linear, '--', 'LineWidth',1.5);
grid on; xlabel('Q [GW]'); ylabel('\phi(Q)');
title('Convex \phi(Q) vs Linear (capped)');
legend({'convex (capped)','linear (capped)'});


[p, q, gamma, iters] = single_episode_hetero( ...
    Q0, epsilon, C, f, h, piE, cL, cSys, lambda, wind_cf, ...
    a, b, c, alpha_fun, phi_fun, 'tol_q',1e-3, 'max_iter',100, 'damp',0.6);

% Multi-period loop (heterogeneous demand)
% Requires: Q0, C, epsilon, lambda, wind_cf; f, h, piE, cL, cSys;
%           a,b,c, alpha_fun, phi_fun; and single_episode_hetero() above on path.

tol_q     = 0.01;   % GW stop threshold
max_steps = 200;

% Storage
Q_hist      = zeros(1, max_steps+1);
p_hist      = nan(1, max_steps);
q_hist      = nan(1, max_steps);
gamma_hist  = nan(1, max_steps);
iters_hist  = nan(1, max_steps);

% Revenue by segment (M$/yr)
rev_a_hist      = nan(1, max_steps);
rev_b_hist      = nan(1, max_steps);
rev_c_hist      = nan(1, max_steps);
rev_total_hist  = nan(1, max_steps);
energy_hist     = nan(1, max_steps);
op_credit_hist  = nan(1, max_steps);
gen_credit_hist = nan(1, max_steps);

% Init & iterate
Q_hist(1) = Q0;
t = 1;
while t <= max_steps
    [p_t, q_t, gamma_t, iters_t, rev_t] = single_episode_hetero( ...
        Q_hist(t), epsilon, C, f, h, piE, cL, cSys, lambda, wind_cf, ...
        a, b, c, alpha_fun, phi_fun, 'tol_q',1e-3, 'max_iter',100, 'damp',0.6);

    % Record decisions
    p_hist(t)     = p_t;
    q_hist(t)     = q_t;
    gamma_hist(t) = gamma_t;
    iters_hist(t) = iters_t;

    % Record revenues by segment
    rev_a_hist(t)      = rev_t.credit_a_M;
    rev_b_hist(t)      = rev_t.credit_b_M;
    rev_c_hist(t)      = rev_t.credit_c_M;
    rev_total_hist(t)  = rev_t.credit_total_M;
    energy_hist(t)     = rev_t.energy_M;
    op_credit_hist(t)  = rev_t.operator_credit_M;
    gen_credit_hist(t) = rev_t.generator_credit_M;

    % Stopping rule
    if ~isfinite(q_t) || q_t < tol_q
        fprintf('[STOP] t=%d, q_t=%.4f < %.4f (GW). Ending simulation.\n', t, q_t, tol_q);
        break;
    end

    % Update state
    Q_hist(t+1) = Q_hist(t) + q_t;
    t = t + 1;
end

% Trim to realized horizon
T = t;
Q_hist      = Q_hist(1:T);
p_hist      = p_hist(1:T-1);
q_hist      = q_hist(1:T-1);
gamma_hist  = gamma_hist(1:T-1);
iters_hist  = iters_hist(1:T-1);

rev_a_hist      = rev_a_hist(1:T-1);
rev_b_hist      = rev_b_hist(1:T-1);
rev_c_hist      = rev_c_hist(1:T-1);
rev_total_hist  = rev_total_hist(1:T-1);
energy_hist     = energy_hist(1:T-1);
op_credit_hist  = op_credit_hist(1:T-1);
gen_credit_hist = gen_credit_hist(1:T-1);

% Summary table
results_tbl = table((1:T-1)', Q_hist(1:T-1)', p_hist', q_hist', gamma_hist', Q_hist(2:T)', iters_hist', ...
    rev_a_hist', rev_b_hist', rev_c_hist', rev_total_hist', energy_hist', ...
    'VariableNames', {'t','Q_t_GW','p_$perMWh','q_t_GW','gamma_t','Q_tplus1_GW','iters', ...
                      'credit_a_M','credit_b_M','credit_c_M','credit_total_M','energy_M'});
disp(results_tbl);

% Plots (now 5 subplots; the last is stacked bar for segment credit revenue)
figure;
t_axis = 1:T-1;

subplot(5,1,1);
plot(t_axis, Q_hist(1:end-1), '-o','LineWidth',1.8); grid on;
ylabel('Q_t [GW]'); title('Multi-period Simulation (Heterogeneous Demand)');

subplot(5,1,2);
plot(t_axis, p_hist, '-o','LineWidth',1.8); grid on;
ylabel('p_t [$ / MWh]');

subplot(5,1,3);
plot(t_axis, q_hist, '-o','LineWidth',1.8); grid on;
ylabel('q_t [GW]');

subplot(5,1,4);
plot(t_axis, gamma_hist, '-o','LineWidth',1.8); grid on;
ylabel('\gamma_t'); xlabel('t');

subplot(5,1,5);
rev_sum = rev_a_hist + rev_b_hist + rev_c_hist;              % total per episode
rev_pct = 100 * [rev_a_hist'./rev_sum', rev_b_hist'./rev_sum', rev_c_hist'./rev_sum'];  % in %

bar(t_axis, rev_pct, 'stacked'); grid on;
ylabel('Credit Revenue Share [%]');
xlabel('t');
ylim([0 100]);
legend({'Aggressive (a)','Baseline (b)','Conservative (c)'}, 'Location','bestoutside');
title('Credit Revenue Composition by Segment (Percentage)');
%}


%% Single-episode simulation function: Baseline demand

function [p, q, gamma] = single_episode_baseline(Q, epsilon, C, f, h, piE, cL, cSys, lambda, wind_cf)
% SINGLE_EPISODE_BASELINE (graceful version: no hard errors)
% Baseline single-period decision given current capacity Q.
% Returns p, q, gamma. If infeasible, prints message and returns q=0.

    % --- Tolerances ---
    TOL = 1e-9;

    % Default outputs in case of early return
    p = NaN; q = 0; gamma = NaN;

    % --- Basic checks ---
    if ~(epsilon > 0) || ~(C > 0) || ~(lambda > 0)
        note('Invalid parameters: require epsilon>0, C>0, lambda>0.'); return;
    end

    fQ  = f(Q);
    hQ  = h(Q);
    piQ = piE(Q);

    if ~(isfinite(fQ) && isfinite(hQ) && isfinite(piQ))
        note('Non-finite f(Q)/h(Q)/pi(Q).'); return;
    end
    if fQ <= 0
        note('Infeasible: f(Q)<=0 makes demand ill-defined.'); return;
    end
    if hQ < 0
        note('Infeasible: h(Q)<0 is not allowed.'); return;
    end

    % --- Demand function (baseline) ---
    L = @(pp) C .* exp(-epsilon .* pp ./ fQ);

    % --- Step 1: price p ---
    p = fQ / epsilon;                 % unconstrained candidate
    if L(p) > hQ + TOL                % bind credit feasibility if needed
        if hQ <= 0
            note('Infeasible: h(Q)=0 but demand would be positive at any finite price.'); return;
        end
        p = (fQ / epsilon) * log(C / max(hQ, TOL));  % p^dagger
    end

    % Recompute demand at chosen price
    Lp = L(p);
    if Lp > hQ + 1e-6
        note(sprintf('Internal: L(p)=%.3f still exceeds h(Q)=%.3f after adjustment.', Lp, hQ)); return;
    end

    % --- Step 2: minimal gamma in [0,1] for generator viability ---
    % Need: c_L(Q) <= h(Q)*pi(Q) + gamma * p * L(p)
    denom    = p * Lp;  % credit revenue scale
    % Energy-market revenue (units: M$ / yr):
    %   hQ [GW] * wind_cf [-] * 8760 [h/yr] * 1000 [MW/GW] * piQ [$ / MWh] / 1e6 [$ -> M$]
    rhs_base = hQ * wind_cf * 8760 * 1000 * piQ / 1e6;
    lhs      = cL(Q);

    %diag(Q, fQ, hQ, piQ, p, Lp, denom, lhs, cSys(Q), rhs_base);

    if lhs <= rhs_base + TOL
        gamma = 0;   % already viable with energy-market revenue alone
    else
        if denom <= TOL
            note('Infeasible: p*L(p)=0 so no credit revenue; generators not viable.'); return;
        end
        gamma = (lhs - rhs_base) / denom;
        if gamma > 1 + TOL
            note(sprintf('Infeasible: required gamma=%.3f > 1 to keep generators viable.', gamma)); return;
        end
        gamma = min(max(gamma,0),1);
    end

    % --- Step 3: operator balance → compute q from remaining funds ---
    % c_sys(Q) + lambda*q <= (1 - gamma) * p * L(p)
    available = (1 - gamma) * denom - cSys(Q);
    if available < -TOL
        note(sprintf(['Operator revenue insufficient for system cost at chosen p, gamma.\n' ...
                      '  (1-γ)*pL=%.3f, cSys(Q)=%.3f, gap=%.3f'], ...
                      (1-gamma)*denom, cSys(Q), available));
        q = 0; return;
    end

    q = max(0, available / lambda);  % invest all remaining funds

    % --- Final sanity checks (graceful) ---
    if Lp > hQ + 1e-6
        warn(sprintf('Credit feasibility: L(p)=%.3f > h(Q)=%.3f. Setting q=0.', Lp, hQ));
        q = 0; return;
    end

    if cL(Q) - (rhs_base + gamma*denom) > 1e-6
        gap = cL(Q) - (rhs_base + gamma*denom);
        warn(sprintf('Generator viability gap=%.3f M$/yr. Setting q=0.', gap));
        q = 0; return;
    end

    if cSys(Q) + lambda*q - (1 - gamma)*denom > 1e-6
        gap = cSys(Q) + lambda*q - (1 - gamma)*denom;
        warn(sprintf('Operator balance gap=%.3f M$/yr. Setting q=0.', gap));
        q = 0; return;
    end

    % --- Print feasible episode summary ---
    fprintf('\n[Episode Results @ Q=%.2f GW]\n', Q);
    fprintf('  p       = %.3f M$/GW\n', p);
    fprintf('  p       = %.3f $/MWh\n', p*1000/(8760*wind_cf));
    fprintf('  L(p)    = %.3f\n', Lp);
    fprintf('  gamma   = %.3f\n', gamma);
    fprintf('  q       = %.3f GW (new capacity)\n', q);
    fprintf('  Revenue p*L(p) = %.3f\n\n', denom);
    
    %{
    % ---- local helpers ----
    function note(msg), fprintf('[NOTE] %s\n', msg); end
    function warn(msg), fprintf('Warning: %s\n', msg); end
    function diag(Q, fQ, hQ, piQ, p, Lp, denom, cLQ, cSysQ, rhs_base)
        fprintf('\n[DIAGNOSTIC @ Q = %.3f]\n', Q);
        fprintf('  f(Q)         = %.3f\n', fQ);
        fprintf('  h(Q)         = %.3f\n', hQ);
        fprintf('  pi(Q)        = %.3f\n', piQ);
        fprintf('  p            = %.3f\n', p);
        fprintf('  L(p)         = %.3f\n', Lp);
        fprintf('  denom p*L(p) = %.3f\n', denom);
        fprintf('  c_L(Q)       = %.3f M$/yr\n', cLQ);
        fprintf('  c_sys(Q)     = %.3f M$/yr\n', cSysQ);
        fprintf('  Energy rev   = %.3f M$/yr\n\n', rhs_base);
    end
    %}
end



%% Single-episode simulation function: Heterogeneous demand

function [p, q, gamma, iters] = single_episode_hetero_test( ...
    Q, epsilon, C, f, h, piE, cL, cSys, lambda, wind_cf, ...
    a, b, c, alpha_fun, phi_fun, varargin)
% SINGLE_EPISODE_HETERO  One-period decision with heterogeneous demand.
% Iterates on q because L depends on q via alpha(q). Graceful returns (no errors).

    % Options
    p = inputParser;
    addParameter(p,'tol_q',1e-3);     % GW convergence for q
    addParameter(p,'max_iter',100);
    addParameter(p,'damp',0.6);       % damping in (0,1]
    parse(p,varargin{:});
    tol_q   = p.Results.tol_q;
    Kmax    = p.Results.max_iter;
    damp    = p.Results.damp;

    TOL = 1e-9;
    q = 0;                      % initial guess
    gamma = NaN;
    iters = 0;

    fQ  = f(Q);
    hQ  = h(Q);
    piQ = piE(Q);
    if ~(epsilon>0 && C>0 && lambda>0 && fQ>0 && hQ>=0 && isfinite(fQ+hQ+piQ))
        fprintf('[NOTE] Invalid inputs or f/h/pi at Q=%.3f.\n', Q);
        q = 0; p = NaN; gamma = NaN; return;
    end

    for k = 1:Kmax
        iters = k;

        % Segment weight with current q
        S = a*alpha_fun(q) + b + c*phi_fun(Q);   % >=0
        S = max(S, 0);                           % safety

        % Demand function with heterogeneity
        % L(p; q, Q) = C * exp(-eps * p / fQ) * S
        L = @(pp) C .* exp(-epsilon .* pp ./ fQ) .* S;

        % Price: unconstrained, then possibly bind L<=h(Q)
        p = fQ / epsilon;
        if L(p) > hQ + TOL
            if hQ <= 0
                fprintf('[NOTE] h(Q)=0 at Q=%.3f. No feasible demand. q=0.\n', Q);
                q = 0; gamma = 0; p = (fQ/epsilon)*log(max(C*S,TOL)/max(hQ,TOL)); return;
            end
            p = (fQ / epsilon) * log( max(C*S, TOL) / max(hQ, TOL) );  % p^dagger with S(q,Q)
        end

        % Revenues & gamma
        Lp      = L(p);
        denom   = p * Lp;                                           % credit revenue scale
        rhsBase = hQ * wind_cf * 8760 * 1000 * piQ / 1e6;          % M$/yr (energy revenue)
        lhs     = cL(Q);                                            % M$/yr

        if lhs <= rhsBase + TOL
            gamma_tmp = 0;
        else
            if denom <= TOL
                fprintf('[NOTE] p*L=0 while generators need credits. q=0.\n');
                q = 0; gamma = 0; return;
            end
            gamma_tmp = (lhs - rhsBase) / denom;
            if gamma_tmp > 1 + TOL
                fprintf('[NOTE] Required gamma=%.3f>1; infeasible credits. q=0.\n', gamma_tmp);
                q = 0; gamma = 1; return;
            end
            gamma_tmp = min(max(gamma_tmp,0),1);
        end

        % Operator balance → q_new
        available = (1 - gamma_tmp) * denom - cSys(Q);
        if available < -TOL
            % Not enough operator revenue even for system cost: no expansion
            fprintf('[NOTE] (1-γ)pL=%.3f < cSys=%.3f. Set q=0 at Q=%.3f.\n', ...
                    (1-gamma_tmp)*denom, cSys(Q), Q);
            q_new = 0;
        else
            q_new = max(0, available / lambda);
        end

        % Convergence / damping
        dq = q_new - q;
        q  = q + damp * dq;            % damped update
        gamma = gamma_tmp;             % keep gamma from this iteration

        % Stop if small change or small magnitude
        if ~isfinite(q) || q < tol_q || abs(dq) < tol_q
            q = max(0, q);             % sanitize
            break;
        end
    end

    % Final feasibility warnings (soft)
    % Recompute with final q for reporting
    S = a*alpha_fun(q) + b + c*phi_fun(Q);
    L = @(pp) C .* exp(-epsilon .* pp ./ fQ) .* S;
    Lp = L(p); denom = p*Lp; rhsBase = hQ*wind_cf*8760*1000*piQ/1e6;

    if Lp > hQ + 1e-6
        fprintf('Warning: L(p)=%.3f > h(Q)=%.3f. Forcing q=0.\n', Lp, hQ); q=0;
    end
    if cL(Q) - (rhsBase + gamma*denom) > 1e-6
        gap = cL(Q) - (rhsBase + gamma*denom);
        fprintf('Warning: Gen viability gap=%.3f M$/yr. Forcing q=0.\n', gap); q=0;
    end
    if cSys(Q) + lambda*q - (1 - gamma)*denom > 1e-6
        gap = cSys(Q) + lambda*q - (1 - gamma)*denom;
        fprintf('Warning: Operator balance gap=%.3f M$/yr. Forcing q=0.\n', gap); q=0;
    end

    % Optional: episode summary
    fprintf('\n[Hetero Episode @ Q=%.2f] iters=%d\n', Q, iters);
    fprintf('  p = %.3f $/MWh,  L(p) = %.3f,  γ = %.3f,  q = %.3f GW\n', p, Lp, gamma, q);
end


function [p, q, gamma, iters, rev] = single_episode_hetero( ...
    Q, epsilon, C, f, h, piE, cL, cSys, lambda, wind_cf, ...
    a, b, c, alpha_fun, phi_fun, varargin)
% SINGLE_EPISODE_HETERO  One-period decision with heterogeneous demand.
% Iterates on q (because L depends on q via alpha(q)). Graceful returns (no errors).
% Returns rev struct with revenue by segment (M$/yr).

    % --- Options ---
    ip = inputParser;
    addParameter(ip,'tol_q',1e-3);     % GW convergence for q
    addParameter(ip,'max_iter',100);
    addParameter(ip,'damp',0.6);       % damping in (0,1]
    parse(ip,varargin{:});
    tol_q   = ip.Results.tol_q;
    Kmax    = ip.Results.max_iter;
    damp    = ip.Results.damp;

    TOL = 1e-9;

    % Defaults
    p = NaN; q = 0; gamma = NaN; iters = 0;
    rev = struct('L_total',NaN,'L_a',NaN,'L_b',NaN,'L_c',NaN, ...
                 'credit_total_M',NaN,'credit_a_M',NaN,'credit_b_M',NaN,'credit_c_M',NaN, ...
                 'energy_M',NaN,'operator_credit_M',NaN,'generator_credit_M',NaN, ...
                 'S',NaN,'alpha_q',NaN,'phi_Q',NaN);

    % Basic values
    fQ  = f(Q);  hQ  = h(Q);  piQ = piE(Q);
    if ~(epsilon>0 && C>0 && lambda>0 && isfinite(fQ+hQ+piQ) && fQ>0 && hQ>=0)
        fprintf('[NOTE] Invalid inputs at Q=%.3f.\n', Q); return;
    end

    % Iterate on q
    q = 0;  % initial guess
    for k = 1:Kmax
        iters = k;

        alpha_q = alpha_fun(q);
        phi_Q   = phi_fun(Q);
        S = a*alpha_q + b + c*phi_Q;  S = max(S,0);

        % Demand L(p; q, Q) = C * exp(-ε p / fQ) * S
        Lfun = @(pp) C .* exp(-epsilon .* pp ./ fQ) .* S;

        % Price: unconstrained then quantity-binding if needed
        p = fQ / epsilon;
        if Lfun(p) > hQ + TOL
            if hQ <= 0
                fprintf('[NOTE] h(Q)=0 at Q=%.3f. Setting q=0.\n', Q);
                gamma = 0; q = 0;
                break;
            end
            p = (fQ/epsilon) * log( max(C*S,TOL) / max(hQ,TOL) );
        end

        % Revenues and γ
        Lp      = Lfun(p);
        denom   = p * Lp;                                           % [$/MWh * (MWh-equiv unitless)] but we keep consistency with credit logic
        energyM = hQ * wind_cf * 8760 * 1000 * piQ / 1e6;          % M$/yr
        lhsM    = cL(Q);                                            % M$/yr

        if lhsM <= energyM + TOL
            gamma_tmp = 0;
        else
            if denom <= TOL
                fprintf('[NOTE] p*L=0 while generators need credits. q=0.\n');
                gamma = 0; q = 0; break;
            end
            gamma_tmp = (lhsM - energyM) / denom;
            if gamma_tmp > 1 + TOL
                fprintf('[NOTE] Required gamma=%.3f>1; infeasible credits. q=0.\n', gamma_tmp);
                gamma = 1; q = 0; break;
            end
            gamma_tmp = min(max(gamma_tmp,0),1);
        end

        % Operator balance → q_new
        availM = (1 - gamma_tmp) * denom - cSys(Q);                % M$/yr
        if availM < -TOL
            q_new = 0;
        else
            q_new = max(0, availM / lambda);                        % GW
        end

        % Damped update & stop test
        dq = q_new - q;
        q  = q + damp * dq;
        gamma = gamma_tmp;
        if ~isfinite(q) || q < tol_q || abs(dq) < tol_q
            q = max(0, q);
            break;
        end
    end

    % Compose segment breakdown (using *final* q and p)
    alpha_q = alpha_fun(q);  phi_Q = phi_fun(Q);  S = a*alpha_q + b + c*phi_Q;
    base    = C .* exp(-epsilon .* p ./ fQ);      % common factor
    L_a = a * alpha_q * base;
    L_b = b * base;
    L_c = c * phi_Q * base;
    L_total = L_a + L_b + L_c;

    % Credit revenues by segment (M$/yr): p[$/MWh]*L[unitless]*? => keep consistent with your previous usage:
    % We treat p*L as "credit revenue scale" in M$/yr units consistent with earlier model (no extra hour factor).
    credit_total_M = p * L_total;
    credit_a_M     = p * L_a;
    credit_b_M     = p * L_b;
    credit_c_M     = p * L_c;

    energyM = hQ * wind_cf * 8760 * 1000 * piQ / 1e6;  % M$/yr
    operator_credit_M  = (1 - gamma) * credit_total_M;
    generator_credit_M = gamma * credit_total_M;

    rev = struct('L_total',L_total,'L_a',L_a,'L_b',L_b,'L_c',L_c, ...
                 'credit_total_M',credit_total_M,'credit_a_M',credit_a_M, ...
                 'credit_b_M',credit_b_M,'credit_c_M',credit_c_M, ...
                 'energy_M',energyM,'operator_credit_M',operator_credit_M, ...
                 'generator_credit_M',generator_credit_M, ...
                 'S',S,'alpha_q',alpha_q,'phi_Q',phi_Q);
end

