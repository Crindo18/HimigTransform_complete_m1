function fig = plotOpenSetRoc(sweep, Cfg, fig)
%PLOTOPENSETROC Operating-characteristic curve for the open-set decision.
%
%   FIG = PLOTOPENSETROC(SWEEP, CFG) draws the sweep returned by
%   TUNETHRESHOLDS: recall against false-accept rate, with the Pareto frontier
%   highlighted, the chosen operating point marked, and the FAR budget shown.
%
%   FIG = PLOTOPENSETROC(SWEEP, CFG, FIG) draws into an existing figure.
%
%   WHY THIS IS NOT A TEXTBOOK ROC. A classifier ROC sweeps ONE threshold and
%   plots TPR against FPR. This decision has TWO thresholds - tau on normScore
%   and rho on the top1/top2 margin - so the sweep is a cloud of points, not a
%   curve. What matters is its upper-left frontier: for each achievable FAR,
%   the best recall any (tau, rho) reaches. Plotting the cloud alone invites
%   reading a dominated point as if it were on the curve.
%
%   The y-axis is recall over IN-DATABASE queries and the x-axis is FAR over
%   HOLDOUT queries - two different populations, which is exactly what open-set
%   evaluation means. Blueprint 8.3 defines both.
%
%   Milestone: M5.  Blueprint: sections 8.3, 8.4.
%
%   See also TUNETHRESHOLDS, DECIDEOPENSET.

narginchk(2, 3);
if nargin < 3 || isempty(fig)
    fig = figure('Color', 'w', 'Position', [100 100 780 560]);
else
    figure(fig);
    clf(fig);
end

U = sweep.Properties.UserData;

far    = sweep.far;
recall = sweep.recall;

ax = axes('Parent', fig);
hold(ax, 'on');

% ---- The cloud ----------------------------------------------------------
scatter(ax, 100 * far, 100 * recall, 14, [0.75 0.78 0.85], 'filled', ...
    'MarkerFaceAlpha', 0.55, 'DisplayName', 'all (tau, rho)');

% ---- Pareto frontier ----------------------------------------------------
frontier = paretoFrontier(far, recall);
[~, ord] = sort(far(frontier));
frontier = frontier(ord);

plot(ax, 100 * far(frontier), 100 * recall(frontier), '-', ...
    'LineWidth', 2, 'Color', [0.20 0.40 0.70], ...
    'DisplayName', 'best recall at each FAR');

% ---- FAR budget ---------------------------------------------------------
if isfield(U, 'farBudget') && isfinite(U.farBudget)
    xline(ax, 100 * U.farBudget, '--', ...
        sprintf('FAR budget %.1f%%', 100 * U.farBudget), ...
        'Color', [0.65 0.25 0.25], 'LineWidth', 1.2, ...
        'LabelVerticalAlignment', 'bottom', ...
        'DisplayName', 'FAR budget');
end

% ---- Chosen operating point --------------------------------------------
if isfield(U, 'chosenIdx') && ~isempty(U.chosenIdx)
    k = U.chosenIdx;
    plot(ax, 100 * far(k), 100 * recall(k), 'p', ...
        'MarkerSize', 17, 'MarkerFaceColor', [0.95 0.65 0.10], ...
        'MarkerEdgeColor', [0.35 0.22 0.02], 'LineWidth', 1.1, ...
        'DisplayName', sprintf('chosen: tau %.3f, rho %.2f', ...
            sweep.tau(k), sweep.rho(k)));

    text(ax, 100 * far(k), 100 * recall(k), ...
        sprintf('  recall %.1f%%\n  precision %.1f%%', ...
            100 * recall(k), 100 * sweep.precision(k)), ...
        'VerticalAlignment', 'top', 'FontSize', 9);
end

hold(ax, 'off');
grid(ax, 'on');
box(ax, 'on');

xlabel(ax, 'False accept rate on holdout songs (%)');
ylabel(ax, 'Recall on in-database queries (%)');

sysName = 'system';
if isfield(U, 'system'), sysName = char(U.system); end

rangeTxt = '';
if isfield(U, 'snrRange')
    if isinf(U.snrRange(2))
        rangeTxt = sprintf(', tuned on %g dB and above', U.snrRange(1));
    else
        rangeTxt = sprintf(', tuned on %g..%g dB', U.snrRange(1), U.snrRange(2));
    end
end

title(ax, sprintf('Open-set operating characteristic - %s%s', sysName, rangeTxt));

sub = '';
if isfield(U, 'nInDb') && isfield(U, 'nHoldout')
    sub = sprintf('dev split: %d in-database, %d holdout queries', ...
        U.nInDb, U.nHoldout);
end
if ~isempty(sub)
    subtitle(ax, sub);
end

legend(ax, 'Location', 'southeast');
xlim(ax, [0 max(1, 100 * max(far))]);
ylim(ax, [0 100]);

end

% =======================================================================
function idx = paretoFrontier(cost, benefit)
%PARETOFRONTIER Points with no other point at both lower cost and higher benefit.

n   = numel(cost);
[~, ord] = sortrows([cost(:), -benefit(:)]);

idx     = false(n, 1);
bestSoFar = -Inf;

for k = 1:n
    j = ord(k);
    if benefit(j) > bestSoFar
        idx(j)    = true;
        bestSoFar = benefit(j);
    end
end

idx = find(idx);

end
