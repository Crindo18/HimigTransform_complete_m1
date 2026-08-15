%S08_COMPARESYSTEMS  Paired comparison of two systems, cell by cell.
%
%   Loads two results files, aligns them BY QUERYID, and runs an exact
%   McNemar test in every (length, SNR) cell. Writes the comparison table and
%   prints the cells where the difference is significant.
%
%   Usage
%       s08_a = 'baseline'; s08_b = 'enhanced'; s08_compareSystems
%       s08_a = 'baseline'; s08_b = 'enh1';     s08_compareSystems
%
%   Options
%       s08_split   which split the files must carry (default 'test')
%       s08_alpha   significance level (default 0.05)
%
%   WHY PAIRED, PER CELL.
%
%   Both systems answered the same queries - same excerpt, same noise
%   segment, same SNR - because the manifest fixes all of that before either
%   runs. Comparing two accuracy figures with their Wilson intervals throws
%   that away: at n = 720 the half-width is around 3 pp, so two intervals
%   overlap while the paired difference is unambiguous either way. Overlapping
%   error bars are not evidence of no difference.
%
%   Per cell, not pooled, because a pooled p-value depends on how many cells
%   of each kind the grid happens to contain.
%
%   READ THE SIGN, NOT JUST THE STARS. A significant result here can be a
%   significant REGRESSION. That is a finding, not a failure of the run.
%
%   Milestone: M7.  Blueprint: sections 8.3, 8.4.
%
%   See also MCNEMARTEST, COMPUTEMETRICS, S06_RUNEVALUATION.

projRoot = setupPaths();

if ~exist('s08_a', 'var') || isempty(s08_a), s08_a = 'baseline'; end
if ~exist('s08_b', 'var') || isempty(s08_b), s08_b = 'enhanced'; end
if ~exist('s08_split', 'var') || isempty(s08_split), s08_split = 'test'; end
if ~exist('s08_alpha', 'var') || isempty(s08_alpha), s08_alpha = 0.05; end

logMsg('info', '===== s08_compareSystems =====');
logMsg('info', '%s vs %s | split %s | alpha %.3f', s08_a, s08_b, s08_split, s08_alpha);

RA = loadLatestResults(projRoot, s08_a, s08_split);
RB = loadLatestResults(projRoot, s08_b, s08_split);

% ---- Align by queryID ---------------------------------------------------
% Alignment is the whole basis of the test. Do not assume the two files came
% out in the same order - a subset run, a parfor, or a re-run with a different
% split filter all break that assumption silently.
[common, ia, ib] = intersect(RA.queryID, RB.queryID, 'stable');

if isempty(common)
    error('HimigTransform:NoCommonQueries', ...
        'The two result files share no queryID. Were they built from the same manifest?');
end

if numel(common) < height(RA) || numel(common) < height(RB)
    logMsg('warn', ...
        ['Only %d queries are common to both files (%s has %d, %s has %d). ' ...
         'Comparing the intersection.'], ...
        numel(common), s08_a, height(RA), s08_b, height(RB));
end

A = RA(ia, :);
B = RB(ib, :);

if ~isequal(A.queryID, B.queryID)
    error('HimigTransform:AlignmentFailed', ...
        'queryID alignment failed after intersect - do not proceed.');
end

% ---- Per-cell McNemar ---------------------------------------------------
lengths = unique(A.lengthSec);
snrs    = unique(A.targetSnrDb, 'stable');
snrs    = sort(snrs, 'descend');

rows = {};

for li = 1:numel(lengths)
    for si = 1:numel(snrs)
        m = A.lengthSec == lengths(li) & A.targetSnrDb == snrs(si) & A.isInDb;
        if ~any(m), continue, end

        cA = logical(A.correct(m));
        cB = logical(B.correct(m));

        [p, st] = mcnemarTest(cA, cB, s08_alpha);

        rows{end+1} = struct( ...
            'lengthSec', lengths(li), ...
            'snrDb',     snrs(si), ...
            'n',         st.n, ...
            'accA',      st.accA, ...
            'accB',      st.accB, ...
            'diffPp',    100 * st.diff, ...
            'diffLoPp',  100 * st.diffLo, ...
            'diffHiPp',  100 * st.diffHi, ...
            'bOnlyA',    st.b, ...
            'cOnlyB',    st.c, ...
            'p',         p, ...
            'significant', st.significant); %#ok<SAGROW>
    end
end

T = struct2table([rows{:}]);

% ---- Report -------------------------------------------------------------
fprintf('\n--- %s (A) vs %s (B), paired McNemar, %s split ---\n', ...
    s08_a, s08_b, s08_split);
fprintf('%7s %7s %6s %8s %8s %9s %7s %7s %10s %s\n', ...
    'len', 'SNR', 'n', 'A %', 'B %', 'B-A pp', 'A only', 'B only', 'p', '');

