function [S, f, t] = computeSTFT(sig, Cfg)
%COMPUTESTFT Short-Time Fourier Transform, implemented from framing + window + fft.
%
%   [S, F, T] = COMPUTESTFT(SIG, CFG) returns the one-sided complex STFT of
%   SIG as [nBins x nFrames], the bin centre frequencies F in Hz, and the
%   frame centre times T in seconds.
%
%   At the default grid (fs 8000, winLen 512, hop 256, nfft 512):
%   nBins = 257, bin width 15.625 Hz, frame rate 31.25 frames/s.
%
%   Deliberately NOT a call to spectrogram(). This is a DSP course and the
%   pipeline is the deliverable; spectrogram() stays in tSTFT as the oracle
%   that proves this implementation correct to < 1e-10 relative error.
%
%   NO SCALING IS APPLIED. S is the raw DFT of each windowed frame, exactly
%   what spectrogram() returns, so the oracle test is a direct comparison
%   rather than a comparison up to some constant nobody can later remember.
%   The consequence is that the magnitudes scale with window length and window
%   gain, and are therefore NOT in dBFS. Anything that needs an interpretable
%   dB value takes its own reference - see PICKPEAKSFIXED, which measures
%   relative to the loudest bin in the same signal.
%
%   THE WINDOW IS HAND-WRITTEN, and it has to match MATLAB's to the last bit
%   or the oracle test fails for a reason that looks like an FFT bug. Both
%   'hamming' and 'hann' are built the way MATLAB builds them: compute one
%   half and mirror it, so the result is exactly symmetric rather than
%   symmetric to within rounding.
%
%   Do NOT rename this file to stft.m - it would shadow the Signal Processing
%   Toolbox function and break the very test meant to validate it.
%
%   MEMORY. The framed, windowed and transformed copies coexist briefly, so a
%   6-minute track peaks around 150 MB. Per song that is fine; it is worth
%   knowing before sizing the parfor pool at M2.
%
%   Milestone: M1.  Blueprint: sections 3.1, 4.1.
%
%   See also FRAMESIGNAL, PICKPEAKS.

if nargin < 2 || isempty(Cfg)
    Cfg = defaultConfig();
end

winLen = Cfg.stft.winLen;
hop    = Cfg.stft.hop;
nfft   = Cfg.stft.nfft;
fs     = Cfg.audio.fs;

if nfft < winLen
    error('HimigTransform:BadStftGrid', ...
        'Cfg.stft.nfft (%d) must be >= Cfg.stft.winLen (%d).', nfft, winLen);
end

nBins = floor(nfft / 2) + 1;

% ---- Frame, window, transform ------------------------------------------
F = frameSignal(sig, winLen, hop);

if isempty(F)
    S = complex(zeros(nBins, 0));
    f = (0:nBins - 1)' * (fs / nfft);
    t = zeros(0, 1);
    return
end

w = analysisWindow(Cfg.stft.window, winLen);

S = fft(F .* w, nfft);
S = S(1:nBins, :);

% ---- Axes ---------------------------------------------------------------
nFrames = size(S, 2);

f = (0:nBins - 1)' * (fs / nfft);

% Frame CENTRES, matching spectrogram's convention. The matcher never uses
% this - it works in integer frame indices throughout, so that an offset
% difference is an exact integer and the histogram in ALIGNOFFSETS has no
% rounding in it. T exists for plotting.
t = ((0:nFrames - 1)' * hop + winLen / 2) / fs;

end

% =======================================================================
function w = analysisWindow(name, n)
%ANALYSISWINDOW Hand-built symmetric cosine windows, bit-identical to MATLAB's.
%
%   MATLAB computes half the window and mirrors it. Reproducing that exactly
%   matters: computing the full vector in one expression leaves asymmetries of
%   order 1e-17, which is harmless in itself but is the kind of difference
%   that makes a 1e-10 oracle comparison mysterious rather than reassuring.

validateattributes(n, {'numeric'}, {'scalar', 'integer', 'positive'}, mfilename, 'n');

% BOTH COEFFICIENTS ARE WRITTEN OUT AS LITERALS, and that is not stylistic.
% Computing the second one as (1 - a0) is algebraically identical and
% numerically is not: 1 - 0.54 evaluates to 0.45999999999999996, one unit in
% the last place below the literal 0.46. That one bit propagates into every
% window sample and puts this window about 5.6e-17 away from MATLAB's, which
% is harmless for the DSP but destroys any bit-identical comparison against
% hamming() - and turns tSTFT's window check into a puzzle.
switch lower(char(name))
    case 'hamming'
        a0 = 0.54;   a1 = 0.46;
    case 'hann'
        a0 = 0.5;    a1 = 0.5;
    case {'rect', 'rectangular', 'boxcar', 'none'}
        w = ones(n, 1);
        return
    otherwise
        error('HimigTransform:UnknownWindow', ...
            'Cfg.stft.window = "%s" is not supported. Use ''hamming'', ''hann'' or ''rect''.', ...
            char(name));
end

if n == 1
    w = 1;
    return
end

half  = ceil(n / 2);
k     = (0:half - 1)' / (n - 1);
wHalf = a0 - a1 * cos(2 * pi * k);

if mod(n, 2) == 0
    w = [wHalf; flipud(wHalf)];
else
    w = [wHalf; flipud(wHalf(1:end - 1))];
end

end