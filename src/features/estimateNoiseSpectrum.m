function [Nmag, info] = estimateNoiseSpectrum(Smag, Cfg)
%ESTIMATENOISESPECTRUM Noise magnitude spectrum from the quietest frames.
%
%   NMAG = ESTIMATENOISESPECTRUM(SMAG, CFG) takes the magnitude spectrogram
%   SMAG [nBins x nFrames], selects the lowest-energy
%   Cfg.denoise.noiseFrameFrac of its frames, and returns their mean magnitude
%   spectrum as NMAG [nBins x 1].
%
%   [NMAG, INFO] = ... also returns
%       info.nFramesUsed   frames averaged
%       info.nFrames       frames available
%       info.frac          nFramesUsed / nFrames
%
%   ALWAYS A COLUMN. SPECTRALSUBTRACT expands this against [nBins x nFrames],
%   and a row of the same length expands along the wrong axis instead of
%   erroring whenever the frame count happens to equal the bin count. The
%   orientation is guaranteed here as well as guarded there.
%
%   THE ESTIMATE IS THIN ON SHORT QUERIES, BY CONSTRUCTION. A 3 s query is 93
%   frames, so the default 10% fraction averages nine frames of a
%   non-stationary source - cafe babble is not a stationary process over
%   300 ms. That is exactly the 3 s / 0 dB cell Enhancement 1 is judged on, so
%   the function warns when it has fewer than 8 frames to work with rather
%   than returning a confident-looking average of two. Whether to widen the
%   fraction for short queries, or floor the frame count, is an M4 sweep on
%   dev - not a default to guess at here.
%
%   Selecting by lowest energy systematically UNDER-estimates the noise floor,
%   because the quietest frames are quiet partly through noise fluctuation.
%   That bias is why Cfg.denoise.alpha exists and why it is swept rather than
%   fixed at 1.
%
%   Milestone: M4.  Blueprint: section 3.6.
%
%   See also SPECTRALSUBTRACT, COMPUTESTFT.

if nargin < 2 || isempty(Cfg)
    Cfg = defaultConfig();
end

validateattributes(Smag, {'numeric'}, {'2d'}, mfilename, 'Smag');

% Accept a complex spectrogram without silently doing the wrong thing: sorting
% complex values orders them by magnitude then angle, which would "work" and
% give a subtly different frame selection.
if ~isreal(Smag)
    Smag = abs(Smag);
end
Smag = double(Smag);

[nBins, nFrames] = size(Smag);

info = struct('nFramesUsed', 0, 'nFrames', nFrames, 'frac', 0);

if nFrames == 0 || nBins == 0
    error('HimigTransform:EmptySpectrogram', ...
        'estimateNoiseSpectrum received a %dx%d spectrogram.', nBins, nFrames);
end

frameEnergy = sum(Smag.^2, 1);

nNoiseFrames = round(Cfg.denoise.noiseFrameFrac * nFrames);
nNoiseFrames = max(1, min(nNoiseFrames, nFrames));

if nNoiseFrames < 8
    logMsg('warn', ...
        ['estimateNoiseSpectrum: only %d frame(s) of %d used for the noise ' ...
         'estimate. On a short query the estimate is noisy - see the M4 ' ...
         'noiseFrameFrac decision in docs/designNotes.md.'], ...
        nNoiseFrames, nFrames);
end

[~, order]  = sort(frameEnergy, 'ascend');
quietFrames = order(1:nNoiseFrames);

Nmag = mean(Smag(:, quietFrames), 2);
Nmag = Nmag(:);

info.nFramesUsed = nNoiseFrames;
info.frac        = nNoiseFrames / nFrames;

end
