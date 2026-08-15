%S05_TUNETHRESHOLDS  Choose tau and rho on the DEV split, for both systems.
%
%   Reads a dev-split results file per system, sweeps the open-set accept rule
%   and reports the chosen operating point. Writes the sweep, the ROC figure
%   and a summary you paste back into config/.
%
%   Prerequisite - run these FIRST, once per system:
%       s06_system = 'baseline'; s06_split = 'dev'; s06_runEvaluation
%       s06_system = 'enhanced'; s06_split = 'dev'; s06_runEvaluation
%
%   Then:
%       s05_tuneThresholds
%
%   Options
%       s05_farBudget   max tolerable false-accept rate (default 0.01)
%       s05_systems     {'baseline','enhanced'} by default
%
%   DEV ONLY, AND ONCE. The test split is touched exactly once, at M7. Write
%   the chosen tau and rho into config/baselineConfig.m and
%   config/enhancedConfig.m, COMMIT that change, and only then run s06 on the
%   test split. If the thresholds move after you have seen test numbers, the
%   result is no longer defensible and a panel is entitled to say so.
%
%   TWO OPERATING POINTS, NOT ONE. The enhanced system emits more hashes per
%   query, so its normScore sits on a different scale. Carrying the baseline's
%   tau across to it would make part of the measured difference a threshold
%   artefact rather than an effect of the enhancement.
%
%   Milestone: M5.  Blueprint: sections 3.5, 8.2, 8.3.
%
%   See also TUNETHRESHOLDS, PLOTOPENSETROC, DECIDEOPENSET.

projRoot = setupPaths();

if ~exist('s05_farBudget', 'var') || isempty(s05_farBudget)
    s05_farBudget = 0.01;
end
if ~exist('s05_systems', 'var') || isempty(s05_systems)
    s05_systems = {'baseline', 'enhanced'};
end

logMsg('info', '===== s05_tuneThresholds =====');
logMsg('info', 'FAR budget %.3f | systems: %s', ...
    s05_farBudget, strjoin(s05_systems, ', '));

rawDir  = fullfile(projRoot, 'results', 'raw');
outDir  = fullfile(projRoot, 'results', 'tables');
figDir  = fullfile(projRoot, 'results', 'figures');
for d = {outDir, figDir}
    if ~isfolder(d{1}), mkdir(d{1}); end
end

chosen = struct('system', {}, 'tau', {}, 'rho', {}, ...
                'recall', {}, 'precision', {}, 'far', {}, ...
                'nInDb', {}, 'nHoldout', {}, 'file', {});

