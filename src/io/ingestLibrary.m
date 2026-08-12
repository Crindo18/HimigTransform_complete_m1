function [catalog, report] = ingestLibrary(Cfg, varargin)
%INGESTLIBRARY Convert data/raw audio to 8 kHz mono WAV and build the catalog.
%
%   CATALOG = INGESTLIBRARY(CFG) walks data/raw, writes 8 kHz mono 16-bit WAVs
%   into data/processed/mono8k, and returns the blueprint 2.2 catalog table.
%   [CATALOG, REPORT] = INGESTLIBRARY(...) also returns a per-file QA table.
%
%   Name-value options:
%       'RawRoot'     scan somewhere other than data/raw
%       'ProcRoot'    write somewhere other than data/processed/mono8k
%       'CatalogPath' merge and write a catalog other than db/catalog.csv
%       'Force'       true reprocesses every file, ignoring the skip logic
%       'Verify'      false skips checksum verification of skipped files
%   The first three exist so s00_makeToySet can build a throwaway synthetic
%   library without ever touching the real catalog or consuming real songIDs.
%
%   LAYOUT. Repertoire and role are read from the path, not from a metadata
%   file, so moving a file is how you reclassify it:
%
%       data/raw/american/**            role db,      repertoire american
%       data/raw/opm/**                 role db,      repertoire opm
%       data/raw/holdout/american/**    role holdout, repertoire american
%       data/raw/holdout/opm/**         role holdout, repertoire opm
%
%   A file with no repertoire folder anywhere in its path is skipped with a
%   warning rather than guessed at. Guessing would silently corrupt the
%   per-repertoire analysis, which is the paper's novelty claim - a skipped
%   file you can see beats a mislabelled one you cannot.
%
%   IDEMPOTENCE. A file is reprocessed only when the output is missing, the
%   catalog checksum does not match the file on disk, the source is newer than
%   the output, or 'Force' is set. The checksum comparison is the expensive
%   part and it is the point: re-running s01_ingest is also how you verify
%   that nobody's processed library has drifted.
%
%   LEVEL. Files are RMS-normalised to CFG.audio.targetRmsDbfs on the way to
%   disk, so the whole catalog sits at one loudness before any peak picking or
%   SNR mixing happens (blueprint 6.1). A track whose crest factor would then
%   clip 16-bit full scale is scaled down and flagged in REPORT.clipGuard;
%   PREPROCESSSIGNAL re-normalises in memory anyway, where doubles do not
%   clip, so nothing downstream depends on the stored level being exact.
%
%   Milestone: M0.  Blueprint: sections 2.2, 6.1, 7 (M0).
%
%   See also BUILDCATALOG, LOADCATALOG, LOADAUDIO, RMSNORMALIZE, SHA256FILE.

projRoot = setupPaths();

opt = parseOpts(struct( ...
    'RawRoot',     fullfile(projRoot, 'data', 'raw'), ...
    'ProcRoot',    fullfile(projRoot, 'data', 'processed', 'mono8k'), ...
    'CatalogPath', fullfile(projRoot, 'db', 'catalog.csv'), ...
    'Force',       false, ...
    'Verify',      true), varargin);

if ~isfolder(opt.RawRoot)
    error('HimigTransform:NoRawFolder', ...
        'Raw audio folder does not exist: %s\nSee data/README.md.', opt.RawRoot);
end
if ~isfolder(opt.ProcRoot)
    mkdir(opt.ProcRoot);
end

% procPath in the catalog is relative to the processed root's parent, so it
% reads 'mono8k/song_0042.wav' for the real library and for the toy library
% alike.
[~, procLeaf] = fileparts(opt.ProcRoot);

logMsg('info', 'Ingest: scanning %s', opt.RawRoot);
[fileList, nSkipped] = scanRawFolder(opt.RawRoot);
logMsg('info', 'Ingest: %d audio file(s) found, %d skipped by the scanner.', ...
    numel(fileList), nSkipped);

catalog = buildCatalog(fileList, Cfg, opt.CatalogPath);
n       = height(catalog);

% ---- Per-file QA accumulators -----------------------------------------
action      = strings(n, 1);
fsIn        = zeros(n, 1);
nChIn       = zeros(n, 1);
rmsDbfsIn   = nan(n, 1);
gainDb      = nan(n, 1);
peakAfter   = nan(n, 1);
clipGuard   = false(n, 1);
elapsedSec  = zeros(n, 1);
message     = strings(n, 1);

nProcessed = 0;
nOk        = 0;
nFailed    = 0;
tStart     = tic;

for i = 1:n
    tFile = tic;

    srcFile  = fullfile(opt.RawRoot, strrep(char(catalog.sourcePath(i)), '/', filesep));
    procName = sprintf('song_%04d.wav', catalog.songID(i));
    procFile = fullfile(opt.ProcRoot, procName);
    procRel  = string([procLeaf '/' procName]);

    % ---- Skip logic ----------------------------------------------------
    if ~opt.Force && needsNoWork(srcFile, procFile, catalog(i, :), opt.Verify)
        catalog.procPath(i) = procRel;
        action(i)     = "skipped";
        message(i)    = "up to date";
        elapsedSec(i) = toc(tFile);
        nOk           = nOk + 1;
        continue
    end

    % ---- Convert -------------------------------------------------------
    try
        [x, fs, srcInfo] = loadAudio(srcFile, Cfg);

        fsIn(i)      = srcInfo.fsIn;
        nChIn(i)     = srcInfo.nChannelsIn;
        rmsDbfsIn(i) = srcInfo.rmsDbfs;

        if numel(x) < fs   % under one second of audio
            error('HimigTransform:TooShort', ...
                'Only %.2f s of audio after conversion; a fingerprint needs far more.', ...
                numel(x) / fs);
        end

        [x, gainDb(i)] = rmsNormalize(x, Cfg.audio.targetRmsDbfs);

        pk = max(abs(x));
        if pk > 0.999
            x            = x * (0.999 / pk);
            clipGuard(i) = true;
            logMsg('warn', ...
                'songID %d (%s): peak %.2f dBFS after RMS normalisation; scaled down to avoid clipping the 16-bit write.', ...
                catalog.songID(i), catalog.title(i), 20 * log10(pk));
        end
        peakAfter(i) = max(abs(x));

        audiowrite(procFile, x, fs, 'BitsPerSample', 16);

        % ---- Verify what actually landed on disk -----------------------
        ai = audioinfo(procFile);
        if ai.SampleRate ~= Cfg.audio.fs || ai.NumChannels ~= 1
            error('HimigTransform:BadProcessedFile', ...
                'Wrote %d Hz / %d channel(s); expected %d Hz mono.', ...
                ai.SampleRate, ai.NumChannels, Cfg.audio.fs);
        end

        catalog.procPath(i)    = procRel;
        catalog.durationSec(i) = ai.TotalSamples / ai.SampleRate;
        catalog.sha256(i)      = string(sha256File(procFile));

        action(i)  = "processed";
        message(i) = sprintf("%d Hz/%dch -> 8 kHz mono", srcInfo.fsIn, srcInfo.nChannelsIn);
        nProcessed = nProcessed + 1;
        nOk        = nOk + 1;

    catch err
        % Do not abort the run for one bad file. Clear the row's outputs so
        % the failure is visible in the catalog as well as the report, and
        % keep going - one unreadable rip should not cost you the other 119.
        catalog.procPath(i)    = "";
        catalog.durationSec(i) = 0;
        catalog.sha256(i)      = "";

        action(i)  = "failed";
        message(i) = string(err.message);
        nFailed    = nFailed + 1;

        logMsg('error', 'songID %d (%s): %s', ...
            catalog.songID(i), catalog.sourcePath(i), err.message);
    end

    elapsedSec(i) = toc(tFile);

    if mod(i, 10) == 0 || i == n
        logMsg('info', 'Ingest: %d/%d done (%d processed, %d failed).', ...
            i, n, nProcessed, nFailed);
    end
end

% ---- Write the catalog -------------------------------------------------
catalogDir = fileparts(opt.CatalogPath);
if ~isfolder(catalogDir)
    mkdir(catalogDir);
end
writetable(catalog, opt.CatalogPath);

logMsg('info', 'Ingest: %d row(s) written to %s in %.1f s (%d processed, %d skipped, %d failed).', ...
    n, opt.CatalogPath, toc(tStart), nProcessed, nOk - nProcessed, nFailed);

if nFailed > 0
    logMsg('warn', ...
        '%d file(s) failed. Their catalog rows have an empty sha256 - fix or remove them before M2.', nFailed);
end

% ---- Report ------------------------------------------------------------
report = table( ...
    catalog.songID, catalog.sourcePath, action, fsIn, nChIn, ...
    rmsDbfsIn, gainDb, peakAfter, clipGuard, catalog.durationSec, elapsedSec, message, ...
    'VariableNames', {'songID', 'sourcePath', 'action', 'fsIn', 'nChannelsIn', ...
                      'rmsDbfsIn', 'gainDb', 'peakAfter', 'clipGuard', ...
                      'durationSec', 'elapsedSec', 'message'});

end

% =======================================================================
function [fileList, nSkipped] = scanRawFolder(rawRoot)
%SCANRAWFOLDER Recursive scan, deriving repertoire and role from the path.

audioExt = {'.wav', '.flac', '.mp3', '.m4a', '.mp4', '.aac', '.ogg', ...
            '.wma', '.aif', '.aiff', '.au', '.opus'};

listing  = dir(fullfile(rawRoot, '**', '*'));
listing  = listing(~[listing.isdir]);

fileList = struct('relPath', {}, 'name', {}, 'repertoire', {}, 'role', {});
nSkipped = 0;

for k = 1:numel(listing)
    name = listing(k).name;

    % Hidden files and macOS resource forks.
    if startsWith(name, '.') || startsWith(name, '._')
        continue
    end

    [~, ~, ext] = fileparts(name);
    if ~any(strcmpi(ext, audioExt))
        continue
    end

    full = fullfile(listing(k).folder, name);
    rel  = strrep(erase(full, [rawRoot filesep]), '\', '/');
    parts = strsplit(rel, '/');

    if any(strcmpi(parts, 'opm'))
        repertoire = 'opm';
    elseif any(strcmpi(parts, 'american'))
        repertoire = 'american';
    else
        logMsg('warn', ...
            ['Skipping %s - no american/ or opm/ folder in its path, so its repertoire ' ...
             'is unknown. Move it into a repertoire folder (see data/README.md).'], rel);
        nSkipped = nSkipped + 1;
        continue
    end

    if any(strcmpi(parts, 'holdout'))
        role = 'holdout';
    else
        role = 'db';
    end

    fileList(end + 1) = struct( ...
        'relPath', rel, 'name', name, ...
        'repertoire', repertoire, 'role', role); %#ok<AGROW>
end

end

% =======================================================================
function tf = needsNoWork(srcFile, procFile, row, doVerify)
%NEEDSNOWORK True when the processed file is present, current and intact.

tf = false;

if ~isfile(procFile) || ~isfile(srcFile)
    return
end
if strlength(row.sha256) ~= 64 || row.durationSec <= 0
    return
end

d = dir(procFile);
s = dir(srcFile);
if s.datenum > d.datenum + 1/86400   % one second of slack for filesystem rounding
    return
end

if doVerify && ~strcmp(sha256File(procFile), char(row.sha256))
    logMsg('warn', ...
        'songID %d: checksum mismatch on %s - reprocessing.', row.songID, procFile);
    return
end

tf = true;

end

% =======================================================================
function opt = parseOpts(opt, args)
%PARSEOPTS Minimal name-value parsing. INPUTPARSER is overkill for five flags.

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