for ii = 1:height(T)
    if isinf(T.snrDb(ii)) && T.snrDb(ii) > 0
        snrLabel = 'clean';
    else
        snrLabel = sprintf('%.0f', T.snrDb(ii));
    end

    if ~T.significant(ii)
        mark = '';
    elseif T.diffPp(ii) > 0
        mark = '  *  B better';
    else
        mark = '  *  B WORSE';
    end

    fprintf('%6.0fs %7s %6d %8.1f %8.1f %+9.1f %7d %7d %10.4f%s\n', ...
        T.lengthSec(ii), snrLabel, T.n(ii), ...
        100 * T.accA(ii), 100 * T.accB(ii), T.diffPp(ii), ...
        T.bOnlyA(ii), T.cOnlyB(ii), T.p(ii), mark);
end

% ---- Verdict ------------------------------------------------------------
sig    = T(T.significant, :);
better = sig(sig.diffPp > 0, :);
worse  = sig(sig.diffPp < 0, :);

fprintf('\n--- Verdict (alpha = %.3f, %d cells) ---\n', s08_alpha, height(T));
fprintf('  significant improvements : %d\n', height(better));
fprintf('  significant regressions  : %d\n', height(worse));
fprintf('  no significant difference: %d\n', height(T) - height(sig));

if ~isempty(better)
    [~, k] = max(better.diffPp);
    fprintf('\n  largest improvement: %+.1f pp at %g s, %g dB (p = %.4f)\n', ...
        better.diffPp(k), better.lengthSec(k), better.snrDb(k), better.p(k));
end
if ~isempty(worse)
    [~, k] = min(worse.diffPp);
    fprintf('  largest regression : %+.1f pp at %g s, %g dB (p = %.4f)\n', ...
        worse.diffPp(k), worse.lengthSec(k), worse.snrDb(k), worse.p(k));
end

% Criterion 1 needs a >= 10 pp gain. Say plainly whether any cell delivers it.
crit = T(T.diffPp >= 10 & T.significant, :);
fprintf('\n  cells with a significant gain of 10 pp or more: %d\n', height(crit));
if isempty(crit)
    fprintf(['  Success criterion 1 is NOT met anywhere on this grid. Report\n' ...
             '  that as the measured outcome and explain it - a negative\n' ...
             '  result that is properly attributed is a contribution; an\n' ...
             '  unexplained one is not. Run the enh1 / enh2 ablations to say\n' ...
             '  WHICH component costs what.\n']);
end

outDir = fullfile(projRoot, 'results', 'tables');
if ~isfolder(outDir), mkdir(outDir); end
outPath = fullfile(outDir, sprintf('compare_%s_vs_%s_%s.csv', s08_a, s08_b, s08_split));
writetable(T, outPath);

fprintf('\nWritten to %s\n', outPath);
fprintf('s08_compareSystems: PASS\n');
fprintf('---------------------\n');

% =======================================================================
function R = loadLatestResults(projRoot, sysName, wantSplit)
%LOADLATESTRESULTS Newest results .mat for a system, checked against its label.

files = dir(fullfile(projRoot, 'results', 'raw', sprintf('results_%s_*.mat', sysName)));

if isempty(files)
    error('HimigTransform:NoResults', ...
        'No results for "%s". Run s06 with s06_system = ''%s''.', sysName, sysName);
end

[~, newest] = max([files.datenum]);
S = load(fullfile(files(newest).folder, files(newest).name));
R = S.R;

% The label must match the config that produced it. systemConfig ties the two
% at run time; this catches a file written before that fix.
Cfg = systemConfig(sysName);
if ismember('cfgTag', R.Properties.VariableNames) && height(R) > 0
    if ~strcmp(char(string(R.cfgTag(1))), Cfg.tag)
        error('HimigTransform:SystemTagMismatch', ...
            ['%s is named "%s" but carries config tag %s, while %s produces ' ...
             '%s. Discard it and re-run - a mislabelled file makes this ' ...
             'comparison meaningless in a way nothing downstream can detect.'], ...
            files(newest).name, sysName, string(R.cfgTag(1)), sysName, Cfg.tag);
    end
end

isWanted = strcmp(cellstr(string(R.split)), wantSplit);
if ~all(isWanted)
    if ~any(isWanted)
        error('HimigTransform:WrongSplit', ...
            '%s holds no "%s" rows.', files(newest).name, wantSplit);
    end
    logMsg('warn', '%s: filtering %d of %d rows to split "%s".', ...
        files(newest).name, nnz(isWanted), height(R), wantSplit);
    R = R(isWanted, :);
end

logMsg('info', '%-9s <- %s (%d rows)', sysName, files(newest).name, height(R));

end
