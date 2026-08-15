function [tau, rho, sweep] = tuneThresholds(Rdev, Cfg, varargin)
%TUNETHRESHOLDS Choose the open-set thresholds on the DEV split only.
%
%   [TAU, RHO, SWEEP] = TUNETHRESHOLDS(RDEV, CFG) sweeps the accept rule
%
%       accept  iff  normScore >= tau  AND  margin >= rho
%
%   over a 2-D grid and returns the chosen operating point plus the whole
%   sweep for PLOTOPENSETROC.
%
%   Options (name/value)
%       'FarBudget'   max tolerable false-accept rate (default Cfg.match.farBudget
%                     if present, else 0.01)
%       'SnrRange'    [lo hi] dB of dev rows to tune on (default
%                     Cfg.match.tuneSnrDb if present, else the proposal's
%                     clean/10/5/0 envelope)
%       'Objective'   'recallAtFar' (default) | 'f1'
%
%   THE TEST SPLIT IS TOUCHED EXACTLY ONCE, AT M7. Tuning a threshold on the
%   data you then report is the most common way a project like this produces a
%   number it cannot defend at the panel. This function refuses any row whose
%   split is not "dev".
%
%   WHY THE DEFAULT OBJECTIVE IS RECALL AT A FIXED FAR, NOT ACCURACY.
%
%   A music identifier's two failure modes are not equally bad. Returning "no
%   match" costs the user a retry; confidently naming the wrong song is a
%   wrong answer that looks right, and for the royalty-tracking use case in
%   the proposal it is a misattributed payment. Shazam's product behaviour is
%   the same: it would rather say nothing. So the threshold is chosen to
%   maximise how much the system correctly identifies SUBJECT TO a false-accept
%   budget, rather than to maximise a single blended score that would happily
%   trade a wrong answer for two right ones.
%
%   Report the budget you chose. It is a design decision, not a fact about the
%   data, and the ROC curve shows what the other choices would have bought.
%
%   WHY THE SNR RANGE IS RESTRICTED BY DEFAULT.
%
%   tau and rho are ONE global operating point applied to every query. Tuning
%   them over a grid that runs to -25 dB optimises against queries that no
%   configuration can identify, and the resulting threshold is then a function
%   of how many unidentifiable cells the grid happens to contain rather than
%   of the system. That is the same grid-composition artefact that makes
%   pooled recall meaningless (see s06_runEvaluation).
%
%   The default range is the operating envelope the proposal actually claims -
%   clean, 10, 5 and 0 dB. The extended rows still get REPORTED at the chosen
%   threshold; they are simply not allowed to choose it. Widen SnrRange if the
%   paper claims a wider envelope, and say in the text which range was used.
%
%   TUNE ONCE PER SYSTEM. The enhanced system emits more hashes per query, so
%   normScore is on a different scale; reusing the baseline's tau on it is the
%   easiest way to report a difference that is really a threshold artefact.
%   S05_TUNETHRESHOLDS does both and writes both.
%
%   Milestone: M5.  Blueprint: sections 3.5, 8.2, 8.3.
%
%   See also DECIDEOPENSET, PLOTOPENSETROC, COMPUTEMETRICS.

narginchk(2, Inf);

opt = parseOpts(Cfg, varargin{:});

% ---- Guard the split ----------------------------------------------------
required = {'split', 'isInDb', 'correct', 'normScore', 'margin', 'targetSnrDb'};
missing  = setdiff(required, Rdev.Properties.VariableNames);
if ~isempty(missing)
    error('HimigTransform:MissingColumns', ...
        'Rdev is missing: %s', strjoin(missing, ', '));
end

% strcmp on cellstr rather than string-array ==, so this behaves the same
% whether split arrived as a categorical, a string array or a cell array of
% char - which depends on how the CSV was read.
isDev = strcmp(cellstr(string(Rdev.split)), 'dev');
if ~all(isDev)
    error('HimigTransform:NotDevSplit', ...
        ['%d of %d rows are not from the dev split. Thresholds must be ' ...
         'tuned on dev only - run s06 with s06_split = ''dev'' and pass ' ...
         'that result here.'], nnz(~isDev), height(Rdev));
end

% ---- Restrict to the tuning envelope ------------------------------------
inRange = Rdev.targetSnrDb >= opt.SnrRange(1) & Rdev.targetSnrDb <= opt.SnrRange(2);
R = Rdev(inRange, :);

if isempty(R)
    error('HimigTransform:EmptyTuningSet', ...
        'No dev rows within SnrRange [%g %g] dB.', opt.SnrRange(1), opt.SnrRange(2));
end

inDb    = logical(R.isInDb);
correct = logical(R.correct);
ns      = double(R.normScore);
mg      = double(R.margin);

nInDb    = nnz(inDb);
nHoldout = nnz(~inDb);

if nHoldout == 0
    error('HimigTransform:NoHoldout', ...
        ['No holdout queries in the tuning set, so FAR cannot be measured ' ...
         'and an open-set threshold cannot be chosen. Check that the 20 ' ...
         'holdout songs carry split = dev rows.']);
end

