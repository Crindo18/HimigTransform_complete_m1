function peaks = pickPeaksAdaptive(Smag, Cfg)
%PICKPEAKSADAPTIVE Enhancement 1b: SNR-adaptive constellation via a local-median threshold.
%
%   Admits a bin only if it exceeds the LOCAL median magnitude in its
%   neighbourhood by Cfg.peaks.kappaDb. Compute the local median with
%   movmedian
%   along each dimension (base MATLAB, separable approximation); medfilt2 is
%   the exact 2-D version if Image Processing Toolbox is available -
%   benchmark
%   the difference once and record it.
%
%   The intent is that peak density stays roughly constant across SNR. That
%   is
%   a claim to MEASURE, not assert: plotPeakDensityVsSnr is the figure that
%   shows the mechanism rather than just the outcome, and it is one of the
%   strongest arguments in the paper.
%
%   Milestone: M4.  Blueprint: section(s) 3.3.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also PICKPEAKS, PLOTPEAKDENSITYVSSNR.

error('HimigTransform:NotImplemented', ...
    'pickPeaksAdaptive is a stub (Milestone M4). See docs/designNotes.md.');

end
