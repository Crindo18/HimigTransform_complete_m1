function fig = plotAccuracyVsLength(T, systemName, opts)
%PLOTACCURACYVSLENGTH Accuracy against query length, one line per SNR.
%
%   FIG = PLOTACCURACYVSLENGTH(T, SYSTEMNAME) plots the table COMPUTEMETRICS
%   produced, grouped by lengthSec and targetSnrDb, with Wilson 95% intervals.
%
%   FIG = PLOTACCURACYVSLENGTH(T, SYSTEMNAME, OPTS) accepts a struct with
%       .metric   column to plot (default 'closedSetAcc')
%       .showN    annotate each point with its n (default false)
%
%   The x axis here is genuinely numeric - 3, 5, 10 seconds - so unlike
%   PLOTACCURACYVSSNR it needs no remapping. Inf still appears, but only as a
%   SERIES label, where it is rendered "clean" rather than printed as "Inf dB".
%
%   Blueprint 8.4 wants an interval on every reported accuracy; at three
%   lengths and one line per SNR this is the figure where the 3 s cells show
%   their width, which is exactly the comparison Enhancement 2 is judged on.
%
%   Milestone: M3.  Blueprint: section(s) 7 (M3), 8.4.
%
%   See also COMPUTEMETRICS, PLOTACCURACYVSSNR, WILSONINTERVAL.

if nargin < 2 || isempty(systemName)
    systemName = 'baseline';
end
if nargin < 3 || isempty(opts)
    opts = struct();
end
if ~isfield(opts, 'metric'), opts.metric = 'closedSetAcc'; end
if ~isfield(opts, 'showN'),  opts.showN  = false;          end

missingCols = setdiff({'targetSnrDb', 'lengthSec', opts.metric}, T.Properties.VariableNames);
if ~isempty(missingCols)
    error('HimigTransform:BadMetricsTable', ...
        ['Metrics table has no column(s): %s.\nGroup by at least ' ...
         '{''lengthSec'',''targetSnrDb''} in COMPUTEMETRICS.'], ...
        strjoin(missingCols, ', '));
end

loCol = [opts.metric 'Lo'];
hiCol = [opts.metric 'Hi'];
hasCI = all(ismember({loCol, hiCol}, T.Properties.VariableNames));

% Clean first, then descending SNR - the order a reader scans a legend.
snrVals = unique(T.targetSnrDb);
snrVals = [snrVals(isinf(snrVals)); sort(snrVals(~isinf(snrVals)), 'descend')];

fig = figure('Color', 'white', 'Name', sprintf('Accuracy vs length (%s)', systemName));
ax  = axes(fig); %#ok<LAXES>
hold(ax, 'on');

cmap = lines(max(numel(snrVals), 1));
h    = gobjects(numel(snrVals), 1);
lbl  = cell(numel(snrVals), 1);

for k = 1:numel(snrVals)
    if isinf(snrVals(k))
        sub    = T(isinf(T.targetSnrDb), :);
        lbl{k} = 'clean';
    else
        sub    = T(T.targetSnrDb == snrVals(k), :);
        lbl{k} = sprintf('%g dB', snrVals(k));
    end

    sub = sortrows(sub, 'lengthSec');
    x   = sub.lengthSec;
    y   = 100 * sub.(opts.metric);

    if hasCI
        neg  = y - 100 * sub.(loCol);
        pos  = 100 * sub.(hiCol) - y;
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

lengths = unique(T.lengthSec);
set(ax, 'XTick', lengths);
xlim(ax, [min(lengths) - 0.5, max(lengths) + 0.5]);
ylim(ax, [0 102]);
grid(ax, 'on');
box(ax, 'on');

xlabel(ax, 'Query length (s)');
ylabel(ax, sprintf('%s (%%)', prettyMetric(opts.metric)));
title(ax, sprintf('%s vs query length - %s', prettyMetric(opts.metric), systemName));

legend(ax, h, lbl, 'Location', 'southeast');

hold(ax, 'off');

if nargout == 0
    clear fig
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
