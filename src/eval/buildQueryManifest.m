function M = buildQueryManifest(catalog, Cfg)
%BUILDQUERYMANIFEST Deterministic query table for the whole evaluation grid.
%
%   M = BUILDQUERYMANIFEST(CATALOG, CFG) returns the table of blueprint 2.5.
%   No waveforms are written: SYNTHESIZEQUERY regenerates each one from its
%   row on demand (blueprint D2).
%
%   Grid, per song, per query length, per replicate:
%       1 clean condition + numel(noiseTypes) x nFiniteSnr noisy conditions
%   Every song in the catalog is queried, holdout included.
%
%   THE PAIRING INVARIANTS, AND WHY THERE ARE TWO
%
%   (a) startSample is drawn ONCE per (songID, lengthSec, rep) and reused
%       across every noise condition. This is what blueprint 2.5 states, and
%       it is what licenses McNemar in 8.4: baseline and enhanced read the
%       same manifest, so they hear the same excerpt under the same noise and
%       the discordant-pair count means something.
%
%   (b) noiseStartSample is drawn ONCE per (songID, lengthSec, rep,
%       noiseType) and reused across every SNR. This one is not spelled out
%       in 2.5, and leaving it out is easy to miss because the McNemar test
%       still works without it. What breaks is the SNR axis: if the noise
%       segment is redrawn at each SNR, the accuracy drop from 10 dB to 0 dB
%       is a mixture of "less favourable SNR" and "different babble", and the
%       curve in the paper's headline figure no longer isolates the variable
%       it is plotted against.
%
%   NOISE FILENAMES COME FROM THE BANK. Cfg.eval.noiseTypes are the project's
%   names (cafe, traffic, crowd); the files carry DEMAND's codes (PCAFETER,
%   STRAFFIC, SPSQUARE). There is no rule that maps one to the other, so the
%   mapping is read from db/noiseBank.csv rather than constructed.
%
%   HOLDOUT SONGS ARE QUERIED. They are the open-set negatives: without rows
%   for them there is no false-accept rate, the precision denominator in 8.3
%   is missing its wrongly-accepted term, and M5 has no ROC to tune tau and
%   rho against. They are excluded from ENROLMENT, never from the manifest.
%
%   Determinism comes from a local RandStream seeded with Cfg.seed, so
%   building the manifest neither depends on nor disturbs the global
%   generator. Re-running with the same Cfg and catalog reproduces the table
%   row for row.
%
%   Milestone: M3.  Blueprint: section(s) 2.5, 8.1, 8.2, 8.4.
%
%   See also SYNTHESIZEQUERY, PICKEXCERPTSTART, LOADNOISEBANK, RUNEXPERIMENT.

if nargin < 1 || isempty(catalog)
    catalog = loadCatalog();
end
if nargin < 2 || isempty(Cfg)
    Cfg = baselineConfig();
end

stream = RandStream('twister', 'Seed', Cfg.seed);

bank       = loadNoiseBank(Cfg);
noiseTypes = cellstr(string(Cfg.eval.noiseTypes));
lengths    = Cfg.eval.lengthsSec(:)';
snrAll     = Cfg.eval.snrDb(:)';
snrFinite  = snrAll(~isinf(snrAll));
reps       = Cfg.eval.repsPerSong;

nSongs      = height(catalog);
nPerExcerpt = 1 + numel(noiseTypes) * numel(snrFinite);
nRows       = nSongs * numel(lengths) * reps * nPerExcerpt;

logMsg('info', ...
    'Manifest: %d song(s) x %d length(s) x %d rep(s) x %d condition(s) = %d queries.', ...
    nSongs, numel(lengths), reps, nPerExcerpt, nRows);

% ---- Preallocate --------------------------------------------------------
queryID          = zeros(nRows, 1, 'uint32');
songID           = zeros(nRows, 1, 'uint16');
repertoire       = strings(nRows, 1);
role             = strings(nRows, 1);
split            = strings(nRows, 1);
lengthSec        = zeros(nRows, 1);
startSample      = zeros(nRows, 1, 'uint32');
rep              = zeros(nRows, 1, 'uint8');
noiseType        = strings(nRows, 1);
noiseFile        = strings(nRows, 1);
noiseStartSample = zeros(nRows, 1, 'uint32');
targetSnrDb      = zeros(nRows, 1);
seed             = zeros(nRows, 1, 'uint32');

gateFrac = nan(nSongs * numel(lengths) * reps, 1);
gateK    = 0;
r        = 0;
qid      = 0;

tAll = tic;

