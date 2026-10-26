function [p, q, gamma] = single_episode_baseline_20251020(Q, epsilon, C, f, h, piE, cL, cSys, lambda, wind_cf)
% SINGLE_EPISODE_BASELINE
% Baseline single-period decision given current capacity Q.
% Chooses price p, revenue share gamma, and new capacity q.
%
% Inputs:
%   Q        : current cumulative renewable capacity [GW]
%   epsilon  : demand sensitivity ε (>0)
%   C        : market size (>0)
%   f, h     : function handles f(Q), h(Q)
%   piE      : function handle π(Q) (effective price received by renewables)
%   cL       : function handle c_L(Q) (renewable O&M-side cost; no CAPEX)
%   cSys     : function handle c_system(Q) (system cost; here includes storage CAPEX proxy)
%   lambda   : install cost per GW for new capacity q (M$ / GW)
%
% Outputs:
%   p        : optimal price [$ / MWh]
%   q        : new capacity [GW]
%   gamma    : revenue share to generators in [0,1]
%
% Feasibility rules enforced:
%   (i)  L(p) ≤ h(Q)  (credit feasibility)
%   (ii) c_L(Q) ≤ h(Q)·π(Q) + γ·p·L(p)              (generator viability)
%   (iii)c_sys(Q) + λ·q ≤ (1 − γ)·p·L(p)            (operator balance)
%
% Stops with error('Infeasible: ...') if no γ ∈ [0,1] and q ≥ 0 can satisfy constraints.

    % --- Tolerances ---
    TOL = 1e-9;

    % --- Basic checks ---
    if ~(epsilon > 0) || ~(C > 0) || ~(lambda > 0)
        error('Parameters must satisfy: epsilon>0, C>0, lambda>0.');
    end

    fQ = f(Q);
    hQ = h(Q);
    piQ = piE(Q);
    if fQ <= 0
        error('Infeasible: f(Q)<=0 makes demand ill-defined.');
    end
    if hQ < 0
        error('Infeasible: h(Q)<0 is not allowed.');
    end

    % --- Demand function (baseline) ---
    L = @(p) C .* exp(-epsilon .* p ./ fQ);

    % --- Step 1: price p ---
    % Unconstrained candidate:
    p = fQ / epsilon;

    % Enforce credit feasibility L(p) <= h(Q); if violated, raise price to bind:
    if L(p) > hQ + TOL
        if hQ <= 0
            error('Infeasible: h(Q)=0 but demand would be positive at any finite price.');
        end
        p = (fQ / epsilon) * log(C / max(hQ, TOL));  % p^dagger
    end

    % Recompute demand at chosen price
    Lp = L(p);

    % Safety: after adjustment ensure feasibility
    if Lp > hQ + 1e-6
        error('Internal error: L(p) still exceeds h(Q) after adjustment.');
    end

    % --- Step 2: find minimal gamma in [0,1] for generator viability ---
    % Need: c_L(Q) <= h(Q)*pi(Q) + gamma * p * L(p)
    denom = p * Lp;
    rhs_base = hQ * wind_cf * 8760*1000 * piQ / 1000000; % hQ in GW, time capacity factor, times 8760 hours, times 1000 to convert to MWh, $ unit in Mllion
        lhs = cL(Q);


    fprintf('\n[DIAGNOSTIC INFO at Q = %.3f]\n', Q);
    fprintf('  f(Q)     = %.3f\n', fQ);
    fprintf('  h(Q)     = %.3f\n', hQ);
    fprintf('  pi(Q)    = %.3f\n', piQ);
    fprintf('  p        = %.3f\n', p);
    fprintf('  L(p)     = %.3f\n', Lp);
    fprintf('  c_L(Q)     = %.3f\n', cL(Q));
    fprintf('  c_sys(Q)     = %.3f\n', cSys(Q));
    fprintf('  denom    = p * L(p) = %.3f\n', denom);
    fprintf('  Energy revenue = %.3f\n\n', rhs_base);

    if lhs <= rhs_base + TOL
        gamma = 0;  % already viable with energy-market revenue alone
    else
        if denom <= TOL
            error('Infeasible: no credit revenue to support generators (p*L=0) but c_L(Q)>h(Q)π(Q).');
        end
        gamma_req = (lhs - rhs_base) / denom;
        gamma = max(0, gamma_req);
        if gamma > 1 + TOL
            error('Infeasible: required gamma=%.3f exceeds 1 to keep generators viable.', gamma);
        end
        gamma = min(1, gamma); % clamp numerically
    end


    % --- Step 3: operator balance → compute q from remaining funds ---
    % c_sys(Q) + lambda*q <= (1 - gamma) * p * L(p)
    available = (1 - gamma) * denom - cSys(Q);
    if available < -TOL
        error('Infeasible: operator revenue insufficient even for c_system(Q) at chosen p, gamma.');
    end

    q = max(0, available / lambda);  % invest all remaining funds

    fprintf('  gamma     = %.3f\n', gamma);
    fprintf('  q (new capacity) = %.3f\n\n', q);
    

    % --- Final sanity checks ---
    if Lp > hQ + 1e-6
        fprintf('Warning: Credit feasibility violated: L(p)=%.3f > h(Q)=%.3f\n', Lp, hQ);
        q = 0;   % cannot expand further
        return;
    end

    if cL(Q) - (rhs_base + gamma*denom) > 1e-6
        fprintf('Warning: Generator viability violated: cL(Q)-[h(Q)*pi(Q)+γ·p·L(p)] = %.3f\n', ...
                cL(Q) - (rhs_base + gamma*denom));
        q = 0;   % no feasible expansion
        return;
    end

    if cSys(Q) + lambda*q - (1 - gamma)*denom > 1e-6
        fprintf('Warning: Operator balance violated: cSys(Q)+λ·q-(1-γ)pL(p)=%.3f\n', ...
                cSys(Q) + lambda*q - (1 - gamma)*denom);
        q = 0;   % cannot invest this round
        return;
    end
end