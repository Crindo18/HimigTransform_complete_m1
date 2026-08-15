function peaks = pickPeaksAdaptive(Smag, Cfg)
%PICKPEAKSADAPTIVE Constellation from a LOCAL threshold (Enhancement 1b).
%
%   PEAKS = PICKPEAKSADAPTIVE(SMAG, CFG) returns the constellation of SMAG, a
%   [nBins x nFrames] magnitude spectrogram. A bin is a peak if it is the
%   maximum over a Cfg.peaks.nbhdF x Cfg.peaks.nbhdT neighbourhood centred on
%   it AND it exceeds the LOCAL median magnitude inside that neighbourhood by
%   Cfg.peaks.kappaDb.
%
%   PEAKS has fields tIdx (uint32), fIdx (uint16), magDb (single) and nFrames,
%   matching PICKPEAKSFIXED exactly. The contrast between the two pickers must
%   be the threshold rule and nothing else.
%
%   NO DENSITY CAP HERE. PICKPEAKS applies ENFORCEPEAKDENSITY once, after
%   whichever picker ran, so fixed and adaptive are always compared at the
%   same peak budget. This function used to call it a second time internally.
%   The selection is idempotent so scores never moved, which is why it went
%   unnoticed - but the second pass overwrote peaks.nBeforeDensity with the
%   already-capped count. That field is the raw pre-cap peak count, and it is
%   the quantity PLOTPEAKDENSITYVSSNR draws to show that adaptive picking
%   holds density up as SNR falls. Corrupted for adaptive and correct for
%   fixed, it would have made the mechanism figure understate the very effect
%   it exists to demonstrate.
%
%   WHY SEPARABLE IS EXACT FOR THE MAX AND APPROXIMATE FOR THE MEDIAN. The
%   maximum over a rectangle is the max along rows of the max along columns,
%   so MOVMAX twice is not an approximation at all. The median does not
%   factor that way, so the median here is the separable approximation
%   blueprint 3.3 specifies; MEDFILT2 is the exact 2-D alternative and costs
%   an Image Processing Toolbox dependency. That comparison is a pending M4
%   decision, and the two must be benchmarked before one is chosen.
%
%   THE dB REFERENCE MATCHES THE FIXED PICKER. magDb is measured against the
%   loudest bin in this signal, not against raw STFT magnitude, so magDb means
%   the same thing in both pickers and ENFORCEPEAKDENSITY - which ranks peaks
%   by magDb - ranks them on the same scale whichever picker produced them.
%   The kappaDb test itself is a difference of two dB values and so is immune
%   to the choice of reference, but the magDb that is stored is not.
%
%   Milestone: M4.  Blueprint: section 3.3.
%
%   See also PICKPEAKS, PICKPEAKSFIXED, ENFORCEPEAKDENSITY.

if nargin < 2 || isempty(Cfg)
    Cfg = defaultConfig();
end

validateattributes(Smag, {'numeric'}, {'2d', 'real', 'nonnegative'}, mfilename, 'Smag');

nbhdF   = Cfg.peaks.nbhdF;
nbhdT   = Cfg.peaks.nbhdT;
kappaDb = Cfg.peaks.kappaDb;

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
    % Digital silence. A query can legitimately land on a silent lead-in;
    % R10's energy gate exists because that happens. Return nothing.
    peaks = emptyPeaks();
    peaks.nFrames = size(Smag, 2);
    return
end

magDb = 20 * log10(Smag / ref + eps);

% ---- 2-D local maximum (exact, separable) -------------------------------
% 'shrink' endpoints truncate the window at the edges, matching
% PICKPEAKSFIXED. Both pickers must treat boundaries identically or the M4
% comparison acquires a difference that has nothing to do with thresholding.
localMax = movmax(Smag, nbhdF, 1);
localMax = movmax(localMax, nbhdT, 2);

% ---- 2-D local median (separable approximation, blueprint 3.3) ----------
% Computed on magDb rather than Smag. The median commutes with a monotonic
% transform, so this is the same set of values either way; doing it in dB
% keeps the kappaDb comparison in one unit.
localMed = movmedian(magDb, nbhdF, 1);
localMed = movmedian(localMed, nbhdT, 2);

% ---- Admit ---------------------------------------------------------------
isPeak = (Smag >= localMax) & (magDb >= localMed + kappaDb) & (Smag > 0);

% find() walks column-major, so pairs come out ordered by frame then bin.
% MAKEHASHES relies on that ordering for its two-pointer sweep.
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
