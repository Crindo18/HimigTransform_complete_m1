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
testCase.assumeFail('Pending: computeSTFT not implemented (M1).');
end

function testOutputGeometry(testCase)
% CONTRACT: S is [nBins x nFrames] with nBins = nfft/2 + 1 = 257 and
% nFrames = floor((numel(sig) - winLen)/hop) + 1. f is in Hz, t in seconds.
testCase.assumeFail('Pending: computeSTFT not implemented (M1).');
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