for si = 1:numel(s05_systems)
    sysName = s05_systems{si};

    % ---- Find the most recent dev results for this system ---------------
    pattern = fullfile(rawDir, sprintf('results_%s_*.mat', sysName));
    files   = dir(pattern);

    if isempty(files)
        logMsg('warn', ['No results for "%s" in results/raw. Run: ' ...
            's06_system = ''%s''; s06_split = ''dev''; s06_runEvaluation'], ...
            sysName, sysName);
        continue
    end

    [~, newest] = max([files.datenum]);
    resPath = fullfile(files(newest).folder, files(newest).name);

    S = load(resPath);
    R = S.R;

    % ---- Refuse anything that is not purely dev -------------------------
    isDev = strcmp(cellstr(string(R.split)), 'dev');

    if ~any(isDev)
        logMsg('warn', '%s holds no dev rows - skipping. (%s)', sysName, files(newest).name);
        continue
    end

    if ~all(isDev)
        % A file run with s06_split = 'all' contains test rows too. Filtering
        % is safe and better than refusing, but say so loudly: the intent was
        % a dev-only run, and silently proceeding is how a habit forms.
        logMsg('warn', ...
            ['%s was run with split = ''all'' (%d of %d rows are dev). ' ...
             'Filtering to dev. Prefer s06_split = ''dev'' so the file ' ...
             'cannot be confused with a test result.'], ...
            sysName, nnz(isDev), height(R));
        R = R(isDev, :);
    end

    % ---- Confirm the file is what it claims to be -----------------------
    % systemConfig makes the label and the config agree at run time; this
    % catches a file produced before that fix.
    Cfg = systemConfig(sysName);
    fileTag = "unknown";
    if ismember('cfgTag', R.Properties.VariableNames) && height(R) > 0
        fileTag = string(R.cfgTag(1));
    end
    if fileTag ~= "unknown" && ~strcmp(char(fileTag), Cfg.tag)
        error('HimigTransform:SystemTagMismatch', ...
            ['%s claims system "%s" but carries config tag %s, while ' ...
             '%sConfig produces %s. This file was produced by a different ' ...
             'configuration than its name says - discard it and re-run.'], ...
            files(newest).name, sysName, fileTag, sysName, Cfg.tag);
    end

    % ---- Sweep ----------------------------------------------------------
    fprintf('\n===== %s =====\n', sysName);
    fprintf('  source: %s\n', files(newest).name);

    [tau, rho, sweep] = tuneThresholds(R, Cfg, 'FarBudget', s05_farBudget);

    U = sweep.Properties.UserData;
    k = U.chosenIdx;

    fprintf('\n  chosen operating point\n');
    fprintf('    tau        : %.4f   (was %.4f)\n', tau, Cfg.match.tau);
    fprintf('    rho        : %.2f     (was %.2f)\n', rho, Cfg.match.rho);
    fprintf('    recall     : %.3f\n', sweep.recall(k));
    fprintf('    precision  : %.3f\n', sweep.precision(k));
    fprintf('    FAR        : %.4f  (budget %.4f)\n', sweep.far(k), s05_farBudget);
    fprintf('    tuned on   : %g dB and above, %d in-DB / %d holdout dev queries\n', ...
        U.snrRange(1), U.nInDb, U.nHoldout);

    % ---- What the budget bought -----------------------------------------
    fprintf('\n  what other budgets would give\n');
    fprintf('%12s %10s %11s\n', 'FAR budget', 'recall', 'precision');
    for b = [0.001 0.005 0.01 0.02 0.05 0.10]
        ok = find(sweep.far <= b);
        if isempty(ok)
            fprintf('%12.3f %10s %11s\n', b, '-', '-');
            continue
        end
        [bestRec, j] = max(sweep.recall(ok));
        fprintf('%12.3f %10.3f %11.3f\n', b, bestRec, sweep.precision(ok(j)));
    end

    % ---- Persist ---------------------------------------------------------
    sweepPath = fullfile(outDir, sprintf('openSetSweep_%s.csv', sysName));
    writetable(sweep, sweepPath);

    fig     = plotOpenSetRoc(sweep, Cfg);
    figPath = fullfile(figDir, sprintf('openSetRoc_%s.png', sysName));
    exportgraphics(fig, figPath, 'Resolution', 200);
    close(fig);

    fprintf('\n  sweep  -> %s\n', sweepPath);
    fprintf('  figure -> %s\n', figPath);

    chosen(end + 1) = struct( ...
        'system',    string(sysName), ...
        'tau',       tau, ...
        'rho',       rho, ...
        'recall',    sweep.recall(k), ...
        'precision', sweep.precision(k), ...
        'far',       sweep.far(k), ...
        'nInDb',     U.nInDb, ...
        'nHoldout',  U.nHoldout, ...
        'file',      string(files(newest).name)); %#ok<SAGROW>
end

if isempty(chosen)
    error('HimigTransform:NothingTuned', ...
        'No dev results found for any system. See the prerequisites above.');
end

C = struct2table(chosen);
writetable(C, fullfile(outDir, 'openSetThresholds.csv'));

% ---- What to paste back -------------------------------------------------
fprintf('\n========================================================\n');
fprintf('PASTE THESE INTO config/, THEN COMMIT, THEN RUN THE TEST SPLIT\n');
fprintf('========================================================\n');
for ii = 1:height(C)
    fprintf('\n%% config/%sConfig.m\n', C.system(ii));
    fprintf('Cfg.match.tau = %.4f;   %% tuned on dev, s05, FAR budget %.3f\n', ...
        C.tau(ii), s05_farBudget);
    fprintf('Cfg.match.rho = %.2f;     %% dev recall %.3f, precision %.3f, FAR %.4f\n', ...
        C.rho(ii), C.recall(ii), C.precision(ii), C.far(ii));
end

fprintf('\n--- s05 exit check ---\n');
fprintf('Systems tuned           : %d\n', height(C));
fprintf('Thresholds              : %s\n', ...
    fullfile(outDir, 'openSetThresholds.csv'));
fprintf('s05_tuneThresholds: PASS\n');
fprintf(['Next: paste the values above into config/, COMMIT that change,\n' ...
         'then run s06 with s06_split = ''test'' for each system.\n' ...
         'Do not revisit the thresholds after seeing test numbers.\n']);
fprintf('---------------------\n');
