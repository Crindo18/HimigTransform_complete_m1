%S02_PREPARENOISE  Build the 8 kHz noise bank from the DEMAND recordings.
%
%   Expects the 16 kHz DEMAND release under data/noise/source. Takes channel
%   01 of PCAFETER, STRAFFIC and SPSQUARE, resamples each to 8 kHz mono into
%   data/noise/, and writes db/noiseBank.csv with the checksums.
%
%   db/noiseBank.csv is committed for the same reason db/catalog.csv is: it
%   proves every member mixed against byte-identical noise, and it carries no
%   audio. If two people report different accuracy at 0 dB, this file is the
%   first thing to compare.
%
%   DEMAND is CC BY-SA 3.0 - attribute it in the paper. ShareAlike applies to
%   derivatives you redistribute, so do not publish mixed audio (blueprint D2
%   is the other reason queries are synthesised rather than stored).
%
%   Idempotent: an existing 8 kHz mono file is verified and skipped.
%
%   Milestone: M0.  Blueprint: sections 1.4, 6.2, 7 (M0).
%
%   Usage:
%       setupPaths;
%       s02_prepareNoise

projRoot = setupPaths();
Cfg      = defaultConfig();
rng(Cfg.seed, 'twister');

noiseRoot = fullfile(projRoot, 'data', 'noise');

logMsg('info', '===== s02_prepareNoise =====');
logMsg('info', 'MATLAB %s | target fs %d Hz | noise types: %s', ...
    version('-release'), Cfg.audio.fs, strjoin(Cfg.eval.noiseTypes, ', '));

noiseTable = prepareNoiseBank(Cfg);

noiseBankPath = fullfile(projRoot, 'db', 'noiseBank.csv');
writetable(noiseTable, noiseBankPath);
logMsg('info', 'Noise bank manifest written to %s', noiseBankPath);

% =======================================================================
% Composition
% =======================================================================
fprintf('\n--- Noise bank ---\n');
disp(noiseTable(:, {'noiseType', 'demandCode', 'file', 'durationSec', 'rmsDbfs'}));

fprintf('Total noise available : %.1f min\n', sum(noiseTable.durationSec) / 60);
fprintf('Level spread          : %.1f to %.1f dBFS\n', ...
    min(noiseTable.rmsDbfs), max(noiseTable.rmsDbfs));
fprintf('(Levels are left as DEMAND recorded them. mixAtSNR derives its gain\n');
fprintf(' from measured power, so pre-normalising would change nothing.)\n');

% =======================================================================
% Exit checks
% =======================================================================
problems = strings(0, 1);

% Every noise type the evaluation grid will ask for must exist. Without this,
% the failure surfaces at M3 as a missing file two hours into a grid run.
missingTypes = setdiff(Cfg.eval.noiseTypes, cellstr(string(noiseTable.noiseType)));
if ~isempty(missingTypes)
    problems(end + 1) = sprintf("missing noise type(s): %s", strjoin(missingTypes, ', ')); %#ok<SAGROW>
end

badHash = strlength(noiseTable.sha256) ~= 64;
if any(badHash)
    problems(end + 1) = sprintf("%d row(s) have no checksum", nnz(badHash)); %#ok<SAGROW>
end

% The manifest at M3 draws a random noiseStartSample per query, so each
% recording has to be comfortably longer than the longest query. DEMAND's are
% 300 s, which is enormous headroom - this check exists to catch a truncated
% download, not a genuinely marginal case.
minNeededSec = max(Cfg.eval.lengthsSec) * 3;
nChecked     = 0;

for k = 1:height(noiseTable)
    f = fullfile(noiseRoot, char(noiseTable.file(k)));
    if ~isfile(f)
        problems(end + 1) = sprintf("missing %s", noiseTable.file(k)); %#ok<SAGROW>
        continue
    end

    ai = audioinfo(f);
    if ai.SampleRate ~= Cfg.audio.fs || ai.NumChannels ~= 1
        problems(end + 1) = sprintf("%s: %d Hz / %d ch", ...
            noiseTable.file(k), ai.SampleRate, ai.NumChannels); %#ok<SAGROW>
    end

    if noiseTable.durationSec(k) < minNeededSec
        problems(end + 1) = sprintf("%s is only %.1f s; need at least %.0f s", ...
            noiseTable.file(k), noiseTable.durationSec(k), minNeededSec); %#ok<SAGROW>
    end

    if noiseTable.rmsDbfs(k) < -60
        logMsg('warn', ...
            '%s is very quiet (%.1f dBFS). Verify it is a real DEMAND recording and not a silent lead-in.', ...
            noiseTable.file(k), noiseTable.rmsDbfs(k));
    end

    nChecked = nChecked + 1;
end

fprintf('\n--- M0 exit check (noise bank) ---\n');
fprintf('Noise files verified 8 kHz mono : %d / %d\n', nChecked, height(noiseTable));
fprintf('Rows with checksums             : %d / %d\n', nnz(~badHash), height(noiseTable));
fprintf('Manifest                        : %s (COMMIT THIS)\n', noiseBankPath);

if isempty(problems)
    fprintf('s02_prepareNoise: PASS\n');
else
    fprintf('s02_prepareNoise: BLOCKED\n');
    for k = 1:numel(problems)
        fprintf('  - %s\n', problems(k));
    end
end
fprintf('----------------------------------\n');