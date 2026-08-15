%S07_MAKEFIGURES  Regenerate every figure from the newest results file.
%
%   Finds the most recent results/raw/results_<system>_*.mat, computes the
%   metrics, and writes the figures to results/figures/ as both .png (for
%   drafts) and .fig (so a figure can be reopened and adjusted without a
%   re-run).
%
%   Configure with variables set BEFORE running (all optional):
%
%       s07_system    'baseline' (default)
%       s07_resultsFile   explicit path, overriding "newest"
%
%   UNATTENDED IS THE POINT. Blueprint 7 (M3) gates on these two plots
%   generating from the results table without intervention, and 7 (M7) says
%   every figure in the paper is produced by script - no hand-made plots.
%   A figure you touched by hand is a figure you cannot regenerate when a
%   number changes in week 10, and something always changes in week 10.
%
%   NO FIGURE IS DRAWN FROM A DIFFERENT RUN THAN THE TABLE BESIDE IT. The
%   results file records its Cfg, git commit and timestamp; those are stamped
%   into the figure filenames so a plot in the paper can always be traced back
%   to the run that produced it (blueprint 6.4).
%
%   Milestone: M3 (the two accuracy figures), M7 (the rest).
%   Blueprint: sections 6.4, 7 (M3, M7), 8.3, 8.4.
%
%   Usage:
%       setupPaths;
%       s07_makeFigures

projRoot = setupPaths();

if ~exist('s07_system', 'var') || isempty(s07_system), s07_system = 'baseline'; end
if ~exist('s07_resultsFile', 'var'),                   s07_resultsFile = '';    end

logMsg('info', '===== s07_makeFigures =====');

figDir = fullfile(projRoot, 'results', 'figures');
if ~isfolder(figDir), mkdir(figDir); end

% =======================================================================
% 1. Locate the results
% =======================================================================
if isempty(s07_resultsFile)
    pattern = fullfile(projRoot, 'results', 'raw', ...
        sprintf('results_%s_*.mat', s07_system));
    files = dir(pattern);
    if isempty(files)
        error('HimigTransform:NoResults', ...
            'No results matching %s.\nRun s06_runEvaluation first.', pattern);
    end
    [~, newest]     = max([files.datenum]);
    s07_resultsFile = fullfile(files(newest).folder, files(newest).name);
end

S = load(s07_resultsFile, 'R');
R = S.R;

meta = R.Properties.UserData;
if isstruct(meta) && isfield(meta, 'gitCommit')
    logMsg('info', 'Results: %s (commit %s, %d rows)', ...
        s07_resultsFile, meta.gitCommit, height(R));
else
    logMsg('info', 'Results: %s (%d rows)', s07_resultsFile, height(R));
end

[~, stem] = fileparts(s07_resultsFile);

% =======================================================================
% 2. Metrics
% =======================================================================
T = computeMetrics(R, {'lengthSec', 'targetSnrDb'});

tablePath = fullfile(projRoot, 'results', 'tables', sprintf('metrics_%s.csv', stem));
writetable(T, tablePath);
logMsg('info', 'Metrics table: %s', tablePath);

% =======================================================================
% 3. Figures
% =======================================================================
figs = struct('name', {}, 'handle', {});

f = plotAccuracyVsSnr(T, s07_system);
figs(end + 1) = struct('name', 'accuracyVsSnr', 'handle', f);

f = plotAccuracyVsLength(T, s07_system);
figs(end + 1) = struct('name', 'accuracyVsLength', 'handle', f);

% Per-repertoire, because the American/OPM split is the paper's novelty claim
% (blueprint 8.3: "Report all of these split by repertoire") and it is the one
% figure nobody else has produced for this corpus.
if numel(unique(R.repertoire)) > 1
    Trep = computeMetrics(R, {'repertoire', 'lengthSec', 'targetSnrDb'});
    for rep = unique(Trep.repertoire)'
        sub = Trep(Trep.repertoire == rep, :);
        f = plotAccuracyVsSnr(sub, sprintf('%s - %s', s07_system, char(rep)));
        figs(end + 1) = struct('name', sprintf('accuracyVsSnr_%s', char(rep)), ...
            'handle', f); %#ok<SAGROW>
    end

    writetable(Trep, fullfile(projRoot, 'results', 'tables', ...
        sprintf('metricsByRepertoire_%s.csv', stem)));
end

% =======================================================================
% 4. Save
% =======================================================================
for k = 1:numel(figs)
    base = fullfile(figDir, sprintf('%s_%s', figs(k).name, stem));
    exportgraphics(figs(k).handle, [base '.png'], 'Resolution', 200);
    savefig(figs(k).handle, [base '.fig']);
    close(figs(k).handle);
end

fprintf('\n--- s07 figures ---\n');
for k = 1:numel(figs)
    fprintf('  %s\n', fullfile(figDir, sprintf('%s_%s.png', figs(k).name, stem)));
end

fprintf('\n--- Still to come (later milestones) ---\n');
fprintf('  plotPeakDensityVsSnr    M4 - the mechanism figure\n');
fprintf('  plotOpenSetRoc          M5 - needs tau/rho tuned on dev\n');
fprintf('  plotRepertoireConfusion M7\n');
fprintf('s07_makeFigures: PASS\n');
fprintf('---------------------\n');