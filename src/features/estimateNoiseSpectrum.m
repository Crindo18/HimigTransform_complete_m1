function Nmag = estimateNoiseSpectrum(Smag, Cfg)
%ESTIMATENOISESPECTRUM Estimate a noise magnitude spectrum from the lowest-energy frames.
%
%   Averages the quietest Cfg.denoise.noiseFrameFrac of frames. Returns
%   [nBins x 1]. Assumes the noise is roughly stationary across the clip - a
%   3 s query gives about 9 frames to work with at the default fraction,
%   which
%   is worth stating as a limitation in the paper.
%
%   Milestone: M4.  Blueprint: section(s) 3.6.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also SPECTRALSUBTRACT.

error('HimigTransform:NotImplemented', ...
    'estimateNoiseSpectrum is a stub (Milestone M4). See docs/designNotes.md.');

end
