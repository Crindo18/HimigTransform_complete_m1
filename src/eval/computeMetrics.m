function T = computeMetrics(R, groupVars, alpha)
%COMPUTEMETRICS Blueprint 8.3 metrics with Wilson intervals, per group.
%
%   T = COMPUTEMETRICS(R, GROUPVARS) summarises the long-format results table
%   R by the grouping columns GROUPVARS (a cellstr or string array, e.g.
%   {'system','lengthSec','targetSnrDb'}), returning one row per group with:
%
%       nQueries, nInDb, nHoldout, nAccepted
%       closedSetAcc      pred1 == songID over IN-DB queries, threshold ignored
%       operationalAcc    correct AND accepted, over IN-DB queries
%       precision         correct-and-accepted / all accepted
%       recall            correct-and-accepted / all IN-DB queries
%       far               accepted holdout / all holdout queries
%       *Lo / *Hi         Wilson 95% bounds for each of the five above
%       tMatchMedian, tMatchP95, tTotalMedian, tTotalP95
%
%   T = COMPUTEMETRICS(R, GROUPVARS, ALPHA) sets the interval level.
%
%   THE DENOMINATORS ARE THE WHOLE POINT. Blueprint 8.3 defines each of these
%   over a different population, and getting one wrong produces a number that
%   looks reasonable and is not:
%
%     - closed-set accuracy and recall are over IN-DB queries. Holdout queries
%       can never be "correct" (their song is deliberately absent from the
%       index), so leaving them in the denominator drags every accuracy down
%       by the holdout share and makes the system look worse the more
%       thoroughly its open-set behaviour is tested.
%     - precision divides by ALL accepted queries, holdout included. That
%       wrongly-accepted term is the only thing that makes precision differ
%       from recall; drop it and, as blueprint 12.3 warns, precision = recall
%       = accuracy and the metric is vacuous.
%     - FAR is over holdout queries only.
%
%   TIMING EXCLUDES WARM-UP. Blueprint 6.3: the first calls measure MATLAB's
%   JIT. RUNEXPERIMENT flags them; they are dropped here, from the timing
%   columns only, never from the accuracy counts.
%
%   Milestone: M3.  Blueprint: section(s) 8.3, 8.4, 6.3.
%
%   See also RUNEXPERIMENT, WILSONINTERVAL, PLOTACCURACYVSSNR.

if nargin < 2 || isempty(groupVars)
    groupVars = {'system', 'lengthSec', 'targetSnrDb'};
end
if nargin < 3 || isempty(alpha)
    alpha = 0.05;
end

% Force a ROW cell: cellstr of a column string returns a column, and
% concatenating that with the row cells used for the column order below
% would error on a caller who happened to pass a column.
groupVars = reshape(cellstr(string(groupVars)), 1, []);

missingCols = setdiff(groupVars, R.Properties.VariableNames);
if ~isempty(missingCols)
    error('HimigTransform:BadGroupVars', ...
        'Results table has no column(s): %s', strjoin(missingCols, ', '));
end

required = {'isInDb', 'correct', 'accepted', 'normScore', 'margin'};
missingCols = setdiff(required, R.Properties.VariableNames);
if ~isempty(missingCols)
    error('HimigTransform:BadResultsTable', ...
        ['Results table is missing %s. It looks like it came from an older ' ...
         'RUNEXPERIMENT - re-run the grid.'], strjoin(missingCols, ', '));
end

[G, T] = findgroups(R(:, groupVars));
nG     = height(T);

nQueries   = zeros(nG, 1);
nInDb      = zeros(nG, 1);
nHoldout   = zeros(nG, 1);
nAccepted  = zeros(nG, 1);
nCorrect   = zeros(nG, 1);
nCorrAcc   = zeros(nG, 1);
nHoldAcc   = zeros(nG, 1);

tMatchMedian = nan(nG, 1);
tMatchP95    = nan(nG, 1);
tTotalMedian = nan(nG, 1);
tTotalP95    = nan(nG, 1);

normScoreMedian = nan(nG, 1);
normScoreP05    = nan(nG, 1);
marginMedian    = nan(nG, 1);
marginMin       = nan(nG, 1);

hasTiming = all(ismember({'tMatchSec', 'tTotalSec'}, R.Properties.VariableNames));
hasWarmup = ismember('warmup', R.Properties.VariableNames);

