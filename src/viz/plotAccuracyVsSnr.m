function fig = plotAccuracyVsSnr(T, systemName, opts)
%PLOTACCURACYVSSNR Accuracy against SNR, one line per query length.
%
%   FIG = PLOTACCURACYVSSNR(T, SYSTEMNAME) plots the table COMPUTEMETRICS
%   produced, grouped by targetSnrDb and lengthSec, with Wilson 95% intervals
%   as error bars.
%
%   FIG = PLOTACCURACYVSSNR(T, SYSTEMNAME, OPTS) accepts a struct with
%       .metric   column to plot (default 'closedSetAcc')
%       .showN    annotate each point with its n (default false)
%
%   CLEAN IS Inf, AND Inf DOES NOT PLOT. targetSnrDb is Inf for the clean
%   condition, which on a linear axis either vanishes or drags the limits to
%   infinity - the earlier GSCATTER version did the latter and produced an
%   empty figure. Clean is a real condition and belongs on the chart, so it is
%   drawn one grid step to the right of the highest finite SNR and tick-labelled
%   "clean", with the axis reversed so noise increases left to right the way
%   the reader expects a degradation curve to run.
%
%   ERROR BARS, NOT BARE POINTS. Blueprint 8.4 asks for a Wilson interval on
%   every reported accuracy, and the reason is visible here: at 150 queries
%   per cell the half-width is around 6 pp, which is most of the 10 pp gain
%   criterion 1 claims. A figure without them invites the panel to read a
%   difference that the data may not support.
%
%   Milestone: M3.  Blueprint: section(s) 7 (M3), 8.4.
%
%   See also COMPUTEMETRICS, PLOTACCURACYVSLENGTH, WILSONINTERVAL.

if nargin < 2 || isempty(systemName)
    systemName = 'baseline';
end
if nargin < 3 || isempty(opts)
    opts = struct();
end
if ~isfield(opts, 'metric'), opts.metric = 'closedSetAcc'; end
if ~isfield(opts, 'showN'),  opts.showN  = false;          end

requireCols(T, {'targetSnrDb', 'lengthSec', opts.metric});

loCol = [opts.metric 'Lo'];
hiCol = [opts.metric 'Hi'];
hasCI = all(ismember({loCol, hiCol}, T.Properties.VariableNames));

% ---- Map SNR onto plotting positions -----------------------------------
snrVals   = unique(T.targetSnrDb);
finiteSnr = sort(snrVals(~isinf(snrVals)), 'descend');
hasClean  = any(isinf(snrVals));

if isempty(finiteSnr)
    step = 5;
else
    step = median(abs(diff([finiteSnr; finiteSnr(end) - 5])));
    if ~(step > 0), step = 5; end
end

% Positions run left (worst SNR) to right (best), clean furthest right.
posOf = containers.Map('KeyType', 'double', 'ValueType', 'double');
for k = 1:numel(finiteSnr)
    posOf(finiteSnr(k)) = numel(finiteSnr) - k + 1;
end
cleanPos = numel(finiteSnr) + 1;

tickPos   = 1:numel(finiteSnr);
tickLabel = arrayfun(@(v) sprintf('%g', v), flipud(finiteSnr(:)), 'UniformOutput', false);
if hasClean
    tickPos   = [tickPos, cleanPos];
    tickLabel = [tickLabel; {'clean'}];
end

% ---- Draw ---------------------------------------------------------------
fig = figure('Color', 'white', 'Name', sprintf('Accuracy vs SNR (%s)', systemName));
ax  = axes(fig); %#ok<LAXES>
hold(ax, 'on');

lengths = unique(T.lengthSec);
cmap    = lines(max(numel(lengths), 1));
h       = gobjects(numel(lengths), 1);

for k = 1:numel(lengths)
    sub = T(T.lengthSec == lengths(k), :);

    x = zeros(height(sub), 1);
    for r = 1:height(sub)
        if isinf(sub.targetSnrDb(r))
            x(r) = cleanPos;
        else
            x(r) = posOf(sub.targetSnrDb(r));
        end
    end

    [x, ord] = sort(x);
    sub      = sub(ord, :);
    y        = 100 * sub.(opts.metric);

    if hasCI
        neg = y - 100 * sub.(loCol);
        pos = 100 * sub.(hiCol) - y;
        h(k) = errorbar(ax, x, y, neg, pos, '-o', ...
            'Color', cmap(k, :), 'MarkerFaceColor', cmap(k, :), ...
            'MarkerSize', 5, 'LineWidth', 1.4, 'CapSize', 6);
    else
        h(k) = plot(ax, x, y, '-o', ...
            'Color', cmap(k, :), 'MarkerFaceColor', cmap(k, :), ...
            'MarkerSize', 5, 'LineWidth', 1.4);
    end

    if opts.showN && ismember('nInDb', sub.Properties.VariableNames)
        for r = 1:height(sub)
            text(ax, x(r), y(r), sprintf('  n=%d', sub.nInDb(r)), ...
                'FontSize', 7, 'Color', cmap(k, :), 'VerticalAlignment', 'bottom');
        end
    end
end

if hasClean
    xline(ax, cleanPos - 0.5, ':', 'Color', [0.6 0.6 0.6], 'HandleVisibility', 'off');
end

set(ax, 'XTick', tickPos, 'XTickLabel', tickLabel);
xlim(ax, [min(tickPos) - 0.4, max(tickPos) + 0.4]);
ylim(ax, [0 102]);
grid(ax, 'on');
box(ax, 'on');

xlabel(ax, 'Target SNR (dB)');
ylabel(ax, sprintf('%s (%%)', prettyMetric(opts.metric)));
title(ax, sprintf('%s vs SNR - %s', prettyMetric(opts.metric), systemName));

legend(ax, h, arrayfun(@(v) sprintf('%g s', v), lengths, 'UniformOutput', false), ...
    'Location', 'southeast');

hold(ax, 'off');

if nargout == 0
    clear fig
end

end

% =======================================================================
function requireCols(T, cols)
missingCols = setdiff(cols, T.Properties.VariableNames);
if ~isempty(missingCols)
    error('HimigTransform:BadMetricsTable', ...
        ['Metrics table has no column(s): %s.\nGroup by at least ' ...
         '{''lengthSec'',''targetSnrDb''} in COMPUTEMETRICS.'], ...
        strjoin(missingCols, ', '));
end
end

% =======================================================================
function s = prettyMetric(m)
switch m
    case 'closedSetAcc',   s = 'Closed-set top-1 accuracy';
    case 'operationalAcc', s = 'Identification accuracy';
    case 'precision',      s = 'Precision';
    case 'recall',         s = 'Recall';
    case 'far',            s = 'False-accept rate';
    otherwise,             s = m;
end
end