for i = 1:nSongs
    song = catalog(i, :);

    procFile = resolveProcPath(song.procPath);
    if ~isfile(procFile)
        error('HimigTransform:FileNotFound', ...
            ['No processed audio for songID %d at %s.\n' ...
             'Run s01_ingest, or check the procPath column in catalog.csv.'], ...
            double(song.songID), procFile);
    end

    % One read per song, nine excerpt picks off it.
    [x, fsIn] = audioread(procFile);
    if fsIn ~= Cfg.audio.fs
        error('HimigTransform:WrongSampleRate', ...
            '%s is %d Hz, expected %d Hz. Re-run s01_ingest.', ...
            procFile, fsIn, Cfg.audio.fs);
    end
    x = double(x(:, 1));

    for li = 1:numel(lengths)
        lenSec         = lengths(li);
        excerptSamples = round(lenSec * Cfg.audio.fs);

        for rp = 1:reps

            % ---- INVARIANT (a): one excerpt start per (song, length, rep)
            [s0, gInfo] = pickExcerptStart(x, lenSec, Cfg, stream);
            gateK           = gateK + 1;
            gateFrac(gateK) = gInfo.passFrac;

            % ---- INVARIANT (b): one noise offset per noise type, shared
            %      across every SNR for this excerpt.
            noiseStart = zeros(numel(noiseTypes), 1);
            for ni = 1:numel(noiseTypes)
                bRow      = bank(bank.noiseType == noiseTypes{ni}, :);
                maxNStart = max(1, double(bRow.nSamples(1)) - excerptSamples + 1);
                noiseStart(ni) = randi(stream, maxNStart);
            end

            % ---- Clean -------------------------------------------------
            r   = r + 1;
            qid = qid + 1;
            queryID(r)          = qid;
            songID(r)           = song.songID;
            repertoire(r)       = string(song.repertoire);
            role(r)             = string(song.role);
            split(r)            = string(song.split);
            lengthSec(r)        = lenSec;
            startSample(r)      = s0;
            rep(r)              = rp;
            noiseType(r)        = "none";
            noiseFile(r)        = "";
            noiseStartSample(r) = 0;
            targetSnrDb(r)      = Inf;
            seed(r)             = randi(stream, intmax('uint32') - 1);

            % ---- Noisy -------------------------------------------------
            for ni = 1:numel(noiseTypes)
                bRow = bank(bank.noiseType == noiseTypes{ni}, :);
                for si = 1:numel(snrFinite)
                    r   = r + 1;
                    qid = qid + 1;
                    queryID(r)          = qid;
                    songID(r)           = song.songID;
                    repertoire(r)       = string(song.repertoire);
                    role(r)             = string(song.role);
                    split(r)            = string(song.split);
                    lengthSec(r)        = lenSec;
                    startSample(r)      = s0;
                    rep(r)              = rp;
                    noiseType(r)        = string(noiseTypes{ni});
                    noiseFile(r)        = bRow.file(1);
                    noiseStartSample(r) = noiseStart(ni);
                    targetSnrDb(r)      = snrFinite(si);
                    seed(r)             = randi(stream, intmax('uint32') - 1);
                end
            end
        end
    end

    if mod(i, 20) == 0 || i == nSongs
        logMsg('info', '  manifest: %d/%d song(s).', i, nSongs);
    end
end

if r ~= nRows
    error('HimigTransform:ManifestSizeMismatch', ...
        'Preallocated %d rows but wrote %d. The grid arithmetic is wrong.', nRows, r);
end

M = table(queryID, songID, ...
    setcats(categorical(repertoire), {'american', 'opm'}), ...
    setcats(categorical(role),  {'db', 'holdout'}), ...
    setcats(categorical(split), {'dev', 'test'}), ...
    lengthSec, startSample, rep, ...
    setcats(categorical(noiseType), [{'none'}, noiseTypes(:)']), ...
    noiseFile, noiseStartSample, targetSnrDb, seed, ...
    'VariableNames', {'queryID', 'songID', 'repertoire', 'role', 'split', ...
    'lengthSec', 'startSample', 'rep', 'noiseType', 'noiseFile', ...
    'noiseStartSample', 'targetSnrDb', 'seed'});

M.Properties.UserData = struct( ...
    'cfgTag',      Cfg.tag, ...
    'seed',        Cfg.seed, ...
    'builtOn',     datetime('now'), ...
    'matlabVer',   version('-release'), ...
    'nSongs',      nSongs, ...
    'nInDb',       nnz(catalog.role == 'db'), ...
    'nHoldout',    nnz(catalog.role == 'holdout'), ...
    'snrDb',       snrAll, ...
    'lengthsSec',  lengths, ...
    'repsPerSong', reps);

logMsg('info', ...
    'Manifest: %d rows in %.1f s. Excerpt gate admitted %.0f%% of candidate windows (min %.0f%%).', ...
    height(M), toc(tAll), 100 * mean(gateFrac(1:gateK)), 100 * min(gateFrac(1:gateK)));

end
