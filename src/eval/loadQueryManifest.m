function [M, meta] = loadQueryManifest(Cfg, manifestPath)
%LOADQUERYMANIFEST Read results/queryManifest.csv back into a typed table.
%
%   M = LOADQUERYMANIFEST() reads results/queryManifest.csv and restores the
%   column types BUILDQUERYMANIFEST declared, the way LOADCATALOG does for the
%   song table.
%
%   [M, META] = LOADQUERYMANIFEST() also returns the provenance struct
%   (cfgTag, seed, grid shape, build time) that S04_BUILDQUERIES saved
%   alongside the CSV.
%
%   WHY THE .MAT EXISTS TOO. CSV is typeless. WRITETABLE flattens categoricals
%   to text, integers to decimal, and Inf to the literal "Inf"; READTABLE then
%   guesses on the way back. Two of those guesses are load-bearing here:
%
%     - targetSnrDb must come back as DOUBLE with Inf intact. Read as text, or
%       as NaN, the clean condition silently stops matching isinf() and every
%       clean row falls out of the grouping in COMPUTEMETRICS.
%     - noiseType, role and split must come back as CATEGORICAL with their
%       full category lists, so a level that happens to be absent from a
%       subset run still forms a group rather than vanishing from a summary.
%
%   S04 writes both. The .mat is authoritative and carries UserData; the CSV
%   is the human-readable, diffable, committed artifact blueprint D2 describes
%   as "a 500 KB CSV". This function makes the CSV safe to read on its own so
%   the two never disagree.
%
%   Milestone: M3.  Blueprint: section(s) 0 (D2), 2.5.
%
%   See also BUILDQUERYMANIFEST, S04_BUILDQUERIES, LOADCATALOG.

if nargin < 1 || isempty(Cfg)
    Cfg = baselineConfig();
end

projRoot = setupPaths();

if nargin < 2 || isempty(manifestPath)
    manifestPath = fullfile(projRoot, 'results', 'queryManifest.csv');
end
manifestPath = char(manifestPath);

if ~isfile(manifestPath)
    error('HimigTransform:NoQueryManifest', ...
        'No query manifest at %s.\nRun s04_buildQueries first.', manifestPath);
end

% ---- Prefer the .mat when it is present and current ---------------------
matPath = regexprep(manifestPath, '\.csv$', '.mat');
if isfile(matPath)
    S = load(matPath);
    if isfield(S, 'M') && istable(S.M)
        M = S.M;
        meta = tableMeta(M);
        return
    end
end

% ---- Otherwise rebuild the types from the CSV ---------------------------
opts = detectImportOptions(manifestPath, 'TextType', 'string');

numericCols = {'queryID', 'songID', 'lengthSec', 'startSample', 'rep', ...
               'noiseStartSample', 'targetSnrDb', 'seed'};
textCols    = {'repertoire', 'role', 'split', 'noiseType', 'noiseFile'};

for k = 1:numel(numericCols)
    if ismember(numericCols{k}, opts.VariableNames)
        opts = setvartype(opts, numericCols{k}, 'double');
    end
end
for k = 1:numel(textCols)
    if ismember(textCols{k}, opts.VariableNames)
        opts = setvartype(opts, textCols{k}, 'string');
        opts = setvaropts(opts, textCols{k}, 'FillValue', "");
    end
end

M = readtable(manifestPath, opts);

required = [numericCols, textCols];
missingCols = setdiff(required, M.Properties.VariableNames);
if ~isempty(missingCols)
    error('HimigTransform:BadQueryManifest', ...
        ['queryManifest.csv is missing column(s): %s\n' ...
         'Delete it and re-run s04_buildQueries.'], strjoin(missingCols, ', '));
end

% ---- Restore declared types ---------------------------------------------
M.queryID          = uint32(M.queryID);
M.songID           = uint16(M.songID);
M.startSample      = uint32(M.startSample);
M.rep              = uint8(M.rep);
M.noiseStartSample = uint32(M.noiseStartSample);
M.seed             = uint32(M.seed);

M.repertoire = setcats(categorical(M.repertoire), {'american', 'opm'});
M.role       = setcats(categorical(M.role),       {'db', 'holdout'});
M.split      = setcats(categorical(M.split),      {'dev', 'test'});
M.noiseType  = setcats(categorical(M.noiseType), ...
    [{'none'}, cellstr(string(Cfg.eval.noiseTypes(:)'))]);

if any(isundefined(M.noiseType))
    error('HimigTransform:BadQueryManifest', ...
        ['queryManifest.csv contains a noiseType outside {none, %s}. ' ...
         'It was built under a different Cfg.eval.noiseTypes - rebuild it.'], ...
        strjoin(cellstr(string(Cfg.eval.noiseTypes)), ', '));
end

% READTABLE renders "Inf" as Inf, but a locale or an older writer can turn it
% into NaN. That would silently drop every clean row out of isinf(), so it is
% checked rather than trusted.
if any(isnan(M.targetSnrDb))
    error('HimigTransform:BadQueryManifest', ...
        ['%d row(s) have targetSnrDb = NaN. The clean condition is written as ' ...
         'Inf and did not survive the CSV round trip - load the .mat instead, ' ...
         'or re-run s04_buildQueries.'], nnz(isnan(M.targetSnrDb)));
end

if numel(unique(M.queryID)) ~= height(M)
    error('HimigTransform:DuplicateQueryID', ...
        'queryManifest.csv has duplicate queryID values; queryID is the primary key.');
end

meta = tableMeta(M);

end

% =======================================================================
function meta = tableMeta(M)
if isstruct(M.Properties.UserData)
    meta = M.Properties.UserData;
else
    meta = struct('note', 'no provenance recorded (rebuilt from CSV)');
end
end
