
%% Renewable Credit Platform — Sensitivity Analyses
% Run this script to calculate and plot:
% (1) Financial feasibility boundary and terminal emissions vs epsilon.
% (2) Minimum monotone-reachability slope vs epsilon and investment cost k.
% Same calibrated ISO-NE data, cost functions and financial accounting as baseline.
% Figures are displayed only; no files are exported.

clear; clc;

%% Renewable operating cost: cL(Q) [M$/yr]
alphaL = 0.015*1400;
betaL  = 5;
cL = @(Q) alphaL.*Q + betaL.*Q.^2;

%% System integration cost: cSys(Q) [M$/yr]
alphaS = 0.08*120;
betaS  = 1;
cSys = @(Q) alphaS.*Q + betaS.*Q.^2;

%% Load pre-stored ISO-NE dispatch and price data
load rt_price_simulation_results_perfect_prediction_20250806.mat
load data.mat

d = 5;  % same sample day as in the baseline simulation
load_sample_day = mean(reshape(load_real(d,:), 4, 24), 1);
Full_capacity  = max(load_real(:))/1000;  % GW

%% Recover grid emissions, wholesale prices, and usable renewable output
matched_idx = find(arrayfun(@(s) abs(s.wind_ratio-s.storage_ratio)<1e-6, results));
num_cases = numel(matched_idx);
if num_cases < 2
    error('At least two wind_ratio == storage_ratio scenarios are required.');
end

wind_storage_capacity = zeros(1,num_cases);
avg_ci               = zeros(1,num_cases);
wind_prices          = zeros(1,num_cases);
h_values_GW          = zeros(1,num_cases);

for i = 1:num_cases
    run_i = results(matched_idx(i));
    wind_storage_capacity(i) = run_i.wind_ratio * Full_capacity;
    avg_ci(i) = mean(run_i.carbon_intensity_series(:));

    wind_frac = run_i.wind_fraction_series;
    price = run_i.price_series;
    num_runs = size(wind_frac,1);
    load_mat = repmat(load_sample_day, num_runs, 1);

    % Weighted wind price: same as the original driver.
    wind_used = wind_frac .* load_mat;
    total_wind = sum(wind_used(:));
    if total_wind > 0
        revenue = price .* wind_used;
        wind_prices(i) = sum(revenue(:))/total_wind;
    else
        wind_prices(i) = NaN;
    end

    % Curtailment-adjusted usable renewable output [GW].
    used_wind = min(wind_frac,1) .* load_mat;
    h_values_GW(i) = mean(used_wind(:))/1000;
end

[wind_storage_capacity, idx] = sort(wind_storage_capacity);
avg_ci      = avg_ci(idx);
wind_prices = wind_prices(idx);
h_values_GW = h_values_GW(idx);
if any(diff(wind_storage_capacity)<=0)
    error('Duplicate calibrated capacity values: check ISO-NE scenario data.');
end

e_fun  = @(Q) interp1(wind_storage_capacity, avg_ci, Q, 'linear');
pi_fun = @(Q) interp1(wind_storage_capacity, wind_prices, Q, 'linear');
h_fun  = @(Q) interp1(wind_storage_capacity, h_values_GW, Q, 'linear');

%% Baseline assumptions and sensitivity ranges
Q0               = 0.5;       % initial renewable capacity [GW]
C                = 10;        % potential VRP market size [GW-equivalent]
epsilon_baseline = 0.0045;    % baseline demand sensitivity
lambda           = 1000;      % baseline investment cost [M$/GW]
wind_cf          = 0.35;      % wind capacity factor

epsilon_values = 0.002:0.00025:0.020;

%% Set the calibrated capacity interval
Q_min   = min(wind_storage_capacity);
Q_max   = max(wind_storage_capacity);
Q_start = max(Q0, Q_min);

fprintf('Calibrated capacity range: %.2f to %.2f GW\n', Q_min, Q_max);
fprintf('Sensitivity analysis starts at Q = %.2f GW\n', Q_start);

Q_grid = linspace(Q_start, Q_max, 4001);
e_grid  = e_fun(Q_grid);
h_grid  = h_fun(Q_grid);
pi_grid = pi_fun(Q_grid);