% ---- Candidate grid -----------------------------------------------------
% tau candidates come from the observed normScore distribution rather than a
% fixed ladder, so the grid adapts to whichever system is being tuned - the
% enhanced system's normScore lives on a different scale.
tauGrid = uniqueSorted([0; quantileNoStats(ns, linspace(0, 0.999, opt.NTau)')]);
rhoGrid = opt.RhoGrid(:);

nT = numel(tauGrid);
nR = numel(rhoGrid);

[tauM, rhoM] = meshgrid(tauGrid, rhoGrid);
tauM = tauM(:);
rhoM = rhoM(:);
nCell = numel(tauM);

tp        = zeros(nCell, 1);   % in-DB, correct, accepted
acceptedN = zeros(nCell, 1);   % all accepted
falseAcc  = zeros(nCell, 1);   % holdout accepted

for k = 1:nCell
    acc = (ns >= tauM(k)) & (mg >= rhoM(k));
    tp(k)        = nnz(acc & inDb & correct);
    acceptedN(k) = nnz(acc);
    falseAcc(k)  = nnz(acc & ~inDb);
end

precision = tp ./ max(acceptedN, 1);
recall    = tp ./ nInDb;
far       = falseAcc ./ nHoldout;
f1        = 2 * precision .* recall ./ max(precision + recall, eps);

sweep = table(tauM, rhoM, precision, recall, far, f1, ...
    tp, acceptedN, falseAcc, ...
    'VariableNames', {'tau', 'rho', 'precision', 'recall', 'far', 'f1', ...
                      'tp', 'nAccepted', 'nFalseAccept'});

sweep.Properties.UserData = struct( ...
    'nInDb',     nInDb, ...
    'nHoldout',  nHoldout, ...
    'snrRange',  opt.SnrRange, ...
    'farBudget', opt.FarBudget, ...
    'objective', string(opt.Objective), ...
    'system',    resultSystem(Rdev));

% ---- Choose ------------------------------------------------------------
switch lower(opt.Objective)
    case 'recallatfar'
        feasible = find(far <= opt.FarBudget);

        if isempty(feasible)
            [~, best] = min(far);
            warning('HimigTransform:FarBudgetUnreachable', ...
                ['No (tau, rho) reaches FAR <= %.3f on dev; the lowest ' ...
                 'achievable is %.3f. Falling back to that point. Either ' ...
                 'raise the budget and say so in the paper, or accept that ' ...
                 'this system cannot separate holdout from in-DB queries at ' ...
                 'the requested rate.'], opt.FarBudget, far(best));
        else
            % Max recall; ties broken by precision, then by the least
            % aggressive threshold so the operating point is not perched on
            % the edge of a cliff in the sweep.
            sub = sortrows([-recall(feasible), -precision(feasible), ...
                            tauM(feasible), rhoM(feasible), feasible]);
            best = sub(1, end);
        end

    case 'f1'
        [~, best] = max(f1);

    otherwise
        error('HimigTransform:BadObjective', ...
            'Unknown Objective "%s" (expected recallAtFar or f1).', opt.Objective);
end

tau = tauM(best);
rho = rhoM(best);

sweep.Properties.UserData.chosenIdx = best;
sweep.Properties.UserData.tau       = tau;
sweep.Properties.UserData.rho       = rho;

logMsg('info', ...
    ['tuneThresholds: tau = %.4f, rho = %.2f  ->  recall %.3f, precision ' ...
     '%.3f, FAR %.3f  (dev, %g..%g dB, n = %d in-DB / %d holdout).'], ...
    tau, rho, recall(best), precision(best), far(best), ...
    opt.SnrRange(1), opt.SnrRange(2), nInDb, nHoldout);

end

% =======================================================================
function opt = parseOpts(Cfg, varargin)

if isfield(Cfg.match, 'farBudget')
    defFar = Cfg.match.farBudget;
else
    defFar = 0.01;
end

if isfield(Cfg.match, 'tuneSnrDb') && ~isempty(Cfg.match.tuneSnrDb)
    r = Cfg.match.tuneSnrDb;
    defRange = [min(r(~isinf(r))), Inf];
else
    % The proposal's declared envelope: clean, 10, 5 and 0 dB.
    defRange = [0, Inf];
end

opt = struct( ...
    'FarBudget', defFar, ...
    'SnrRange',  defRange, ...
    'Objective', 'recallAtFar', ...
    'NTau',      120, ...
    'RhoGrid',   [1 1.1 1.25 1.5 1.75 2 2.5 3 4 5 7 10]);

for k = 1:2:numel(varargin)
    name = varargin{k};
    if ~isfield(opt, name)
        error('HimigTransform:BadOption', 'Unknown option "%s".', name);
    end
    opt.(name) = varargin{k + 1};
end

if numel(opt.SnrRange) ~= 2 || opt.SnrRange(1) > opt.SnrRange(2)
    error('HimigTransform:BadOption', 'SnrRange must be [lo hi] with lo <= hi.');
end

end

% =======================================================================
function v = uniqueSorted(x)

v = unique(x(:));
v = v(isfinite(v));

end

% =======================================================================
function q = quantileNoStats(x, p)
%QUANTILENOSTATS Linear-interpolated quantiles without Statistics Toolbox.

x = sort(double(x(:)));
n = numel(x);

if n == 0
    q = nan(size(p));
    return
end

pos = max(1, min(n, p(:) * n + 0.5));
lo  = floor(pos);
hi  = ceil(pos);
w   = pos - lo;

q = (1 - w) .* x(lo) + w .* x(hi);

end

% =======================================================================
function s = resultSystem(R)

if ismember('system', R.Properties.VariableNames) && height(R) > 0
    s = string(R.system(1));
else
    s = "unknown";
end

end
