function ax = plotOffsetHistogram(res, Cfg, ax)
%PLOTOFFSETHISTOGRAM Time-offset histogram for the winning candidate.
%
%   AX = PLOTOFFSETHISTOGRAM(RES, CFG) draws into a new figure.
%   AX = PLOTOFFSETHISTOGRAM(RES, CFG, AX) draws into an existing axes.
%
%   RES comes from IDENTIFYQUERY. This is the most informative single frame in
%   the whole system: a correct match is ONE sharp spike, because every
%   matching hash pair shares the same alignment between query and recording.
%   A false match is a flat smear of coincidental collisions at scattered
%   offsets. The contrast is visible at a glance, which makes it both the
%   fastest way to diagnose a broken matcher and the most convincing thing to
%   show in a live demo.
%
%   Milestone: M6.  Blueprint: section 3.5.
%
%   See also IDENTIFYQUERY, ALIGNOFFSETS, PLOTCONSTELLATION.

narginchk(2, 3);

if nargin < 3 || isempty(ax)
    ax = axes('Parent', figure('Color', 'w'));
end

cla(ax, 'reset');

if isempty(res.offsetHist) || ~any(res.offsetHist)
    title(ax, 'No hash collisions');
    xlabel(ax, 'Reference minus query offset (s)');
    ylabel(ax, 'Matching hashes');
    return
end


% identifyQuery returns the offset axis explicitly as res.offsetFrames
% rather than a shift, so use it directly.
offsetSec = double(res.offsetFrames(:)) / Cfg.derived.frameRate;

bar(ax, offsetSec, double(res.offsetHist(:)), 1, ...
    'FaceColor', [0.25 0.45 0.75], 'EdgeColor', 'none');

if isfield(res, 'bestOffsetSec') && ~isnan(res.bestOffsetSec)
    hold(ax, 'on');
    plot(ax, res.bestOffsetSec, res.score1, 'v', ...
        'MarkerSize', 8, 'MarkerFaceColor', [0.95 0.65 0.10], ...
        'MarkerEdgeColor', [0.35 0.22 0.02]);
    hold(ax, 'off');
end

xlabel(ax, 'Reference minus query offset (s)');
ylabel(ax, 'Matching hashes');
grid(ax, 'on');

title(ax, sprintf('Song %d - peak %d hashes, margin %.1f', ...
    res.pred1, res.score1, res.margin));

end