valid_grid = isfinite(e_grid) & isfinite(h_grid) & isfinite(pi_grid) ...
             & e_grid>0 & h_grid>0;
if ~all(valid_grid)
    first_bad = find(~valid_grid,1,'first');
    if first_bad <= 2
        error('Invalid grid functions near the calibrated starting capacity.');
    end
    warning('Truncating before nonpositive/undefined grid values.');
    Q_grid = Q_grid(1:first_bad-1);
    e_grid = e_grid(1:first_bad-1);
    h_grid = h_grid(1:first_bad-1);
    pi_grid = pi_grid(1:first_bad-1);
end

%% Part I. Financial feasibility boundary vs demand sensitivity
% Separated-account financial requirement:
%   cSys(Q) + max(cL(Q) - wholesale revenue(Q), 0).

x_star = max(1, log(C./h_grid));
R_scale = e_grid .* x_star .* (C.*exp(-x_star));  % R*(Q,eps)=R_scale/eps
annual_factor = wind_cf*8760*1000/1e6;
wholesale_revenue = h_grid .* pi_grid * annual_factor;
required_revenue = cSys(Q_grid) + max(cL(Q_grid)-wholesale_revenue, 0);

Q_terminal = nan(size(epsilon_values));
e_terminal = nan(size(epsilon_values));
status = repmat({'Not evaluated'},size(epsilon_values));

for j = 1:numel(epsilon_values)
    epsilon = epsilon_values(j);
    gap = R_scale./epsilon - required_revenue;

    if gap(1)<0
        status{j} = 'Infeasible at starting capacity';
        continue;
    end

    idx_cross = find(gap<=0,1,'first');
    if isempty(idx_cross)
        status{j} = 'Boundary beyond calibrated range';
        continue;
    end

    if idx_cross==1
        Qstar = Q_grid(1);
    else
        balance = @(Q) vrp_balance(Q,epsilon,C,e_fun,h_fun,pi_fun,cL,cSys,wind_cf);
        Qstar = fzero(balance,[Q_grid(idx_cross-1), Q_grid(idx_cross)]);
    end

    Q_terminal(j) = Qstar;
    e_terminal(j) = e_fun(Qstar);
    status{j} = 'Boundary found';
    if any(gap(idx_cross+1:end)>0)
        warning('Feasibility re-entry after first boundary (epsilon=%.5f).',epsilon);
        status{j} = 'First boundary; feasibility re-entry';
    end
end

results_tbl = table(epsilon_values(:),Q_terminal(:),e_terminal(:),status(:), ...
    'VariableNames',{'epsilon','Q_terminal_GW','e_terminal_tCO2_per_MWh','Status'});
disp(results_tbl);

baseline_idx = find(abs(epsilon_values-epsilon_baseline)<1e-10,1);
if ~isempty(baseline_idx) && isfinite(Q_terminal(baseline_idx))
    fprintf('\n[Baseline epsilon = %.4f]\n',epsilon_baseline);
    fprintf('  Terminal renewable capacity = %.3f GW\n',Q_terminal(baseline_idx));
    fprintf('  Terminal emissions intensity = %.4f ton-CO2/MWh\n',e_terminal(baseline_idx));
end

%% Part II. Sensitivity of monotone reachability
% Maximum one-period next-state map:
%   S(Q) = Q + [R*(Q,eps) - required(Q)]/k.
% S'(Q) = 1 - [required'(Q) - R*'(Q,eps)]/k.
% We numerically estimate the worst derivative over the connected feasible
% interval starting at Q_start, up to Q_terminal (or the calibration limit).
% A numerical estimate is not a continuous-domain mathematical certificate.

worst_cost_minus_revenue_slope = nan(size(epsilon_values));
k_crit   = nan(size(epsilon_values));
min_slope_at_base = nan(size(epsilon_values));
reach_status = repmat({'Not evaluated'},size(epsilon_values));

