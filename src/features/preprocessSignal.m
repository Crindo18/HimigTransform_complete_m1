function sig = preprocessSignal(x, fs, Cfg)
%PREPROCESSSIGNAL DC removal, RMS normalisation and pre-emphasis.
%
%   SIG = PREPROCESSSIGNAL(X, FS, CFG) applies, in this order:
%
%       1. DC removal          (Cfg.pre.dcRemove)
%       2. RMS normalisation   (Cfg.audio.targetRmsDbfs)
%       3. Pre-emphasis        (Cfg.pre.preemphAlpha)
%
%   Applied IDENTICALLY to reference and query. The only deliberate asymmetry
%   in the whole pipeline is spectral subtraction, which is query-side only.
%   Blueprint 3.7 is the authoritative symmetry table; tPreprocessSymmetry
%   enforces it.
%
%   THE ORDER IS THE BLUEPRINT'S AND IT MATTERS. DC removal comes first
%   because a DC offset inflates the measured RMS, so normalising before
%   removing it would leave every file at a slightly different true level, by
%   an amount that varies with how badly it was transferred. Pre-emphasis
%   comes last because it is a high-pass and it changes the RMS - typically
%   pulling music 6-12 dB down, since most musical energy sits low. That means
%   SIG is NOT at Cfg.audio.targetRmsDbfs on the way out, and it is not
%   supposed to be. Nothing downstream depends on its absolute level: the peak
%   picker's floor is measured relative to the loudest bin in the same signal
%   (see PICKPEAKSFIXED), and MIXATSNR does its work on the raw excerpt long
%   before this function is reached.
%
%   WHY PRE-EMPHASIS AT ALL. A first-order (1 - alpha*z^-1) high-pass tilts
%   the spectrum upward by roughly 6 dB/octave, which partly cancels the
%   natural downward tilt of music. Without it the peak picker sees a
%   spectrogram whose energy is overwhelmingly concentrated below 500 Hz, and
%   even the per-band density cap in ENFORCEPEAKDENSITY is then choosing
%   between weak candidates in the upper bands rather than good ones. Set
%   Cfg.pre.preemphAlpha = 0 to disable it - but disable it on BOTH sides or
%   nothing will match, which is exactly what tPreprocessSymmetry checks.
%
%   FS is validated against Cfg.audio.fs rather than used to resample. By this
%   point LOADAUDIO or SYNTHESIZEQUERY has already put the signal on the
%   working grid; a mismatch here means a caller skipped a step, and failing
%   loudly beats fingerprinting at the wrong sample rate.
%
%   Milestone: M1.  Blueprint: sections 3.7, 6.1.
%
%   See also COMPUTESTFT, RMSNORMALIZE, SPECTRALSUBTRACT.

if nargin < 3 || isempty(Cfg)
    Cfg = defaultConfig();
end

validateattributes(x, {'numeric'}, {'vector', 'real'}, mfilename, 'x');

if ~isempty(fs) && fs ~= Cfg.audio.fs
    error('HimigTransform:SampleRateMismatch', ...
        ['preprocessSignal received %g Hz audio but Cfg.audio.fs is %g Hz. ' ...
         'Resample with loadAudio or resampleAudio before calling this - ' ...
         'fingerprinting off-grid audio produces hashes that can never match.'], ...
        fs, Cfg.audio.fs);
end

sig = double(x(:));

if ~all(isfinite(sig))
    error('HimigTransform:NonFiniteAudio', ...
        'Signal contains %d non-finite sample(s).', nnz(~isfinite(sig)));
end

% ---- 1. DC removal ------------------------------------------------------
if Cfg.pre.dcRemove
    sig = sig - mean(sig);
end

% ---- 2. RMS normalisation ----------------------------------------------
sig = rmsNormalize(sig, Cfg.audio.targetRmsDbfs);

% ---- 3. Pre-emphasis ----------------------------------------------------
% filter() is base MATLAB. The first output sample is sig(1) because the
% filter state starts at zero, which is a one-sample edge effect identical on
% both sides of the pipeline and therefore harmless.
alpha = Cfg.pre.preemphAlpha;
if alpha ~= 0
    sig = filter([1, -alpha], 1, sig);
end

end