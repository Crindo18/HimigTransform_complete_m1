function peaks = enforcePeakDensity(peaks, nFrames, Cfg)
%ENFORCEPEAKDENSITY Cap constellation density per second and per frequency band.
%
%   PEAKS = ENFORCEPEAKDENSITY(PEAKS, NFRAMES, CFG) thins the constellation so
%   that, within every 1-second window and every frequency band defined by
%   Cfg.peaks.bandEdgesHz, at most K peaks survive - the K strongest by magDb.
%
%       K = round(Cfg.peaks.densityPerSec / nBands)
%
%   With the defaults that is round(25/5) = 5 peaks per band per second, for a
%   target of 25 peaks/s overall.
%
%   Two non-obvious requirements (blueprint 3.3):
%
%     (a) CAP PER SECOND, NOT PER SONG. A per-song budget makes a 6-minute
%         track contribute three times the postings of a 2-minute track, so
%         the long track is over-represented in the index and wins offset
%         histograms on sheer volume. It also makes the index size depend on
%         the catalogue's length distribution rather than on its duration,
%         which makes the memory budget in blueprint 2.4 unpredictable.
%
%     (b) CAP PER BAND. Music puts most of its energy below 500 Hz, so a
%         purely magnitude-ranked selection collapses the whole constellation
%         into the bass. What is lost is precisely the mid-frequency structure
%         that distinguishes one song from another - basslines and kick drums
%         are far more alike across tracks than vocal and instrumental
%         partials are. The bands are deliberately unequal in width (16 bins
%         at the bottom, 128 at the top) and get EQUAL budgets, which forces
%         the upper bands to be represented at all.
%
%   IT IS A CAP, NOT A QUOTA. A band-second holding fewer than K local maxima
%   keeps all of them, so quiet passages and sparse upper bands contribute
%   less and the achieved density sits below the target - typically well
%   below. That gap is not a defect to tune away, it is the signal: the
%   "peaks/second vs SNR" figure at M4 is exactly a measurement of how the
%   achieved density collapses under noise for the fixed picker and holds up
%   for the adaptive one. Reporting the achieved rate alongside the target is
%   what makes that figure honest.
%
%   Milestone: M1.  Blueprint: section 3.3.
%
%   See also PICKPEAKS, PICKPEAKSFIXED.

if nargin < 3 || isempty(Cfg)
    Cfg = defaultConfig();
end

if nargin < 2 || isempty(nFrames)
    nFrames = double(peaks.nFrames);
end

P = numel(peaks.tIdx);
if P == 0
    peaks.nFrames = nFrames;
    return
end

tIdx  = double(peaks.tIdx);
fIdx  = double(peaks.fIdx);
magDb = double(peaks.magDb);

if any(tIdx > nFrames)
    error('HimigTransform:PeakOutOfRange', ...
        'A peak sits at frame %d but the spectrogram has only %d frames.', ...
        max(tIdx), nFrames);
end

% ---- Band index ---------------------------------------------------------
edges = Cfg.peaks.bandEdgesHz(:)';
if numel(edges) < 2
    error('HimigTransform:BadBandEdges', ...
        'Cfg.peaks.bandEdgesHz needs at least two edges; got %d.', numel(edges));
end
nBands = numel(edges) - 1;

freqHz = (fIdx - 1) * Cfg.derived.binWidthHz;

% discretize leaves anything at or above the last edge undefined. The top edge
% is 4000 Hz and the last bin is exactly 4000 Hz at the default grid, so this
% clamp is not a rounding convenience - without it the entire top bin of every
% spectrogram silently vanishes from the constellation.
bandIdx = discretize(freqHz, edges);
bandIdx(freqHz >= edges(end)) = nBands;
bandIdx(freqHz <  edges(1))   = 1;

% ---- Second index -------------------------------------------------------
secIdx  = floor((tIdx - 1) / Cfg.derived.frameRate) + 1;
nSecs   = max(secIdx);

% ---- Rank within each (second, band) group -----------------------------
K = max(1, round(Cfg.peaks.densityPerSec / nBands));

key = (secIdx - 1) * nBands + bandIdx;

% Sort by group, then by magnitude descending inside the group. sortrows on
% [key, -magDb] does both in one pass and is deterministic, which matters:
% two members must build byte-identical indexes from identical audio.
[~, ord] = sortrows([key, -magDb]);

keySorted = key(ord);
newGroup  = [true; diff(keySorted) ~= 0];
grpStart  = find(newGroup);
grpSize   = diff([grpStart; P + 1]);

% 0-based rank of each row within its own group.
rank0 = (1:P)' - repelem(grpStart, grpSize);

keepOrd = ord(rank0 < K);

% ---- Restore time order ------------------------------------------------
% MAKEHASHES sweeps anchors assuming ascending time, and PICKPEAKSFIXED
% handed us that order; the sort above destroyed it.
keepOrd = sort(keepOrd);

peaks.tIdx    = uint32(tIdx(keepOrd));
peaks.fIdx    = uint16(fIdx(keepOrd));
peaks.magDb   = single(magDb(keepOrd));
peaks.nFrames = nFrames;

% ---- Achieved density, for the M4 mechanism figure ----------------------
durationSec           = max(nFrames / Cfg.derived.frameRate, eps);
peaks.densityPerSec   = numel(keepOrd) / durationSec;
peaks.densityTarget   = Cfg.peaks.densityPerSec;
peaks.nBeforeDensity  = P;
peaks.perBandPerSec   = K;
peaks.nSecs           = nSecs;

end