for j = 1:numel(epsilon_values)
    epsilon = epsilon_values(j);
    gap = R_scale./epsilon - required_revenue;
    if gap(1)<0
        reach_status{j} = 'Infeasible at starting capacity';
        continue;
    end

    if isfinite(Q_terminal(j))
        Q_end = Q_terminal(j);
        reach_status{j} = 'Boundary found';
    else
        Q_end = Q_grid(end);
        reach_status{j} = 'Feasible through calibrated range';
    end

    % Include interpolation knots to capture changes in piecewise slopes.
    knots = wind_storage_capacity(wind_storage_capacity>Q_start & ...
                                  wind_storage_capacity<Q_end);
    Q_eval = sort(unique([Q_grid(Q_grid<Q_end), knots, Q_end]));

    % Avoid numerically tiny gaps from an almost duplicated endpoint.
    Q_eval = Q_eval([true, diff(Q_eval)>1e-7]);
    if numel(Q_eval)<2
        reach_status{j} = 'Insufficient feasible interval';
        continue;
    end

    [R_eval, required_eval] = compute_revenue_and_requirement( ...
        Q_eval,epsilon,C,e_fun,h_fun,pi_fun,cL,cSys,wind_cf);

    % Finite-interval slopes; includes the interpolation knot locations.
    slope_req_minus_R = diff(required_eval-R_eval)./diff(Q_eval);
    worst_slope = max(slope_req_minus_R);
    worst_cost_minus_revenue_slope(j) = worst_slope;
    k_crit(j) = max(0,worst_slope);
    min_slope_at_base(j) = 1-worst_slope/lambda;
end

reach_tbl = table(epsilon_values(:),k_crit(:),min_slope_at_base(:),reach_status(:), ...
    'VariableNames',{'epsilon','k_critical_MUSD_per_GW', ...
                     'min_Sprime_at_k_baseline','Status'});
disp(reach_tbl);

if ~isempty(baseline_idx) && isfinite(k_crit(baseline_idx))
    fprintf('\n[Reachability at baseline epsilon = %.4f]\n',epsilon_baseline);
    fprintf('  Estimated critical investment cost k = %.2f M$/GW\n',k_crit(baseline_idx));
    fprintf('  Assumed investment cost k           = %.2f M$/GW\n',lambda);
    if k_crit(baseline_idx)>0
        fprintf('  Ratio assumed/critical k            = %.2f\n',lambda/k_crit(baseline_idx));
    end
    fprintf('  Estimated minimum S''(Q) at baseline = %.4f\n',min_slope_at_base(baseline_idx));
end


%% Part III. Wholesale-value erosion and revenue sharing
% Alpha = 1: original calibrated ISO-NE wholesale-price curve.
% Alpha < 1: slower wholesale-value erosion.
% Alpha > 1: faster wholesale-value erosion.
%
% Hold the wholesale price at Q_start unchanged:
% pi_alpha(Q) = pi(Q_start) + alpha*(pi(Q)-pi(Q_start)).
%
% Other grid, demand, and cost functions remain unchanged.

alpha_values = [0.75 1.00 1.25];
alpha_labels = {'Slower (\alpha=0.75)', ...
                'Baseline (\alpha=1.00)', ...
                'Faster (\alpha=1.25)'};

pi_reference = pi_fun(Q_start);
Rstar_baseline = R_scale./epsilon_baseline;

Q_gamma_alpha    = nan(size(alpha_values));
Q_terminal_alpha = nan(size(alpha_values));
e_terminal_alpha = nan(size(alpha_values));
gamma_end_alpha  = nan(size(alpha_values));
alpha_status     = repmat({'Not evaluated'},size(alpha_values));

Q_path_alpha     = cell(size(alpha_values));
gamma_path_alpha = cell(size(alpha_values));
q_path_alpha     = cell(size(alpha_values));

