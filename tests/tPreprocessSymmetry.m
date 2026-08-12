function tests = tPreprocessSymmetry
%TPREPROCESSSYMMETRY The reference and query paths must agree on clean input.
%
%   Blueprint 3.7 is a table of which stages run on which side. Every row is
%   ticked on both sides except spectral subtraction. An accidental asymmetry
%   does not crash - it shifts peak locations slightly, hashes stop colliding,
%   and accuracy quietly drops with nothing to point at.
%
%   Milestone: M1.  Blueprint: sections 3.7, 5.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
setupPaths();
Cfg = baselineConfig();
testCase.TestData.Cfg = Cfg;

rng(Cfg.seed, 'twister');

% Something with real spectral structure. White noise would pass an
% asymmetry test that music fails, because it has no tilt for pre-emphasis
% to act on and no peaks to displace.
fs = Cfg.audio.fs;
tt = (0:fs * 12 - 1)' / fs;
x  = 0.5 * sin(2 * pi * 440 * tt) ...
   + 0.3 * sin(2 * pi * 880 * tt) ...
   + 0.2 * sin(2 * pi * 1319 * tt) ...
   + 0.05 * randn(numel(tt), 1);
x(1:1000) = x(1:1000) .* linspace(0, 1, 1000)';

testCase.TestData.sig = x;
end

function testIdenticalPeaksOnIdenticalCleanInput(testCase)
% CONTRACT: the same clean signal fingerprinted twice - once as a reference,
% once as a query - gives bit-identical peaks and hashes.
Cfg = testCase.TestData.Cfg;
sig = testCase.TestData.sig;

fpRef = extractFingerprint(sig, Cfg);

CfgQ  = resolveQueryConfig(Cfg, numel(sig) / Cfg.audio.fs);
fpQry = extractFingerprint(sig, CfgQ);

verifyEqual(testCase, fpQry.peaks.tIdx, fpRef.peaks.tIdx, ...
    'Peak frames differ between the reference and query paths.');
verifyEqual(testCase, fpQry.peaks.fIdx, fpRef.peaks.fIdx, ...
    'Peak bins differ between the reference and query paths.');
verifyEqual(testCase, fpQry.hashes.h, fpRef.hashes.h, ...
    'Hashes differ between the reference and query paths.');
verifyEqual(testCase, fpQry.hashes.t1, fpRef.hashes.t1);
end

function testExtractionIsDeterministic(testCase)
% Two members must build byte-identical indexes from identical audio, so
% nothing in the chain may depend on RNG state or on hash-map iteration order.
Cfg = testCase.TestData.Cfg;
sig = testCase.TestData.sig;

rng(1, 'twister');   a = extractFingerprint(sig, Cfg);
rng(999, 'twister'); b = extractFingerprint(sig, Cfg);

verifyEqual(testCase, a.hashes.h,  b.hashes.h, 'Extraction is not deterministic.');
verifyEqual(testCase, a.peaks.tIdx, b.peaks.tIdx);
end

function testDenoiserIsQuerySideOnly(testCase)
% CONTRACT: baselineConfig never enables denoising, and enrolment never does
% either. The asymmetry in blueprint 3.7 must be the ONLY one, and it must
% point the right way - references are clean and are never denoised.
verifyFalse(testCase, baselineConfig().denoise.enable, ...
    'The baseline system must not denoise.');

Cfg = enhancedConfig();
verifyTrue(testCase, Cfg.denoise.enable, ...
    'The enhanced system should enable denoising (Enhancement 1a).');

% Resolving for the query side must not disturb any preprocessing stage.
CfgQ = resolveQueryConfig(Cfg, 3);
verifyEqual(testCase, CfgQ.pre, Cfg.pre, ...
    'resolveQueryConfig altered the preprocessing stages.');
verifyEqual(testCase, CfgQ.audio, Cfg.audio);
verifyEqual(testCase, CfgQ.stft, Cfg.stft);
end

function testPreprocessOrderIsDcThenRmsThenPreemph(testCase)
% Order matters (blueprint 3.7). A signal with a large DC offset must come out
% the same as the same signal without one - which is only true if DC removal
% precedes RMS normalisation.
Cfg = testCase.TestData.Cfg;
sig = testCase.TestData.sig;

a = preprocessSignal(sig,       Cfg.audio.fs, Cfg);
b = preprocessSignal(sig + 0.2, Cfg.audio.fs, Cfg);

verifyEqual(testCase, b, a, 'RelTol', 1e-9, ...
    'A DC offset changed the output - DC removal is not happening before RMS normalisation.');
end

function testPreemphasisIsAppliedAndReversible(testCase)
% The filter must actually run, and disabling it must be a real bypass.
Cfg = testCase.TestData.Cfg;
sig = testCase.TestData.sig;

withPre = preprocessSignal(sig, Cfg.audio.fs, Cfg);

CfgOff = Cfg;
CfgOff.pre.preemphAlpha = 0;
noPre = preprocessSignal(sig, Cfg.audio.fs, CfgOff);

verifyNotEqual(testCase, withPre(2:end), noPre(2:end), ...
    'Pre-emphasis had no effect.');

% Undoing the filter recovers the normalised signal, confirming the
% coefficients are the ones documented.
recovered = filter(1, [1, -Cfg.pre.preemphAlpha], withPre);
verifyEqual(testCase, recovered, noPre, 'RelTol', 1e-6, ...
    'Pre-emphasis is not (1 - alpha*z^-1) with alpha from Cfg.');
end

function testSampleRateMismatchIsRejected(testCase)
% Fingerprinting off-grid audio produces hashes that can never match. Fail
% loudly rather than silently.
Cfg = testCase.TestData.Cfg;
verifyError(testCase, ...
    @() preprocessSignal(randn(1000, 1), 44100, Cfg), ...
    'HimigTransform:SampleRateMismatch');
end

function testQueryConfigResolutionTiers(testCase)
% Live already: the three-tier resolution of blueprint 2.1 / 3.4.
Cfg = defaultConfig();

verifyEqual(testCase, resolveQueryConfig(Cfg, 10).hash.fanout, Cfg.hash.fanout, ...
    'Default query fan-out should inherit the enrolment value.');

Cfg2 = Cfg;
Cfg2.shortQuery.enable = true;
verifyEqual(testCase, resolveQueryConfig(Cfg2, 3).hash.fanout, Cfg2.shortQuery.fanout, ...
    'A short query should take the shortQuery fan-out.');
verifyEqual(testCase, resolveQueryConfig(Cfg2, 10).hash.fanout, Cfg.hash.fanout, ...
    'A long query should not take the shortQuery fan-out.');

% The guard: a query target zone wider than enrolment's can never match.
Cfg3 = Cfg;
Cfg3.shortQuery.enable = true;
Cfg3.shortQuery.dtMax  = Cfg.hash.dtMax + 10;
verifyWarning(testCase, @() resolveQueryConfig(Cfg3, 3), ...
    'HimigTransform:QueryZoneTooWide');
end