for g = 1:nG
    m = (G == g);

    inDb    = m & R.isInDb;
    holdout = m & ~R.isInDb;

    nQueries(g)  = nnz(m);
    nInDb(g)     = nnz(inDb);
    nHoldout(g)  = nnz(holdout);
    nAccepted(g) = nnz(m & R.accepted);

    nCorrect(g)  = nnz(inDb & R.correct);
    nCorrAcc(g)  = nnz(inDb & R.correct & R.accepted);
    nHoldAcc(g)  = nnz(holdout & R.accepted);

    % ---- Decision margin, over in-DB queries only -----------------------
    % normScore degrades continuously where accuracy saturates. On a
    % 100-song database a 3 s query at 0 dB still identifies correctly
    % essentially always, because a dozen surviving hashes beat 99 rivals
    % contributing one or two chance collisions each - so top-1 stays at
    % 100% while the fingerprint is in fact being destroyed (peak survival
    % at 0 dB measures around 12%).
    %
    % That makes accuracy the wrong dependent variable at this database
    % size, and normScore the right one: it is the headroom the decision
    % has left, it is precisely what Enhancement 1 protects, and it is
    % measurable at the SNRs the proposal names. Reported here so the
    % effect can be quoted even from a saturated accuracy table.
    if any(inDb)
        normScoreMedian(g) = median(R.normScore(inDb));
        normScoreP05(g)    = prctile05(R.normScore(inDb));
        marginMedian(g)    = median(R.margin(inDb));
        marginMin(g)       = min(R.margin(inDb));
    end

    if hasTiming
        if hasWarmup
            tm = m & ~R.warmup;
        else
            tm = m;
        end
        if any(tm)
            tMatchMedian(g) = median(R.tMatchSec(tm));
            tMatchP95(g)    = prctile95(R.tMatchSec(tm));
            tTotalMedian(g) = median(R.tTotalSec(tm));
            tTotalP95(g)    = prctile95(R.tTotalSec(tm));
        end
    end
end

T.nQueries  = nQueries;
T.nInDb     = nInDb;
T.nHoldout  = nHoldout;
T.nAccepted = nAccepted;

% ---- The five metrics, each over its own population ---------------------
% Explicit temporaries rather than [T.a, T.b, T.c] = wilsonInterval(...):
% multi-output assignment through table dot-indexing is fragile across
% releases, and this reads more plainly anyway.
[csLo, csHi, csP] = wilsonInterval(nCorrect,  nInDb,     alpha);
[opLo, opHi, opP] = wilsonInterval(nCorrAcc,  nInDb,     alpha);
[prLo, prHi, prP] = wilsonInterval(nCorrAcc,  nAccepted, alpha);
[rcLo, rcHi, rcP] = wilsonInterval(nCorrAcc,  nInDb,     alpha);
[faLo, faHi, faP] = wilsonInterval(nHoldAcc,  nHoldout,  alpha);

T.closedSetAcc      = csP;  T.closedSetAccLo   = csLo;  T.closedSetAccHi   = csHi;
T.operationalAcc    = opP;  T.operationalAccLo = opLo;  T.operationalAccHi = opHi;
T.precision         = prP;  T.precisionLo      = prLo;  T.precisionHi      = prHi;
T.recall            = rcP;  T.recallLo         = rcLo;  T.recallHi         = rcHi;
T.far               = faP;  T.farLo            = faLo;  T.farHi            = faHi;

T.normScoreMedian = normScoreMedian;
T.normScoreP05    = normScoreP05;
T.marginMedian    = marginMedian;
T.marginMin       = marginMin;

T.tMatchMedian = tMatchMedian;
T.tMatchP95    = tMatchP95;
T.tTotalMedian = tTotalMedian;
T.tTotalP95    = tTotalP95;

% ---- Column order: keys, n, then metric with its bounds adjacent --------
metricOrder = {'closedSetAcc', 'closedSetAccLo', 'closedSetAccHi', ...
               'operationalAcc', 'operationalAccLo', 'operationalAccHi', ...
               'precision', 'precisionLo', 'precisionHi', ...
               'recall', 'recallLo', 'recallHi', ...
               'far', 'farLo', 'farHi', ...
               'normScoreMedian', 'normScoreP05', ...
               'marginMedian', 'marginMin', ...
               'tMatchMedian', 'tMatchP95', 'tTotalMedian', 'tTotalP95'};
T = T(:, [groupVars, {'nQueries', 'nInDb', 'nHoldout', 'nAccepted'}, metricOrder]);

T.Properties.UserData = struct( ...
    'alpha',     alpha, ...
    'groupVars', {groupVars}, ...
    'source',    resultsProvenance(R), ...
    'builtOn',   datetime('now'));

end

% =======================================================================
function v = prctile05(x)
%PRCTILE05 5th percentile without Statistics Toolbox. Mirrors PRCTILE95.

x = sort(x(:));
if isempty(x)
    v = NaN;
    return
end
v = x(max(1, ceil(0.05 * numel(x))));

end

% =======================================================================
function v = prctile95(x)
%PRCTILE95 95th percentile without the Statistics Toolbox (blueprint 1.2).
x = sort(x(:));
n = numel(x);
if n == 0
    v = NaN;
    return
end
if n == 1
    v = x;
    return
end
% Linear interpolation on the same convention PRCTILE uses.
pos = 0.95 * n + 0.5;
pos = min(max(pos, 1), n);
lo  = floor(pos);
hi  = ceil(pos);
if lo == hi
    v = x(lo);
else
    v = x(lo) + (pos - lo) * (x(hi) - x(lo));
end
end

% =======================================================================
function s = resultsProvenance(R)
if isstruct(R.Properties.UserData)
    s = R.Properties.UserData;
else
    s = struct();
end
end