for j = 1:numel(alpha_values)

    alpha = alpha_values(j);

    pi_alpha_fun = @(Q) pi_reference + ...
        alpha.*(pi_fun(Q)-pi_reference);

    pi_alpha_grid = pi_reference + ...
        alpha.*(pi_grid-pi_reference);

    % Generator revenue shortfall
    C2_grid = cL(Q_grid) - ...
        h_grid.*pi_alpha_grid.*annual_factor;

    % Separated-account financial requirement
    required_alpha = cSys(Q_grid) + max(C2_grid,0);
    gap_alpha = Rstar_baseline - required_alpha;

    if gap_alpha(1)<0
        alpha_status{j} = 'Infeasible at starting capacity';
        continue;
    end

    %% Financial feasibility boundary Q*
    idx_cross = find(gap_alpha<=0,1,'first');

    if isempty(idx_cross)
        Qstar = NaN;
        Q_end = Q_grid(end);
        alpha_status{j} = 'No boundary within calibrated range';

    elseif idx_cross==1
        Qstar = Q_grid(1);
        Q_end = Qstar;
        alpha_status{j} = 'Boundary at starting capacity';

    else
        balance_alpha = @(Q) vrp_balance( ...
            Q,epsilon_baseline,C,e_fun,h_fun, ...
            pi_alpha_fun,cL,cSys,wind_cf);

        Qstar = fzero(balance_alpha, ...
            [Q_grid(idx_cross-1),Q_grid(idx_cross)]);

        Q_end = Qstar;
        alpha_status{j} = 'Boundary found';

        if any(gap_alpha(idx_cross+1:end)>0)
            warning('Feasibility re-entry for alpha=%.2f.',alpha);
            alpha_status{j} = ...
                'First boundary; feasibility re-entry';
        end
    end

    Q_terminal_alpha(j) = Qstar;

    if isfinite(Qstar)
        e_terminal_alpha(j) = e_fun(Qstar);
    end

    %% Generator-support onset Q_gamma
    if C2_grid(1)>0
        Q_gamma_alpha(j) = Q_start;
    else
        idx_gamma = find(C2_grid>0 & Q_grid<=Q_end,1,'first');

        if ~isempty(idx_gamma) && idx_gamma>1
            C2_fun = @(Q) cL(Q) - ...
                h_fun(Q).*pi_alpha_fun(Q).*annual_factor;

            Q_gamma_alpha(j) = fzero(C2_fun, ...
                [Q_grid(idx_gamma-1),Q_grid(idx_gamma)]);
        end
    end

    %% Optimal decisions along financially feasible states
    Q_path = sort(unique([Q_grid(Q_grid<Q_end),Q_end]));

    [R_path,required_path] = compute_revenue_and_requirement( ...
        Q_path,epsilon_baseline,C,e_fun,h_fun, ...
        pi_alpha_fun,cL,cSys,wind_cf);

    C2_path = cL(Q_path) - ...
        h_fun(Q_path).*pi_alpha_fun(Q_path).*annual_factor;

    gamma_path = max(C2_path,0)./R_path;
    q_path = (R_path-required_path)./lambda;

    % Remove small numerical errors at the financial boundary
    q_path(abs(q_path)<1e-8) = 0;

    if any(q_path < -1e-6)
        warning('Negative expansion for alpha=%.2f.',alpha);
    end

    Q_path_alpha{j} = Q_path;
    gamma_path_alpha{j} = gamma_path;
    q_path_alpha{j} = q_path;

    if isfinite(Qstar)
        gamma_end_alpha(j) = gamma_path(end);
    end
end

%% Summarize wholesale-value erosion sensitivity

alpha_tbl = table( ...
    alpha_values(:), ...
    Q_gamma_alpha(:), ...
    Q_terminal_alpha(:), ...
    e_terminal_alpha(:), ...
    gamma_end_alpha(:), ...
    alpha_status(:), ...
    'VariableNames', ...
    {'alpha','Q_generator_support_GW','Q_terminal_GW', ...
     'e_terminal_tCO2_per_MWh','gamma_at_boundary','Status'});

fprintf('\n[Wholesale-value erosion sensitivity]\n');
fprintf('Baseline demand sensitivity = %.4f\n',epsilon_baseline);
disp(alpha_tbl);

%% Check consistency with original baseline

idx_alpha_base = find(abs(alpha_values-1)<1e-12,1);

if ~isempty(idx_alpha_base) && ~isempty(baseline_idx)

    Q_base_alpha = Q_terminal_alpha(idx_alpha_base);
    Q_base_original = Q_terminal(baseline_idx);

    if isfinite(Q_base_alpha) && isfinite(Q_base_original)

        difference = abs(Q_base_alpha-Q_base_original);

        fprintf('Alpha=1 baseline Q* difference = %.6f GW\n', ...
            difference);

        if difference>1e-4
            warning('Alpha=1 differs from original baseline.');
        end
    end
