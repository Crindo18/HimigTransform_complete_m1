function [Idx, report] = enrollDatabase(catalog, Cfg, varargin)
%ENROLLDATABASE Fingerprint every in-database song and build the index.
%
%   [IDX, REPORT] = ENROLLDATABASE(CATALOG, CFG) fingerprints every row of
%   CATALOG whose role is 'db', writes the per-song fingerprint cache, and
%   calls BUILDINDEX once over the result.
%
%   Name-value options:
%       'ProcRoot'   where the processed audio lives (default data/processed)
%       'UseCache'   reuse valid cached fingerprints (default true)
%       'UseParfor'  parallelise extraction (default true)
%
%   REPORT is a per-song table: songID, action ("extracted" | "cached" |
%   "failed"), nPeaks, nHashes, densityPerSec, durationSec, elapsedSec.
%
%   HOLDOUT SONGS ARE NOT ENROLLED, by definition - they are the 20 songs the
%   open-set evaluation asks about precisely because they are absent from the
%   index. Filtering on role here rather than in the caller means no script
%   can accidentally enrol them and quietly turn the false-accept rate into a
%   measurement of nothing.
%
%   PARFOR DEGRADES CLEANLY. Without the Parallel Computing Toolbox MATLAB
%   runs parfor as a serial for, so no branch is needed. The per-song cache
%   makes the loop safe to parallelise: each iteration writes its own file and
%   nothing is shared.
%
%   ONE INDEX PER CONFIGURATION (blueprint D4). This function builds the index
%   for the CFG it is given and nothing else. The temptation is to enrol once
%   with a maximal target zone and vary only the query side, and it does not
%   work: the hash encodes dt, so a wider database zone adds retrievable
%   postings that change baseline behaviour too, contaminating the comparison
%   the whole project exists to make.
%
%   Milestone: M2.  Blueprint: sections 0 (D4), 2.3, 7 (M2).
%
%   See also EXTRACTFINGERPRINT, BUILDINDEX, SAVEFINGERPRINT.

if nargin < 2 || isempty(Cfg)
    Cfg = baselineConfig();
end

projRoot = setupPaths();

opt = parseOpts(struct( ...
    'ProcRoot',  fullfile(projRoot, 'data', 'processed'), ...
    'UseCache',  true, ...
    'UseParfor', true), varargin);

rows = catalog(catalog.role == 'db', :);
n    = height(rows);

if n == 0
    error('HimigTransform:NothingToEnrol', ...
        'No catalog rows with role = db. Check that s01_ingest ran.');
end

logMsg('info', 'Enrol: %d song(s), config tag %s.', n, Cfg.tag);

cacheDir = fingerprintCacheDir(Cfg);
if ~isfolder(cacheDir)
    mkdir(cacheDir);
end

songIDs   = double(rows.songID);
procPaths = rows.procPath;
shas      = rows.sha256;
procRoot  = opt.ProcRoot;
useCache  = opt.UseCache;

fps      = cell(n, 1);
action   = strings(n, 1);
nPeaks   = zeros(n, 1);
nHashes  = zeros(n, 1);
density  = zeros(n, 1);
durSec   = zeros(n, 1);
elapsed  = zeros(n, 1);
errMsg   = strings(n, 1);

tAll = tic;

if opt.UseParfor
    parfor k = 1:n
        [fps{k}, action(k), nPeaks(k), nHashes(k), density(k), durSec(k), ...
            elapsed(k), errMsg(k)] = ...
            enrolOne(songIDs(k), procPaths(k), shas(k), procRoot, useCache, Cfg);
    end
else
    for k = 1:n
        [fps{k}, action(k), nPeaks(k), nHashes(k), density(k), durSec(k), ...
            elapsed(k), errMsg(k)] = ...
            enrolOne(songIDs(k), procPaths(k), shas(k), procRoot, useCache, Cfg);
    end
end

extractSec = toc(tAll);

failed = action == "failed";
if any(failed)
    for k = find(failed)'
        logMsg('warn', 'Enrol: songID %d failed - %s', songIDs(k), errMsg(k));
    end
end

good = ~failed;

if ~any(good)
    error('HimigTransform:AllEnrolmentsFailed', ...
        'Every song failed to fingerprint. Check data/processed and the catalog.');
end

logMsg('info', 'Enrol: extraction done in %.1f s (%d extracted, %d cached, %d failed).', ...
    extractSec, nnz(action == "extracted"), nnz(action == "cached"), nnz(failed));

Idx = buildIndex(fps(good), songIDs(good), Cfg);

Idx.stats.extractSec = extractSec;
Idx.stats.enrolSec   = toc(tAll);

report = table(uint16(songIDs), action, nPeaks, nHashes, density, durSec, elapsed, errMsg, ...
    'VariableNames', {'songID', 'action', 'nPeaks', 'nHashes', ...
                      'densityPerSec', 'durationSec', 'elapsedSec', 'errMsg'});

logMsg('info', 'Enrol: complete in %.1f s (%.1f min).', ...
    Idx.stats.enrolSec, Idx.stats.enrolSec / 60);

end

% =======================================================================
function [fp, action, nPk, nHa, dens, durSec, elapsed, errMsg] = ...
    enrolOne(songID, procPath, sha, procRoot, useCache, Cfg)

fp = []; action = "failed"; nPk = 0; nHa = 0; dens = 0; durSec = 0; errMsg = "";
tOne = tic;

try
    if useCache
        [cached, ok] = loadFingerprint(songID, Cfg, char(sha));
        if ok
            fp      = cached;
            action  = "cached";
            nPk     = fp.meta.nPeaks;
            nHa     = fp.meta.nHashes;
            durSec  = fp.meta.durationSec;
            dens    = nPk / max(durSec, eps);
            elapsed = toc(tOne);
            return
        end
    end

    f = fullfile(procRoot, strrep(char(procPath), '/', filesep));
    if ~isfile(f)
        error('Processed file not found: %s', f);
    end

    [x, fsIn] = audioread(f);
    if fsIn ~= Cfg.audio.fs
        error('%s is %d Hz, expected %d Hz. Re-run s01_ingest.', ...
            procPath, fsIn, Cfg.audio.fs);
    end
   
    extractCfg = Cfg;
    if isfield(extractCfg, 'denoise')
        extractCfg.denoise.enable = false; 
    end
    
    fp = extractFingerprint(x(:, 1), extractCfg);
    
    fp.meta.songID = uint16(songID);
    fp.meta.sha256 = char(sha);

    saveFingerprint(fp, songID, Cfg);

    action = "extracted";
    nPk    = fp.meta.nPeaks;
    nHa    = fp.meta.nHashes;
    durSec = fp.meta.durationSec;
    dens   = nPk / max(durSec, eps);

catch ME
    errMsg = string(ME.message);
end

elapsed = toc(tOne);

end

% =======================================================================
function opt = parseOpts(opt, args)

if mod(numel(args), 2) ~= 0
    error('HimigTransform:BadOptions', 'Options must be name-value pairs.');
end

valid = fieldnames(opt);
for k = 1:2:numel(args)
    name = char(args{k});
    hit  = valid(strcmpi(valid, name));
    if isempty(hit)
        error('HimigTransform:BadOption', ...
            'Unknown option "%s". Valid: %s.', name, strjoin(valid', ', '));
    end
    opt.(hit{1}) = args{k + 1};
end

end