function tests = tPreprocessSymmetry
%TPREPROCESSSYMMETRY Reference and query paths must agree on clean input.
%
%   Blueprint 3.7 is the authoritative table: every preprocessing stage is
%   applied to both sides EXCEPT spectral subtraction, which is query-only.
%   Any accidental asymmetry silently destroys the match rate and looks like
%   an algorithm problem rather than a plumbing problem.
%
%   Milestone: M1.  Blueprint: sections 3.7, 5.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
setupPaths();
testCase.TestData.Cfg = baselineConfig();
end

function testIdenticalPeaksOnIdenticalCleanInput(testCase)
% CONTRACT: the enrolment path and the baseline query path produce identical
% peak sets from the same clean signal.
testCase.assumeFail('Pending: extractFingerprint not implemented (M1).');
end

function testDenoiserIsQuerySideOnly(testCase)
% CONTRACT: enrolment ignores Cfg.denoise.enable entirely - an enhanced-config
% enrolment must produce the same fingerprints as one with denoising off.
testCase.assumeFail('Pending: extractFingerprint not implemented (M1).');
end

function testResolveQueryConfigIsLive(testCase)
% Live already: config resolution is implemented, so test it properly.
Cfg = enhancedConfig();

short = resolveQueryConfig(Cfg, 3);
verifyEqual(testCase, short.hash.fanout, Cfg.shortQuery.fanout, ...
    'A 3 s query should take the short-query fan-out.');
verifyEqual(testCase, short.hash.dtMax, Cfg.shortQuery.dtMax);

long = resolveQueryConfig(Cfg, 10);
verifyEqual(testCase, long.hash.fanout, Cfg.hash.queryFanout, ...
    'A 10 s query should fall back to the baseline fan-out.');
verifyEqual(testCase, long.hash.dtMax, Cfg.hash.queryDtMax);

% The guard: a query zone wider than the enrolment zone must be clamped.
Bad = baselineConfig();
Bad.shortQuery.enable = true;
Bad.shortQuery.dtMax  = 999;
verifyWarning(testCase, @() resolveQueryConfig(Bad, 3), ...
    'HimigTransform:QueryZoneTooWide');
end