end


%% IEEE plotting settings (both figures have the SAME single-column width)
fig_width   = 3.5;  % inches; change heights independently below
fig1_height = 2.3;
fig2_height = 2.65;
fig3_height = 3.0;   % Wholesale-value sensitivity figure

font_name  = 'Times New Roman';
font_size  = 9;
line_width = 1.25;

main_color = [0.10 0.33 0.55];
base_color = [0.40 0.40 0.40];
mark_color = [0.70 0.15 0.15];

eps_plot = epsilon_values(:)*1000;  % display epsilon in 10^-3 units
marker_idx = unique([1:6:numel(eps_plot),numel(eps_plot)]);

%% Plot 1. Demand sensitivity: financial boundary and terminal emissions
fig1 = figure('Color','w','Units','inches', ...
    'Position',[1 1 fig_width fig1_height],'PaperPositionMode','auto');
tl1 = tiledlayout(fig1,2,1,'TileSpacing','compact','Padding','compact');

ax11 = nexttile(tl1,1);
plot(ax11,eps_plot,Q_terminal(:),'-o', ...
    'Color',main_color,'LineWidth',line_width, ...
    'MarkerSize',3,'MarkerFaceColor','w','MarkerIndices',marker_idx);
hold(ax11,'on');

xline(ax11,epsilon_baseline*1000,':','Color',base_color,'LineWidth',0.9);

if ~isempty(baseline_idx) && isfinite(Q_terminal(baseline_idx))
    plot(ax11,epsilon_baseline*1000,Q_terminal(baseline_idx),'s', ...
        'MarkerSize',4.5,'MarkerFaceColor',main_color,'MarkerEdgeColor',main_color);
end

ylabel(ax11,{'Q^*','(GW)'});
title(ax11,'(a) Financial feasibility boundary');
ylim(ax11,[4 8]);
yticks(ax11,[4 6 8]);

ax12 = nexttile(tl1,2);
plot(ax12,eps_plot,e_terminal(:),'-o', ...
    'Color',main_color,'LineWidth',line_width, ...
    'MarkerSize',3,'MarkerFaceColor','w','MarkerIndices',marker_idx);
hold(ax12,'on');

xline(ax12,epsilon_baseline*1000,':','Color',base_color,'LineWidth',0.9);

if ~isempty(baseline_idx) && isfinite(e_terminal(baseline_idx))
    plot(ax12,epsilon_baseline*1000,e_terminal(baseline_idx),'s', ...
        'MarkerSize',4.5,'MarkerFaceColor',main_color,'MarkerEdgeColor',main_color);
end

ylabel(ax12,{'e(Q^*)','(tCO_2/MWh)'});
xlabel(ax12,'Demand sensitivity, \epsilon (\times10^{-3})');
title(ax12,'(b) Emissions at the boundary');
ylim(ax12,[0 0.35]);
yticks(ax12,[0 0.15 0.30]);

for ax = [ax11,ax12]
    style_ieee_axes(ax,font_name,font_size);
    xlim(ax,[min(eps_plot)-0.25,max(eps_plot)+0.25]);
    xticks(ax,[2 5 10 15 20]);
end

linkaxes([ax11,ax12],'x');
set(ax11,'XTickLabel',[]);
drawnow;

%% Plot 2. ONE contour map of minimum reachability slope
% The zero contour is the numerical threshold of the SUFFICIENT condition.
% A negative value does NOT prove that myopic expansion is suboptimal.

valid_reach = isfinite(worst_cost_minus_revenue_slope);

if ~any(valid_reach)
    warning('No valid reachability slopes: skipping the contour map.');
