function tests = tSpectralSubtract
%TSPECTRALSUBTRACT The denoiser must preserve phase, respect the floor, and not broadcast sideways.
%
%   THE ORIENTATION TEST IS THE POINT OF THIS FILE. The subtraction relies on
%   implicit expansion of [nBins x nFrames] against [nBins x 1]. Hand it a ROW
%   of the same length and MATLAB errors for most query lengths - but not all.
%   At exactly nBins frames the two dimensions agree, expansion happens along
%   the wrong axis, and the noise estimate is subtracted across TIME instead of
%   frequency. At this STFT grid that is 257 frames, or 8.22 s: not one of the
%   3/5/10 s query lengths, which is precisely why it would have survived every
%   integration run and surfaced only when someone changed an excerpt length.
%
%   This project has hit that bug class twice already - repelem returning a row
%   for a 1x1 first argument, twice - and both times the failure needed one
%   specific size to appear. The guard is cheap; the test that keeps the guard
%   is cheaper than finding it a third time.
%
%   Milestone: M4.  Blueprint: section(s) 3.6, 3.7.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
setupPaths();
Cfg = defaultConfig();
testCase.TestData.Cfg   = Cfg;
testCase.TestData.nBins = Cfg.derived.nBins;
end

function S = makeSpectrogram(nBins, nFrames, seed)
stream = RandStream('twister', 'Seed', seed);
S = (0.5 + abs(randn(stream, nBins, nFrames))) .* ...
    exp(1i * 2 * pi * rand(stream, nBins, nFrames));
end

% =======================================================================
function testRejectsARowNoiseEstimateAtTheAmbiguousSize(testCase)
% The square case: nFrames == nBins, where implicit expansion would silently
% do the wrong thing rather than error.
Cfg   = testCase.TestData.Cfg;
nBins = testCase.TestData.nBins;

S    = makeSpectrogram(nBins, nBins, 1);
Nrow = abs(randn(1, nBins));

% A row of the right length is accepted and normalised to a column - the
% subtraction must still run down frequency, not across time.
SfromRow = spectralSubtract(S, Nrow,  Cfg);
SfromCol = spectralSubtract(S, Nrow(:), Cfg);

verifyEqual(testCase, SfromRow, SfromCol, 'AbsTol', 1e-12, ...
    ['A row noise estimate produced a different result from the same values ' ...
     'as a column - the subtraction broadcast along the wrong axis.']);
end

% =======================================================================
function testRejectsAWrongLengthNoiseEstimate(testCase)
Cfg   = testCase.TestData.Cfg;
nBins = testCase.TestData.nBins;

S = makeSpectrogram(nBins, 93, 2);

verifyError(testCase, @() spectralSubtract(S, abs(randn(nBins - 5, 1)), Cfg), ...
    'HimigTransform:NoiseSpectrumSizeMismatch');
end

% =======================================================================
function testPhaseIsPreservedExactly(testCase)
% Blueprint 3.6: the original phase is retained. Only the magnitude moves.
Cfg   = testCase.TestData.Cfg;
nBins = testCase.TestData.nBins;

S    = makeSpectrogram(nBins, 93, 3);
Nmag = 0.2 * abs(randn(nBins, 1));

Sclean = spectralSubtract(S, Nmag, Cfg);

live = abs(Sclean) > 1e-9 & abs(S) > 1e-9;
verifyEqual(testCase, angle(Sclean(live)), angle(S(live)), 'AbsTol', 1e-9, ...
    'Phase was altered by the denoiser.');
end

% =======================================================================
function testFloorIsRelativeToTheNoisyMagnitude(testCase)
% |Shat| = max(|Y| - alpha|N|, beta|Y|). Over-subtracting must never take the
% output below beta*|Y|, and never above |Y|.
Cfg   = testCase.TestData.Cfg;
nBins = testCase.TestData.nBins;

S = makeSpectrogram(nBins, 93, 4);

% A noise estimate large enough that the first term goes negative everywhere.
Nmag = 10 * max(abs(S(:))) * ones(nBins, 1);

Sclean = spectralSubtract(S, Nmag, Cfg);

verifyEqual(testCase, abs(Sclean), Cfg.denoise.beta * abs(S), 'RelTol', 1e-9, ...
    'Heavy over-subtraction did not settle on the beta*|Y| floor.');
end

% =======================================================================
function testZeroNoiseEstimateIsANoOp(testCase)
Cfg   = testCase.TestData.Cfg;
nBins = testCase.TestData.nBins;

S      = makeSpectrogram(nBins, 93, 5);
Sclean = spectralSubtract(S, zeros(nBins, 1), Cfg);

verifyEqual(testCase, Sclean, S, 'AbsTol', 1e-9, ...
    'A zero noise estimate changed the spectrogram.');
end

% =======================================================================
function testOutputNeverExceedsTheInputMagnitude(testCase)
Cfg   = testCase.TestData.Cfg;
nBins = testCase.TestData.nBins;

S      = makeSpectrogram(nBins, 93, 6);
Nmag   = 0.3 * abs(randn(nBins, 1));
Sclean = spectralSubtract(S, Nmag, Cfg);

verifyLessThanOrEqual(testCase, abs(Sclean), abs(S) + 1e-9, ...
    'Subtraction increased a magnitude.');
end

% =======================================================================
function testNoiseEstimateIsAlwaysAColumn(testCase)
% The other half of the guard: ESTIMATENOISESPECTRUM must never hand out a row.
Cfg   = testCase.TestData.Cfg;
nBins = testCase.TestData.nBins;

for nFrames = [93, 156, nBins, 312]
    Smag = abs(makeSpectrogram(nBins, nFrames, 7));
    Nmag = estimateNoiseSpectrum(Smag, Cfg);
    verifyEqual(testCase, size(Nmag), [nBins 1], ...
        sprintf('estimateNoiseSpectrum returned a %dx%d for %d frames.', ...
        size(Nmag, 1), size(Nmag, 2), nFrames));
end
end

% =======================================================================
function testNoiseEstimateUsesTheQuietestFrames(testCase)
% One loud frame must not move an estimate built from the quiet ones.
Cfg   = testCase.TestData.Cfg;
nBins = testCase.TestData.nBins;

Smag = 0.1 * ones(nBins, 100);
Nquiet = estimateNoiseSpectrum(Smag, Cfg);

Smag(:, 50) = 1000;
Nloud = estimateNoiseSpectrum(Smag, Cfg);

verifyEqual(testCase, Nloud, Nquiet, 'RelTol', 1e-9, ...
    'A single loud frame contaminated the noise estimate.');
end
