function tests = tSTFT
%TSTFT computeSTFT must reproduce the toolbox spectrogram exactly.
%
%   The hand-rolled STFT is the core DSP deliverable, so it needs an oracle.
%   spectrogram() is that oracle - the one place the Signal Processing Toolbox
%   version is allowed in the project.
%
%   Milestone: M1.  Blueprint: sections 3.1, 5.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
setupPaths();
testCase.TestData.Cfg = defaultConfig();
rng(testCase.TestData.Cfg.seed, 'twister');
testCase.TestData.sig = randn(8000 * 5, 1);   % 5 s of noise at fs = 8 kHz
end

function testMatchesToolboxSpectrogram(testCase)
% CONTRACT: max relative error < 1e-10 against spectrogram() using the same
% window, hop and nfft.
%
% White noise is the right probe here precisely because it excites every bin
% at every frame - a tonal signal would leave most of the spectrogram near
% zero, where a relative comparison is meaningless and a bug could hide.
assumeTrue(testCase, requireToolbox('signal', 'optional'), ...
    'Signal Processing Toolbox absent - the oracle is unavailable on this machine.');

Cfg = testCase.TestData.Cfg;
sig = testCase.TestData.sig;

S = computeSTFT(sig, Cfg);

w = hamming(Cfg.stft.winLen);   % periodic vs symmetric matters; MATLAB's
                                % hamming() is symmetric, and so is ours
nOverlap = Cfg.stft.winLen - Cfg.stft.hop;
Sref = spectrogram(sig, w, nOverlap, Cfg.stft.nfft);

verifySize(testCase, S, size(Sref), ...
    'computeSTFT and spectrogram disagree on output size.');

relErr = max(abs(S(:) - Sref(:))) / max(abs(Sref(:)));
verifyLessThan(testCase, relErr, 1e-10, ...
    sprintf('Max relative error vs spectrogram() is %.3e.', relErr));
end

function testWindowMatchesToolbox(testCase)
% If the window is wrong the oracle test fails in a way that looks like an FFT
% bug. Isolating it here means the failure names itself.
%
% TOLERANCE IS A FEW ULP, NOT ZERO. With literal coefficients this window is
% bit-identical to MATLAB's on R2025a, but hamming() is an undocumented
% internal implementation and pinning a test to its exact rounding would make
% the suite break on a future release for no real reason. A few ULP still
% catches every error that matters: a periodic-instead-of-symmetric window is
% out by ~1e-3, and an off-by-one in the (n-1) denominator by ~1e-5.
assumeTrue(testCase, requireToolbox('signal', 'optional'), ...
    'Signal Processing Toolbox absent.');

Cfg = testCase.TestData.Cfg;

% Recover the window: the STFT of a single impulse-at-zero frame is the FFT of
% the window itself, so an inverse transform hands it straight back.
imp = zeros(Cfg.stft.winLen, 1);
imp(1) = 1;

S = computeSTFT(imp, Cfg);
verifyEqual(testCase, size(S, 2), 1, 'Expected exactly one frame.');

% Both even and odd lengths, since the mirroring branches differ.
for n = [Cfg.stft.winLen, 511, 512, 7, 8, 1]
    wOurs = localWindow(n);
    wRef  = hamming(n);
    verifyEqual(testCase, wOurs, wRef, 'AbsTol', 4 * eps, ...
        sprintf('Hamming window of length %d does not match MATLAB''s.', n));
end
end

function testOutputGeometry(testCase)
% CONTRACT: S is [nBins x nFrames] with nBins = nfft/2 + 1 = 257 and
% nFrames = floor((numel(sig) - winLen)/hop) + 1. f is in Hz, t in seconds.
Cfg = testCase.TestData.Cfg;
sig = testCase.TestData.sig;

[S, f, t] = computeSTFT(sig, Cfg);

expFrames = floor((numel(sig) - Cfg.stft.winLen) / Cfg.stft.hop) + 1;

verifySize(testCase, S, [Cfg.derived.nBins, expFrames]);
verifyEqual(testCase, Cfg.derived.nBins, 257);
verifySize(testCase, f, [Cfg.derived.nBins, 1]);
verifySize(testCase, t, [expFrames, 1]);

verifyEqual(testCase, f(1),   0);
verifyEqual(testCase, f(2),   Cfg.derived.binWidthHz, 'AbsTol', 1e-12);
verifyEqual(testCase, f(end), Cfg.audio.fs / 2, 'AbsTol', 1e-9, ...
    'Top bin is not at Nyquist.');

% Frame centres, matching spectrogram's convention.
verifyEqual(testCase, t(2) - t(1), Cfg.stft.hop / Cfg.audio.fs, 'AbsTol', 1e-12);
end

function testShortSignalReturnsEmptyRatherThanErroring(testCase)
% A query can legitimately be shorter than one frame - the GUI lets someone
% record for a moment and stop. Returning an empty spectrogram lets the empty
% result propagate to a clean "no match" instead of an exception in the app.
Cfg = testCase.TestData.Cfg;

[S, f, t] = computeSTFT(randn(Cfg.stft.winLen - 1, 1), Cfg);

verifySize(testCase, S, [Cfg.derived.nBins, 0]);
verifySize(testCase, f, [Cfg.derived.nBins, 1]);
verifyEmpty(testCase, t);
end

function testTonePeaksInTheRightBin(testCase)
% Sanity beyond the oracle: a pure tone at a bin centre must land in that bin.
Cfg = testCase.TestData.Cfg;

binIdx = 65;                                   % 1000 Hz at the default grid
fHz    = (binIdx - 1) * Cfg.derived.binWidthHz;
n      = 8000;
tt     = (0:n - 1)' / Cfg.audio.fs;

S    = computeSTFT(sin(2 * pi * fHz * tt), Cfg);
mag  = mean(abs(S), 2);
[~, peakBin] = max(mag);

verifyEqual(testCase, peakBin, binIdx, ...
    sprintf('A %.1f Hz tone peaked in bin %d, not %d.', fHz, peakBin, binIdx));
end

function testDerivedGridIsConsistent(testCase)
% This one is live already: it checks the config arithmetic, not the DSP.
Cfg = testCase.TestData.Cfg;
verifyEqual(testCase, Cfg.derived.frameRate,  Cfg.audio.fs / Cfg.stft.hop);
verifyEqual(testCase, Cfg.derived.binWidthHz, Cfg.audio.fs / Cfg.stft.nfft);
verifyEqual(testCase, Cfg.derived.nBins,      Cfg.stft.nfft / 2 + 1);
verifyEqual(testCase, Cfg.derived.frameRate,  31.25, ...
    'Frame rate drifted from the 31.25 frames/s assumed throughout the blueprint.');
end

% =======================================================================
function w = localWindow(n)
%LOCALWINDOW Mirror of computeSTFT's private window builder, for testing it.
if n == 1
    w = 1;
    return
end
a0    = 0.54;   % literals, not (1 - a0) - see the note in computeSTFT
a1    = 0.46;
half  = ceil(n / 2);
k     = (0:half - 1)' / (n - 1);
wHalf = a0 - a1 * cos(2 * pi * k);
if mod(n, 2) == 0
    w = [wHalf; flipud(wHalf)];
else
    w = [wHalf; flipud(wHalf(1:end - 1))];
end
end