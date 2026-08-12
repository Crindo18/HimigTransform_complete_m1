function peaks = pickPeaksFixed(Smag, Cfg)
%PICKPEAKSFIXED Baseline constellation: 2-D local maxima above a global magnitude floor.
%
%   PEAKS = PICKPEAKSFIXED(SMAG, CFG) returns the constellation of SMAG, a
%   [nBins x nFrames] magnitude spectrogram. A bin is a peak if it is the
%   maximum over a Cfg.peaks.nbhdF x Cfg.peaks.nbhdT neighbourhood centred on
%   it AND its magnitude exceeds Cfg.peaks.floorDb.
%
%   PEAKS has fields tIdx (uint32), fIdx (uint16) and magDb (single), all
%   [P x 1], sorted by time then frequency. Indices are 1-based MATLAB
%   indices into SMAG.
%
%   No density cap is applied here. PICKPEAKS applies ENFORCEPEAKDENSITY
%   afterwards for both modes, so the two pickers are always compared at the
%   same peak budget.
%
%   WHAT floorDb IS MEASURED AGAINST. The reference is the loudest bin in this
%   signal: magDb = 20*log10(Smag / max(Smag(:))), so magDb is 0 at the peak
%   of the spectrogram and negative everywhere else, and the default -80 dB
%   means "80 dB below the loudest thing in this track."
%
%   An absolute floor was the obvious alternative and it is a trap. The raw
%   STFT magnitudes carry the window gain and scale with winLen, so an
%   absolute threshold silently changes meaning the moment anyone touches the
%   STFT grid. Worse, PREPROCESSSIGNAL's pre-emphasis stage pulls the signal
%   6-12 dB down by an amount that depends on the track's spectral tilt, so an
%   absolute floor would sit at a different effective level for every song -
%   reintroducing exactly the per-track inconsistency that RMS normalisation
%   was adopted to remove (blueprint 6.1).
%
%   This is still a FIXED picker in the sense blueprint 3.3 means. The
%   reference is one scalar for the whole signal; the contrast with
%   PICKPEAKSADAPTIVE is that the adaptive picker compares each bin against a
%   LOCAL median inside its own neighbourhood, which is what lets its peak
%   density hold up as SNR falls.
%
%   AND THE FLOOR IS NOT THE MECHANISM. At -80 dB relative it rejects digital
%   silence and very little else; ENFORCEPEAKDENSITY does the real selecting.
%   That is deliberate. A floor tight enough to control density on its own
%   would have to be re-tuned per track, and the whole point of the density
%   cap is that it controls the index budget directly instead of hoping a
%   threshold does it indirectly.
%
%   Milestone: M1.  Blueprint: section 3.3.
%
%   See also PICKPEAKS, PICKPEAKSADAPTIVE, ENFORCEPEAKDENSITY.

if nargin < 2 || isempty(Cfg)
    Cfg = defaultConfig();
end

validateattributes(Smag, {'numeric'}, {'2d', 'real', 'nonnegative'}, mfilename, 'Smag');

nbhdF = Cfg.peaks.nbhdF;
nbhdT = Cfg.peaks.nbhdT;

if mod(nbhdF, 2) == 0 || mod(nbhdT, 2) == 0
    error('HimigTransform:EvenNeighbourhood', ...
        ['Cfg.peaks.nbhdF (%d) and nbhdT (%d) must both be odd so the ' ...
         'neighbourhood is centred on the bin being tested.'], nbhdF, nbhdT);
end

Smag = double(Smag);

if isempty(Smag)
    peaks = emptyPeaks();
    return
end

% ---- dB relative to the loudest bin in this signal ----------------------
ref = max(Smag(:));

if ~(ref > 0)
    % Digital silence. Not an error - a query can legitimately land on a
    % silent lead-in, and R10's energy gate exists precisely because that
    % happens. Return nothing and let the caller see zero hashes.
    peaks = emptyPeaks();
    return
end

magDb = 20 * log10(Smag / ref + eps);

% ---- 2-D local maximum --------------------------------------------------
% The max over a rectangle is separable: the max over nbhdF rows of the max
% over nbhdT columns. movmax is base MATLAB, so this needs no Image
% Processing Toolbox and there is no fallback branch to keep in sync.
% 'shrink' endpoints truncate the window at the edges, which is the correct
% reading of "is this bin the largest thing near it" at a boundary.
localMax = movmax(Smag, nbhdF, 1);
localMax = movmax(localMax, nbhdT, 2);

isPeak = (Smag >= localMax) & (magDb >= Cfg.peaks.floorDb) & (Smag > 0);

% find() walks column-major, so the pairs come out ordered by frame and then
% by bin. MAKEHASHES relies on that ordering for its two-pointer sweep, and
% keeping it here saves a sort over every peak in the catalogue.
[fIdx, tIdx] = find(isPeak);

peaks         = struct();
peaks.tIdx    = uint32(tIdx);
peaks.fIdx    = uint16(fIdx);
peaks.magDb   = single(magDb(sub2ind(size(Smag), fIdx, tIdx)));
peaks.nFrames = size(Smag, 2);

end

% =======================================================================
function peaks = emptyPeaks()
peaks         = struct();
peaks.tIdx    = zeros(0, 1, 'uint32');
peaks.fIdx    = zeros(0, 1, 'uint16');
peaks.magDb   = zeros(0, 1, 'single');
peaks.nFrames = 0;
end