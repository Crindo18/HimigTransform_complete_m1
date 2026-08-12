function fp = extractFingerprint(sig, Cfg)
%EXTRACTFINGERPRINT Full fingerprint extraction for one signal: preprocess to hashes.
%
%   FP = EXTRACTFINGERPRINT(SIG, CFG) runs the whole front end:
%
%       preprocessSignal -> computeSTFT -> [spectralSubtract] -> pickPeaks
%                        -> enforcePeakDensity -> makeHashes
%
%   SIG must already be mono at Cfg.audio.fs. Returns the struct of blueprint
%   2.3: fp.peaks (tIdx, fIdx, magDb) and fp.hashes (h, t1), plus fp.meta.
%
%   THE SINGLE ENTRY POINT SHARED BY ENROLMENT AND QUERY. That is what keeps
%   the two paths symmetric (blueprint 3.7), and it is worth being stubborn
%   about. The failure it prevents is not a crash - it is a silent one: any
%   difference between how a reference and a query are turned into peaks
%   shifts the constellation slightly, hashes stop colliding, and the symptom
%   is simply lower accuracy with nothing obviously wrong anywhere. Two
%   separate code paths that "do the same thing" drift apart within a week.
%
%   THE ONE DELIBERATE ASYMMETRY is spectral subtraction, and it is gated on
%   Cfg.denoise.enable, which the enrolment config never sets. It is applied
%   to the STFT between the transform and the peak picker, which is the only
%   place it can go: it needs the complex spectrum, and the peak picker needs
%   the cleaned magnitudes.
%
%   Milestone: M1.  Blueprint: sections 2.3, 3.7.
%
%   See also ENROLLDATABASE, IDENTIFYQUERY, PICKPEAKS, MAKEHASHES.

if nargin < 2 || isempty(Cfg)
    Cfg = defaultConfig();
end

sig = preprocessSignal(sig, Cfg.audio.fs, Cfg);

S = computeSTFT(sig, Cfg);

% ---- Enhancement 1a, query side only (M4) ------------------------------
if Cfg.denoise.enable
    Nmag = estimateNoiseSpectrum(abs(S), Cfg);
    S    = spectralSubtract(S, Nmag, Cfg);
end

Smag = abs(S);

peaks = pickPeaks(Smag, Cfg);

[h, t1] = makeHashes(peaks, Cfg);

fp                 = struct();
fp.peaks           = peaks;
fp.hashes.h        = h;
fp.hashes.t1       = t1;

fp.meta.cfgTag      = Cfg.tag;
fp.meta.nFrames     = size(Smag, 2);
fp.meta.durationSec = numel(sig) / Cfg.audio.fs;
fp.meta.nPeaks      = numel(peaks.tIdx);
fp.meta.nHashes     = numel(h);
fp.meta.builtOn     = datetime('now');
fp.meta.matlabVer   = version('-release');

end