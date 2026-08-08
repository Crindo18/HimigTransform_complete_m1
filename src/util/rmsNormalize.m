function [y, gainDb] = rmsNormalize(x, targetRmsDbfs)
%RMSNORMALIZE Scale a signal to a target RMS level in dBFS.
%
%   RMS, not peak. See blueprint 6.1 - peak normalisation leaves a
%   compressed
%   modern master and a dynamic older recording at very different loudness,
%   which breaks both the peak-picking threshold and the SNR mixing.
%
%   Milestone: M0.  Blueprint: section(s) 6.1.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also PREPROCESSSIGNAL, MIXATSNR.

error('HimigTransform:NotImplemented', ...
    'rmsNormalize is a stub (Milestone M0). See docs/designNotes.md.');

end
