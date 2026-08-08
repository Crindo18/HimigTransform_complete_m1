function [S, f, t] = computeSTFT(sig, Cfg)
%COMPUTESTFT Short-Time Fourier Transform, implemented from framing + window + fft.
%
%   Deliberately NOT a call to spectrogram(). This is a DSP course and the
%   pipeline is the deliverable; spectrogram() stays in tSTFT as the oracle
%   that proves this implementation correct to < 1e-10 relative error.
%
%   Returns S as [nBins x nFrames] complex, f in Hz, t in seconds. At the
%   default grid: nBins = 257, frame rate 31.25 Hz, bin width 15.625 Hz.
%
%   Do NOT rename this file to stft.m - it would shadow the Signal
%   Processing
%   Toolbox function and break the very test meant to validate it.
%
%   Milestone: M1.  Blueprint: section(s) 3.1, 4.1.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also FRAMESIGNAL, PICKPEAKS.

error('HimigTransform:NotImplemented', ...
    'computeSTFT is a stub (Milestone M1). See docs/designNotes.md.');

end