else
    eps_valid = epsilon_values(valid_reach)*1000;
    worst_slope_valid = worst_cost_minus_revenue_slope(valid_reach);
    crit_valid = k_crit(valid_reach);

    positive_crit = crit_valid(crit_valid>0);

    if isempty(positive_crit)
        k_min = max(1,lambda/100);
    else
        % Keep the critical region visible while including the baseline k.
        k_min = max(1,min(min(positive_crit)/3,lambda/3));
    end

    k_max = max(1.25*lambda,1.25*max(crit_valid));
    k_values = logspace(log10(k_min),log10(k_max),300);

    [EPS_mesh,K_mesh] = meshgrid(eps_valid,k_values);
    worst_mesh = repmat(worst_slope_valid(:).',numel(k_values),1);
    min_slope_mesh = 1-worst_mesh./K_mesh;

    fig2 = figure('Color','w','Units','inches', ...
        'Position',[1 1 fig_width fig2_height],'PaperPositionMode','auto');

    ax2 = axes('Parent',fig2);

    contourf(ax2,EPS_mesh,K_mesh,min_slope_mesh, ...
        -0.5:0.1:1.0,'LineStyle','none');

    colormap(ax2,parula(256));
    caxis(ax2,[-0.5 1]);
    hold(ax2,'on');

    % S'(Q)=0: threshold of the sufficient condition.
    if any(crit_valid>k_min & crit_valid<k_max)
        contour(ax2,EPS_mesh,K_mesh,min_slope_mesh,[0 0], ...
            'LineColor','k','LineWidth',1.35);
    end

    % Highlight baseline assumptions.
    xline(ax2,epsilon_baseline*1000,':', ...
        'Color',base_color,'LineWidth',0.9);

    yline(ax2,lambda,':', ...
        'Color',base_color,'LineWidth',0.9);

    plot(ax2,epsilon_baseline*1000,lambda,'p', ...
        'MarkerSize',8,'MarkerFaceColor',mark_color, ...
        'MarkerEdgeColor','k','LineWidth',0.6);

    xlabel(ax2,'Demand sensitivity, \epsilon (\times10^{-3})');
    ylabel(ax2,'Investment cost, k (M$/GW)');
    title(ax2,'Estimated minimum reachability slope');

    style_ieee_axes(ax2,font_name,font_size);
    set(ax2,'YScale','log');

    xlim(ax2,[min(eps_valid)-0.25,max(eps_valid)+0.25]);
    xticks(ax2,[2 5 10 15 20]);
    ylim(ax2,[k_min k_max]);

    cb = colorbar(ax2,'eastoutside');
    cb.Label.String = 'min_Q S''(Q)';
    cb.FontName = font_name;
    cb.FontSize = font_size-1;

    drawnow;
end


%% Plot 3. Wholesale-value erosion and financing decisions
% Panel (a): optimal generator revenue-sharing ratio gamma*(Q)
% Panel (b): maximum feasible renewable expansion q*(Q)
% Curves terminate at the respective financial feasibility boundaries.

scenario_colors = [ ...
    0.10 0.48 0.43; ...  % Slower erosion
    0.10 0.33 0.55; ...  % Baseline
    0.70 0.30 0.12];     % Faster erosion

fig3 = figure('Color','w','Units','inches', ...
    'Position',[1 1 fig_width fig3_height], ...
    'PaperPositionMode','auto');

tl3 = tiledlayout(fig3,2,1, ...
    'TileSpacing','compact','Padding','compact');

%% (a) Optimal revenue sharing
ax31 = nexttile(tl3,1);
hold(ax31,'on');

%% (b) Maximum feasible renewable expansion
ax32 = nexttile(tl3,2);
hold(ax32,'on');

scenario_lines = gobjects(1,numel(alpha_values));

for j = 1:numel(alpha_values)

    if isempty(Q_path_alpha{j})
        continue;
    end

    Qp = Q_path_alpha{j};
    gp = gamma_path_alpha{j};
    qp = q_path_alpha{j};

    %% Revenue-sharing curve
    scenario_lines(j) = plot(ax31, Qp, gp, '-', ...
        'Color', scenario_colors(j,:), ...
        'LineWidth', line_width+0.1);

    %% Expansion curve
    plot(ax32, Qp, qp, '-', ...
        'Color', scenario_colors(j,:), ...
        'LineWidth', line_width+0.1);

    %% Mark generator-support onset
    if isfinite(Q_gamma_alpha(j))

        onset_gamma = 0;
        if abs(Q_gamma_alpha(j)-Q_start)<1e-8
            onset_gamma = gp(1);
        end

        plot(ax31,Q_gamma_alpha(j),onset_gamma,'o', ...
            'Color',scenario_colors(j,:), ...
            'MarkerFaceColor','w', ...
            'MarkerSize',4, ...
            'LineWidth',1);
    end

    %% Mark financial feasibility boundary
    if isfinite(Q_terminal_alpha(j)) && ...
            strcmp(alpha_status{j},'Boundary found')

        plot(ax32,Q_terminal_alpha(j),0,'s', ...
            'MarkerFaceColor',scenario_colors(j,:), ...
            'MarkerEdgeColor',scenario_colors(j,:), ...
            'MarkerSize',4);
    end
end

%% Axis labels and titles

ylabel(ax31,'Generator revenue share, \gamma^*(Q)');
title(ax31,'(a) Generator support');

ylabel(ax32,{'Capacity addition, q^*(Q)','(GW/period)'});
xlabel(ax32,'Installed renewable capacity, Q (GW)');
title(ax32,'(b) Maximum feasible expansion');

%% Common IEEE formatting

valid_paths = ~cellfun(@isempty,Q_path_alpha);

if any(valid_paths)

    Q_end_plot = max(cellfun( ...
        @(x) x(end),Q_path_alpha(valid_paths)));

    max_gamma = max(cellfun( ...
        @max,gamma_path_alpha(valid_paths)));

    max_q = max(cellfun( ...
        @max,q_path_alpha(valid_paths)));

    for ax = [ax31,ax32]

        style_ieee_axes(ax,font_name,font_size);

        xlim(ax,[Q_start-0.05, ...
            min(Q_max,Q_end_plot+0.20)]);
    end

    ylim(ax31,[0,min(1.05,max(0.1,1.1*max_gamma))]);
    ylim(ax32,[0,max(0.01,1.1*max_q)]);

else

    for ax = [ax31,ax32]
        style_ieee_axes(ax,font_name,font_size);
    end
end

%% Legend

valid_lines = isgraphics(scenario_lines);

if any(valid_lines)

    legend(ax31,scenario_lines(valid_lines), ...
        alpha_labels(valid_lines), ...
        'Location','best', ...
        'Box','off', ...
        'FontName',font_name, ...
        'FontSize',font_size-1);
end

%% Share the capacity axis

linkaxes([ax31,ax32],'x');
set(ax31,'XTickLabel',[]);

drawnow;


%% Helper: revenue minus recurring financial requirements
function gap = vrp_balance(Q,epsilon,C,e_fun,h_fun,pi_fun,cL,cSys,wind_cf)
    [Rstar,required] = compute_revenue_and_requirement( ...
        Q,epsilon,C,e_fun,h_fun,pi_fun,cL,cSys,wind_cf);
    gap = Rstar-required;
end

%% Helper: revenue and separated-account financial requirement
function [Rstar,required] = compute_revenue_and_requirement( ...
    Q,epsilon,C,e_fun,h_fun,pi_fun,cL,cSys,wind_cf)

    eQ = e_fun(Q);
    hQ = h_fun(Q);
    piQ = pi_fun(Q);

    x_opt = max(1,log(C./hQ));
    Rstar = (eQ./epsilon).*x_opt.*C.*exp(-x_opt);

    annual_factor = wind_cf*8760*1000/1e6;
    wholesale_revenue = hQ.*piQ*annual_factor;

    required = cSys(Q)+max(cL(Q)-wholesale_revenue,0);
end

%% Helper: consistent IEEE axis style
function style_ieee_axes(ax,font_name,font_size)
    set(ax,'FontName',font_name,'FontSize',font_size, ...
        'FontWeight','normal','LabelFontSizeMultiplier',1, ...
        'TitleFontSizeMultiplier',1,'TitleFontWeight','normal', ...
        'TickLabelInterpreter','tex','LineWidth',0.65, ...
        'TickDir','out','Box','off','XColor','k','YColor','k', ...
        'XGrid','on','YGrid','on','GridAlpha',0.10,'Layer','top');
end

