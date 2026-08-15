function tests = tMixSNR
%TMIXSNR mixAtSNR must hit the requested SNR to within 0.1 dB.
%
%   Every accuracy-versus-SNR figure in the paper rests on this being right.
%   If the mixer is off by 3 dB the whole x-axis is wrong and nothing
%   downstream will reveal it.
%
%   ONE OF THESE TESTS USED TO BE UNFALSIFIABLE. When mixAtSNR returned
%   10*log10(mean(x.^2)/mean((g*n).^2)) it was restating the gain it had just
%   solved for from those same two powers, so "measured equals target" held by
%   algebra regardless of what the function did to y. The mixer now measures
%   the noise back out of the returned signal, which is what makes the
%   assertions below capable of failing.
%
%   Milestone: M3.  Blueprint: section(s) 5, 6.2.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
setupPaths();
testCase.TestData.Cfg = defaultConfig();
end

% =======================================================================
function testMeasuredSnrMatchesTarget(testCase)
% CONTRACT: |snrMeasured - target| <= 0.1 dB across the evaluation grid and
% below it. -5 dB is not in Cfg.eval.snrDb but is kept here deliberately: it
% is where the noise gain is largest and the anti-clipping rescale most
% aggressive, so it is the boundary most likely to expose an arithmetic slip.
Cfg = testCase.TestData.Cfg;
stream = RandStream('twister', 'Seed', Cfg.seed);

x = randn(stream, 8000, 1) * 0.1;
n = randn(stream, 8000, 1) * 0.5;

targets = [20, 15, 10, 5, 0, -5];

for t = targets
    [~, ~, snrMeas] = mixAtSNR(x, n, t);
    verifyLessThanOrEqual(testCase, abs(snrMeas - t), 0.1, ...
        sprintf('Measured SNR (%.3f) differs from target (%.2f) by more than 0.1 dB.', ...
        snrMeas, t));
end
end

% =======================================================================
function testMeasuredSnrIsScaleInvariant(testCase)
% Rescaling signal and noise together must not move the ratio. This is the
% property blueprint 6.2 relies on when it rescales to avoid clipping, and it
% is worth asserting rather than assuming.
Cfg = testCase.TestData.Cfg;
stream = RandStream('twister', 'Seed', Cfg.seed);

x = randn(stream, 8000, 1) * 0.1;
n = randn(stream, 8000, 1) * 0.5;

[~, ~, s1] = mixAtSNR(x,      n,      5);
[~, ~, s2] = mixAtSNR(10 * x, 10 * n, 5);
[~, ~, s3] = mixAtSNR(x / 7,  n / 7,  5);

verifyLessThanOrEqual(testCase, abs(s1 - s2), 1e-9, ...
    'Scaling both inputs by 10 changed the measured SNR.');
verifyLessThanOrEqual(testCase, abs(s1 - s3), 1e-9, ...
    'Scaling both inputs down changed the measured SNR.');
end

% =======================================================================
function testNoClippingInOutput(testCase)
% CONTRACT: max(abs(y)) <= 1, and the rescale that achieves it leaves the SNR
% alone.
Cfg = testCase.TestData.Cfg;
stream = RandStream('twister', 'Seed', Cfg.seed);

% Large enough that the mixture must be rescaled.
x = randn(stream, 8000, 1);
n = randn(stream, 8000, 1);

[y, ~, snrMeas] = mixAtSNR(x, n, 0);

verifyLessThanOrEqual(testCase, max(abs(y)), 1.0, ...
    'Output clipped (max absolute value exceeded 1.0).');
verifyLessThanOrEqual(testCase, abs(snrMeas - 0), 0.1, ...
    'Rescaling changed the measured SNR.');
end

% =======================================================================
function testNoiseActuallyReachesTheOutput(testCase)
% The degenerate implementation - return x, report the target - passes every
% test above except this one.
Cfg = testCase.TestData.Cfg;
stream = RandStream('twister', 'Seed', Cfg.seed);

x = randn(stream, 8000, 1) * 0.1;
n = randn(stream, 8000, 1) * 0.5;

[y, g] = mixAtSNR(x, n, 10);

verifyGreaterThan(testCase, g, 0, 'Noise gain is zero at a finite SNR.');
verifyGreaterThan(testCase, norm(y - x), 0, ...
    'The mixture is identical to the clean signal; no noise was added.');
end

% =======================================================================
function testLowerSnrMeansMoreNoise(testCase)
% Monotonicity. A sign slip in the exponent satisfies "measured == target"
% while inverting the axis, and every curve in the paper would then run
% backwards.
Cfg = testCase.TestData.Cfg;
stream = RandStream('twister', 'Seed', Cfg.seed);

x = randn(stream, 8000, 1) * 0.1;
n = randn(stream, 8000, 1) * 0.5;

[~, gHigh] = mixAtSNR(x, n, 20);
[~, gLow]  = mixAtSNR(x, n, 0);

verifyGreaterThan(testCase, gLow, gHigh, ...
    'A lower target SNR did not produce a larger noise gain.');
end

% =======================================================================
function testCleanPassesThroughUnchanged(testCase)
% CONTRACT: snrDb = Inf returns x unmodified and g = 0.
Cfg = testCase.TestData.Cfg;
stream = RandStream('twister', 'Seed', Cfg.seed);

x = randn(stream, 8000, 1) * 0.5;
n = randn(stream, 8000, 1);

[y, g, snrMeas] = mixAtSNR(x, n, Inf);

verifyEqual(testCase, y, x, 'Signal was modified despite target SNR being Inf.');
verifyEqual(testCase, g, 0, 'Gain was not 0 for Inf SNR.');
verifyEqual(testCase, snrMeas, Inf, 'Measured SNR was not Inf.');
end

% =======================================================================
function testShortNoiseIsLoopedToLength(testCase)
Cfg = testCase.TestData.Cfg;
stream = RandStream('twister', 'Seed', Cfg.seed);

x = randn(stream, 8000, 1) * 0.1;
n = randn(stream, 1000, 1) * 0.5;

[y, ~, snrMeas] = mixAtSNR(x, n, 5);

verifyEqual(testCase, numel(y), numel(x), 'Output length does not match the signal.');
verifyLessThanOrEqual(testCase, abs(snrMeas - 5), 0.1, ...
    'Looping the noise moved the measured SNR.');
end

% =======================================================================
function testSilentExcerptReportsMinusInfNotPlusInf(testCase)
% A silent excerpt mixed with real noise has NO signal, so the honest measured
% SNR is -Inf. Reporting +Inf would relabel a broken excerpt as a clean query
% and quietly pollute the clean row of every results table.
Cfg = testCase.TestData.Cfg;
stream = RandStream('twister', 'Seed', Cfg.seed);

x = zeros(8000, 1);
n = randn(stream, 8000, 1) * 0.5;

[~, ~, snrMeas] = mixAtSNR(x, n, 0);

verifyEqual(testCase, snrMeas, -Inf, ...
    'A digitally silent excerpt was reported as +Inf SNR.');
end
