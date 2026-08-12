%S01_INGEST  Convert data/raw audio to 8 kHz mono and build db/catalog.csv.
%
%   Run once after placing audio in data/raw. Idempotent: already-processed,
%   checksum-matching files are skipped, so re-running is cheap and doubles as
%   a verification pass over the whole processed library.
%
%   Exit check (printed at the end): every processed file is 8 kHz mono, every
%   catalog row carries a 64-character sha256, and songID is unique. The row
%   count is reported rather than asserted, because M0 runs on a 5-song toy
%   set and only M2 expects 120.
%
%   Milestone: M0.  Blueprint: sections 2.2, 7 (M0).
%
%   Usage:
%       setupPaths;
%       s01_ingest

projRoot = setupPaths();
Cfg      = defaultConfig();
rng(Cfg.seed, 'twister');

logMsg('info', '===== s01_ingest =====');
logMsg('info', 'MATLAB %s | target fs %d Hz | RMS %.1f dBFS', ...
    version('-release'), Cfg.audio.fs, Cfg.audio.targetRmsDbfs);

[catalog, report] = ingestLibrary(Cfg);

reportPath = fullfile(projRoot, 'db', 'ingestReport.csv');
writetable(report, reportPath);
logMsg('info', 'QA report written to %s', reportPath);

% =======================================================================
% Composition
% =======================================================================
fprintf('\n--- Catalog composition (%d songs) ---\n', height(catalog));
disp(groupsummary(catalog, {'role', 'repertoire', 'split'}));

if any(catalog.role == 'db')
    fprintf('Total in-DB duration : %.1f min\n', ...
        sum(catalog.durationSec(catalog.role == 'db')) / 60);
    fprintf('Mean track length    : %.1f s\n', ...
        mean(catalog.durationSec(catalog.role == 'db')));
end

% Loudness spread before normalisation. If this is wide, blueprint 6.1 was
% doing real work rather than being pedantic.
processedRows = report.action == "processed";
if any(processedRows)
    % max - min rather than range(): range lives in the Statistics Toolbox,
    % which blueprint 1.2 lists as optional.
    loIn = min(report.rmsDbfsIn(processedRows));
    hiIn = max(report.rmsDbfsIn(processedRows));
    fprintf('Source RMS spread    : %.1f to %.1f dBFS (%.1f dB range)\n', loIn, hiIn, hiIn - loIn);
end
if any(report.clipGuard)
    fprintf('Clip guard triggered : %d file(s) - see db/ingestReport.csv\n', nnz(report.clipGuard));
end

% =======================================================================
% Exit checks
% =======================================================================
problems = strings(0, 1);

if any(report.action == "failed")
    problems(end + 1) = sprintf("%d file(s) failed to convert", nnz(report.action == "failed"));
end

if numel(unique(catalog.songID)) ~= height(catalog)
    problems(end + 1) = "songID is not unique";
end

badHash = strlength(catalog.sha256) ~= 64;
if any(badHash)
    problems(end + 1) = sprintf("%d row(s) have no checksum", nnz(badHash));
end

nChecked = 0;
badAudio = strings(0, 1);
for i = 1:height(catalog)
    if strlength(catalog.procPath(i)) == 0
        continue
    end
    f = fullfile(projRoot, 'data', 'processed', strrep(char(catalog.procPath(i)), '/', filesep));
    if ~isfile(f)
        badAudio(end + 1) = sprintf("songID %d: missing %s", catalog.songID(i), catalog.procPath(i)); %#ok<SAGROW>
        continue
    end
    ai = audioinfo(f);
    if ai.SampleRate ~= Cfg.audio.fs || ai.NumChannels ~= 1
        badAudio(end + 1) = sprintf("songID %d: %d Hz / %d ch", ...
            catalog.songID(i), ai.SampleRate, ai.NumChannels); %#ok<SAGROW>
    end
    nChecked = nChecked + 1;
end

if ~isempty(badAudio)
    problems(end + 1) = sprintf("%d processed file(s) are not 8 kHz mono", numel(badAudio));
    for k = 1:numel(badAudio)
        logMsg('error', '  %s', badAudio(k));
    end
end

fprintf('\n--- M0 exit check ---\n');
fprintf('Processed files verified 8 kHz mono : %d\n', nChecked);
fprintf('Catalog rows with checksums         : %d / %d\n', nnz(~badHash), height(catalog));

if isempty(problems)
    fprintf('s01_ingest: PASS\n');
    if height(catalog) < 120
        fprintf('(Note: %d songs. M2 expects 120 - 50 american, 50 opm, 20 holdout.)\n', ...
            height(catalog));
    end
else
    fprintf('s01_ingest: BLOCKED\n');
    for k = 1:numel(problems)
        fprintf('  - %s\n', problems(k));
    end
end
fprintf('---------------------\n');