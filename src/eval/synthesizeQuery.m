function [y, meas] = synthesizeQuery(manifestRow, catalog, Cfg, cache)
%SYNTHESIZEQUERY Regenerate one query waveform from its manifest row (D2).
%
%   [Y, MEAS] = SYNTHESIZEQUERY(MANIFESTROW, CATALOG, CFG) returns the
%   waveform for one row of the table BUILDQUERYMANIFEST produced. MEAS
%   carries the verification fields:
%
%       meas.snrDbMeasured   SNR measured back off Y (blueprint 6.2)
%       meas.lengthSamples   numel(y)
%       meas.noiseGain       the pre-rescale noise gain used
%
%   [Y, MEAS] = SYNTHESIZEQUERY(..., CACHE) reuses audio held in a containers.Map
%   keyed by file path. RUNEXPERIMENT passes one in: without it, a 17,280-row
%   grid re-reads a three-minute WAV once per query, which is precisely the
%   disk I/O in the inner loop that D2 chose the manifest to avoid.
%
%   REPRODUCIBILITY COMES FROM THE ROW, NOT FROM A SEED. Every quantity that
%   could vary - the excerpt offset, the noise file, the noise offset, the
%   target SNR - is a column in the manifest. Nothing here is random, so
%   nothing here touches a random generator. The earlier version called
%   rng(row.seed) at entry, which reset the global stream on all 17,280 calls
%   and made this function a hidden side effect on anything else drawing
%   random numbers in the same session. The seed column stays in the manifest
%   (blueprint 2.5) so a future stochastic step can be made per-row
%   reproducible without reintroducing that.
%
%   THE EXCERPT LENGTH IS ASSERTED, NOT CLAMPED. Silently returning a short
%   excerpt when the window runs past the end of the track makes lengthSec a
%   lie in every results table and bends the length axis of a headline figure.
%   PICKEXCERPTSTART already guarantees the window fits; if it ever does not,
%   that is a bug worth an error rather than a quiet 2.7-second "3 s" query.
%
%   Milestone: M3.  Blueprint: section(s) 0 (D2), 2.5, 6.2.
%
%   See also BUILDQUERYMANIFEST, MIXATSNR, PICKEXCERPTSTART, RUNEXPERIMENT.

if nargin < 3 || isempty(Cfg)
    Cfg = baselineConfig();
end
if nargin < 4
    cache = [];
end

fs = Cfg.audio.fs;

% ---- Clean excerpt ------------------------------------------------------
song = catalog(catalog.songID == manifestRow.songID, :);
if height(song) ~= 1
    error('HimigTransform:SongNotInCatalog', ...
        'songID %d matched %d catalog row(s); expected exactly 1.', ...
        double(manifestRow.songID), height(song));
end

procFile = resolveProcPath(song.procPath);
x        = readCached(procFile, fs, cache);

excerptSamples = round(manifestRow.lengthSec * fs);
s0             = double(manifestRow.startSample);
sEnd           = s0 + excerptSamples - 1;

if s0 < 1 || sEnd > numel(x)
    error('HimigTransform:ExcerptOutOfRange', ...
        ['queryID %d wants samples %d..%d of songID %d, which has %d. ' ...
         'The manifest and the audio disagree - re-run s04_buildQueries after ' ...
         'any change to the processed audio.'], ...
        double(manifestRow.queryID), s0, sEnd, double(manifestRow.songID), numel(x));
end

xEx = x(s0:sEnd);

meas               = struct();
meas.lengthSamples = numel(xEx);
meas.noiseGain     = 0;

% ---- Clean condition ----------------------------------------------------
if isinf(manifestRow.targetSnrDb) && manifestRow.targetSnrDb > 0
    y                   = xEx;
    meas.snrDbMeasured  = Inf;
    return
end

% ---- Noise segment ------------------------------------------------------
noiseFile = char(manifestRow.noiseFile);
if isempty(noiseFile)
    error('HimigTransform:MissingNoiseFile', ...
        'queryID %d has targetSnrDb %g but no noiseFile.', ...
        double(manifestRow.queryID), manifestRow.targetSnrDb);
end

% PROJECTROOT, not setupPaths: this runs once per query and setupPaths
% re-runs addpath every time (see projectRoot's help).
noisePath = fullfile(projectRoot(), 'data', 'noise', noiseFile);
nFull     = readCached(noisePath, fs, cache);

nStart = double(manifestRow.noiseStartSample);
nEnd   = nStart + excerptSamples - 1;

if nStart < 1
    nStart = 1;
    nEnd   = excerptSamples;
end

if nEnd > numel(nFull)
    % Wrap rather than fail: the bank is 300 s and the manifest bounds the
    % offset, so this only fires if the noise file on disk is shorter than
    % noiseBank.csv claims. Wrapping keeps the run alive; the warning says
    % the bank needs rebuilding.
    logMsg('warn', ...
        '%s is shorter than noiseBank.csv records; wrapping the noise segment.', noiseFile);
    idx  = mod((nStart:nEnd) - 1, numel(nFull)) + 1;
    nEx  = nFull(idx);
else
    nEx = nFull(nStart:nEnd);
end

[y, meas.noiseGain, meas.snrDbMeasured] = mixAtSNR(xEx, nEx, manifestRow.targetSnrDb);

meas.lengthSamples = numel(y);

end

% =======================================================================
function x = readCached(f, fs, cache)
%READCACHED Read an audio file, reusing a cached copy when one is offered.

if ~isempty(cache) && isKey(cache, f)
    x = cache(f);
    return
end

if ~isfile(f)
    error('HimigTransform:FileNotFound', ...
        'No such audio file: %s\nCheck s01_ingest / s02_prepareNoise have run.', f);
end

[x, fsIn] = audioread(f);
if fsIn ~= fs
    error('HimigTransform:WrongSampleRate', ...
        '%s is %d Hz, expected %d Hz.', f, fsIn, fs);
end
x = double(x(:, 1));

if ~isempty(cache)
    % containers.Map is a handle class, so writing here updates the caller's
    % cache in place - no need to return it.
    cache(f) = x;
end

end
