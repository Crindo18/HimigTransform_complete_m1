function bank = loadNoiseBank(Cfg, bankPath)
%LOADNOISEBANK Read db/noiseBank.csv into a typed table with absolute paths.
%
%   BANK = LOADNOISEBANK() reads db/noiseBank.csv and returns one row per
%   noise type with the columns written by PREPARENOISEBANK - noiseType,
%   demandCode, file, durationSec, fsSource, rmsDbfs, sha256 - plus two
%   derived columns this project needs everywhere:
%
%       path         absolute path to the 8 kHz mono WAV
%       nSamples     length in samples at Cfg.audio.fs
%
%   BANK = LOADNOISEBANK(CFG, BANKPATH) reads from elsewhere.
%
%   THE MAPPING IS DATA, NOT A NAMING RULE. Cfg.eval.noiseTypes holds the
%   project's own names - cafe, traffic, crowd - and the files on disk carry
%   DEMAND's codes: PCAFETER, STRAFFIC, SPSQUARE. There is no transformation
%   that turns one into the other, so any code that builds a filename by
%   upper-casing a noise type produces CAFE_ch01_8k.wav and fails to open
%   anything. BUILDQUERYMANIFEST did exactly that, which would have made every
%   noisy query in the grid unloadable.
%
%   noiseBank.csv already records the mapping, is committed for the same
%   reason catalog.csv is, and carries the checksums that prove every member
%   has the same noise. Look the filename up here rather than deriving it.
%
%   Milestone: M3.  Blueprint: section(s) 1.4, 2.5.
%
%   See also PREPARENOISEBANK, BUILDQUERYMANIFEST, SYNTHESIZEQUERY.

if nargin < 1 || isempty(Cfg)
    Cfg = defaultConfig();
end

projRoot = setupPaths();

if nargin < 2 || isempty(bankPath)
    bankPath = fullfile(projRoot, 'db', 'noiseBank.csv');
end
bankPath = char(bankPath);

if ~isfile(bankPath)
    error('HimigTransform:NoNoiseBank', ...
        'No noise bank at %s.\nRun s02_prepareNoise first (see data/README.md).', bankPath);
end

opts = detectImportOptions(bankPath, 'TextType', 'string');
bank = readtable(bankPath, opts);

required = {'noiseType', 'file', 'durationSec'};
missingCols = setdiff(required, bank.Properties.VariableNames);
if ~isempty(missingCols)
    error('HimigTransform:BadNoiseBank', ...
        'noiseBank.csv is missing required column(s): %s\nDelete it and re-run s02_prepareNoise.', ...
        strjoin(missingCols, ', '));
end

bank.noiseType = setcats(categorical(string(bank.noiseType)), ...
    cellstr(string(Cfg.eval.noiseTypes)));

if any(isundefined(bank.noiseType))
    error('HimigTransform:BadNoiseBank', ...
        ['noiseBank.csv contains a noise type outside Cfg.eval.noiseTypes {%s}. ' ...
         'The manifest keys on these names, so they have to agree.'], ...
        strjoin(cellstr(string(Cfg.eval.noiseTypes)), ', '));
end

% ---- Derived columns ----------------------------------------------------
noiseRoot = fullfile(projRoot, 'data', 'noise');
bank.path = strings(height(bank), 1);
for k = 1:height(bank)
    bank.path(k) = string(fullfile(noiseRoot, char(bank.file(k))));
end

bank.nSamples = floor(bank.durationSec * Cfg.audio.fs);

% ---- Every configured type must be present ------------------------------
wanted  = cellstr(string(Cfg.eval.noiseTypes));
present = cellstr(string(bank.noiseType));
absent  = setdiff(wanted, present);
if ~isempty(absent)
    error('HimigTransform:IncompleteNoiseBank', ...
        ['Noise bank has no entry for: %s.\nCfg.eval.noiseTypes expects {%s}. ' ...
         'Re-run s02_prepareNoise.'], ...
        strjoin(absent, ', '), strjoin(wanted, ', '));
end

end
