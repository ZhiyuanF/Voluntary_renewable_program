function [price_series, dispatch_info] = run_rt_price_simple(wind_ratio, storage_ratio, sigma, num_scenarios, forecast_error)
    % 1. Set model parameters
    b = 0.05; 
    d = 5; 
    f = 4; 
    g = 0.5; 
    h = 10; 
    c = forecast_error;  
    % expose more of these if needed

    tic; % start timer

    % 2. Generate DA price (as expected price for storage)
    energy_price = DA_price(wind_ratio, b, c, d, storage_ratio, f, g, h);

    fprintf('DA price took %.2f seconds.\n', toc);


    tic;
    % 3. Compute value-function-based storage bids
    seg_num = 5;
    T = 24;
    ed = 1/1500;
    eta = 0.95;
    mc = h;
    [VF, ~] = value_fcn_calcu(energy_price, seg_num, floor(1/ed)+1, T, mc, 1/f, eta, ed, 0, sigma);
    bid_d = VF.k / eta + mc;
    bid_c = VF.k * eta;

    fprintf('Value function calculation took %.2f seconds.\n', toc);

    % 4. Run real-time price and dispatch over 24 hours
    scenarios = num_scenarios;
    g1 = repmat([0.2 0.2 0.1 0 0], scenarios, 1);
    g2 = g1;  % if needed

    price_series = zeros(scenarios, T);
    carbon_intensity_series = zeros(scenarios, T);
    wind_fraction_series = zeros(scenarios, T);
    tic;
    for t = 1:T
        [~, ~, ~, price1, g1, carbon_intensity1, wind_fraction1] = ...
            RT_price_carbon_single(wind_ratio, scenarios, c, d, storage_ratio, f, g1, g2, h, ...
                            bid_d(:, t), bid_c(:, t), t);
        price_series(:, t) = price1;
        carbon_intensity_series(:, t) = carbon_intensity1;
        wind_fraction_series(:, t) = wind_fraction1;
    end
    fprintf('RT dispatch loop took %.2f seconds.\n', toc);

    % 5. Optional: return dispatch metrics if needed
    dispatch_info.carbon_intensity_series = carbon_intensity_series;
    dispatch_info.wind_fraction_series = wind_fraction_series;
end
