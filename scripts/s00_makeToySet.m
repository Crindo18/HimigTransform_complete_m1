%S00_MAKETOYSET  Build and ingest the five-song synthetic toy library.
%
%   Generates data/toy/raw, ingests it into data/toy/processed/mono8k, and
%   writes db/catalogToy.csv. Nothing here touches data/raw, data/processed or
%   db/catalog.csv, so the toy set can never consume a real songID or pollute
%   the real catalog.
%
%   Run this before s01_ingest. It is the fastest way to prove the whole data
%   spine works - resampling, downmix, RMS normalisation, checksums, catalog
%   merge, split assignment - on audio that exists on every machine and needs
%   no licence. It is also what tSelfMatch matches against at M1, and what
%   makes the fresh-clone rehearsal at M8 possible without shipping audio.
%
%   Idempotent: existing toy WAVs and their processed outputs are skipped.
%   Delete data/toy to force a full rebuild.
%
%   Milestone: M0.  Blueprint: sections 1.4, 7 (M0).
%
%   Usage:
%       setupPaths;
%       s00_makeToySet

projRoot = setupPaths();
Cfg      = defaultConfig();
rng(Cfg.seed, 'twister');

toyRawRoot     = fullfile(projRoot, 'data', 'toy', 'raw');
toyProcRoot    = fullfile(projRoot, 'data', 'toy', 'processed', 'mono8k');
toyCatalogPath = fullfile(projRoot, 'db', 'catalogToy.csv');

logMsg('info', '===== s00_makeToySet =====');
logMsg('info', 'MATLAB %s | seed %d | target fs %d Hz', ...
    version('-release'), Cfg.seed, Cfg.audio.fs);

% =======================================================================
% 1. Synthesise
% =======================================================================
toyFiles = makeToyLibrary(Cfg, 'RawRoot', toyRawRoot);

fprintf('\n--- Toy sources ---\n');
disp(toyFiles(:, {'relPath', 'fsSource', 'nChannels', 'durationSec', 'rmsDbfs', 'action'}));

% =======================================================================
% 2. Ingest through the real pipeline
% =======================================================================
% Same INGESTLIBRARY the real library uses. That is the point: if the toy set
% ingests cleanly and the real one does not, the difference is the audio, not
% the code.
[toyCatalog, toyReport] = ingestLibrary(Cfg, ...
    'RawRoot',     toyRawRoot, ...
    'ProcRoot',    toyProcRoot, ...
    'CatalogPath', toyCatalogPath);

fprintf('\n--- Toy catalog (%d songs) ---\n', height(toyCatalog));
disp(toyCatalog(:, {'songID', 'artist', 'title', 'year', 'repertoire', 'role', 'split', 'durationSec'}));

processedRows = toyReport.action == "processed";
if any(processedRows)
    loIn = min(toyReport.rmsDbfsIn(processedRows));
    hiIn = max(toyReport.rmsDbfsIn(processedRows));
    fprintf('Source RMS spread    : %.1f to %.1f dBFS (%.1f dB range)\n', loIn, hiIn, hiIn - loIn);
    fprintf('Gain applied         : %.1f to %.1f dB\n', ...
        min(toyReport.gainDb(processedRows)), max(toyReport.gainDb(processedRows)));
end

% =======================================================================
% Exit checks
% =======================================================================
problems = strings(0, 1);

if height(toyCatalog) ~= 5
    problems(end + 1) = sprintf("expected 5 toy songs, got %d", height(toyCatalog)); %#ok<SAGROW>
end

if any(toyReport.action == "failed")
    problems(end + 1) = sprintf("%d toy file(s) failed to convert", ...
        nnz(toyReport.action == "failed")); %#ok<SAGROW>
end

badHash = strlength(toyCatalog.sha256) ~= 64;
if any(badHash)
    problems(end + 1) = sprintf("%d row(s) have no checksum", nnz(badHash)); %#ok<SAGROW>
end

% Every source rate must have landed at 8 kHz mono. This is the check that
% actually exercises resampleAudio across all five ratios.
nChecked = 0;
for i = 1:height(toyCatalog)
    if strlength(toyCatalog.procPath(i)) == 0
        continue
    end
    f = fullfile(projRoot, 'data', 'toy', 'processed', ...
        strrep(char(toyCatalog.procPath(i)), '/', filesep));
    if ~isfile(f)
        problems(end + 1) = sprintf("songID %d: missing %s", ...
            toyCatalog.songID(i), toyCatalog.procPath(i)); %#ok<SAGROW>
        continue
    end
    ai = audioinfo(f);
    if ai.SampleRate ~= Cfg.audio.fs || ai.NumChannels ~= 1
        problems(end + 1) = sprintf("songID %d: %d Hz / %d ch", ...
            toyCatalog.songID(i), ai.SampleRate, ai.NumChannels); %#ok<SAGROW>
    end
    nChecked = nChecked + 1;
end

if height(toyCatalog) == 5
    if numel(unique(toyCatalog.repertoire)) < 2
        problems(end + 1) = "toy set should cover both repertoires"; %#ok<SAGROW>
    end
    if ~any(toyCatalog.role == 'holdout')
        problems(end + 1) = "toy set should include a holdout song"; %#ok<SAGROW>
    end
end

fprintf('\n--- M0 exit check (toy set) ---\n');
fprintf('Toy files verified 8 kHz mono : %d / %d\n', nChecked, height(toyCatalog));
fprintf('Rows with checksums           : %d / %d\n', nnz(~badHash), height(toyCatalog));
fprintf('Catalog                       : %s\n', toyCatalogPath);

if isempty(problems)
    fprintf('s00_makeToySet: PASS\n');
    fprintf('(The toy set is gitignored and regenerates from Cfg.seed = %d.)\n', Cfg.seed);
else
    fprintf('s00_makeToySet: BLOCKED\n');
    for k = 1:numel(problems)
        fprintf('  - %s\n', problems(k));
    end
end
fprintf('-------------------------------\n');