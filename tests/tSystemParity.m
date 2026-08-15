function tests = tSystemParity
%TSYSTEMPARITY The two systems must differ ONLY by the enhancements.
%
%   Enhancement 1 is a claim about peak SELECTION under noise and Enhancement
%   2 a claim about hash FAN-OUT on short queries. Both are measured as a
%   difference between two full systems, so every parameter that is not part
%   of an enhancement has to be identical. If it is not, the measured
%   difference mixes effects and nothing can be concluded from it.
%
%   This has already happened once. The peak neighbourhood moved from 21x21
%   to 17x17 at the M2/M3 boundary, the change was made in BASELINECONFIG,
%   and ENHANCEDCONFIG - deriving separately from DEFAULTCONFIG - silently
%   kept 21x21. Nothing errored; the two systems simply stopped being
%   comparable. ENHANCEDCONFIG now inherits from BASELINECONFIG, and these
%   tests hold that property still.
%
%   Milestone: M4.  Blueprint: sections 3.7, 7 (M4), 8.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
setupPaths();
testCase.TestData.B = baselineConfig();
testCase.TestData.E = enhancedConfig();
end

function testSharedParametersAreIdentical(testCase)
% Every field that is NOT part of an enhancement must match exactly.
B = testCase.TestData.B;
E = testCase.TestData.E;

verifyEqual(testCase, E.audio, B.audio, 'audio settings diverged.');
verifyEqual(testCase, E.pre,   B.pre,   'preprocessing settings diverged.');
verifyEqual(testCase, E.stft,  B.stft,  'STFT grid diverged.');

% Peak picking: mode and kappaDb ARE Enhancement 1. Everything else is not.
sharedPeakFields = {'nbhdF', 'nbhdT', 'densityPerSec', 'bandEdgesHz', 'floorDb'};
for k = 1:numel(sharedPeakFields)
    f = sharedPeakFields{k};
    verifyEqual(testCase, E.peaks.(f), B.peaks.(f), ...
        sprintf(['Cfg.peaks.%s differs between systems (baseline %s, ' ...
                 'enhanced %s). It is not part of either enhancement, so a ' ...
                 'difference here confounds the comparison.'], ...
            f, mat2str(B.peaks.(f)), mat2str(E.peaks.(f))));
end

% Hashing: fanout and dtMax ARE Enhancement 2. The packing is not.
sharedHashFields = {'dtMin', 'dfMaxBins', 'freqDecim', 'freqBits', 'dtBits'};
for k = 1:numel(sharedHashFields)
    f = sharedHashFields{k};
    verifyEqual(testCase, E.hash.(f), B.hash.(f), ...
        sprintf('Cfg.hash.%s differs between systems.', f));
end
end

function testEnhancementsAreActuallyOn(testCase)
B = testCase.TestData.B;
E = testCase.TestData.E;

verifyEqual(testCase, B.peaks.mode, 'fixed');
verifyFalse(testCase, B.denoise.enable);
verifyFalse(testCase, B.shortQuery.enable);

verifyEqual(testCase, E.peaks.mode, 'adaptive', 'Enhancement 1b is off.');
verifyTrue(testCase, E.denoise.enable,          'Enhancement 1a is off.');
verifyTrue(testCase, E.shortQuery.enable,       'Enhancement 2 is off.');
end

function testTagsDifferAndNameTheSystem(testCase)
B = testCase.TestData.B;
E = testCase.TestData.E;

verifyNotEqual(testCase, E.tag, B.tag, ...
    'The two systems share a config tag; their indexes would collide.');
verifyTrue(testCase, startsWith(B.tag, 'base'), 'Baseline tag mislabelled.');
verifyTrue(testCase, startsWith(E.tag, 'enh'),  'Enhanced tag mislabelled.');
end

function testBaselineChangesPropagateToEnhanced(testCase)
% The actual guarantee: editing baselineConfig must move the enhanced system
% too. Deriving enhancedConfig from defaultConfig would break this silently.
E = testCase.TestData.E;
B = testCase.TestData.B;

verifyEqual(testCase, E.peaks.nbhdF, B.peaks.nbhdF, ...
    ['enhancedConfig does not track baselineConfig''s neighbourhood. ' ...
     'It must derive FROM baselineConfig, not from defaultConfig.']);
verifyEqual(testCase, E.peaks.densityPerSec, B.peaks.densityPerSec);
end

function testEnrolmentZoneCoversEveryQueryMode(testCase)
% Enhancement 2 widens the query target zone on short clips. Hashes outside
% the ENROLMENT zone can never collide, so the database zone has to be at
% least as wide as any query mode will ask for. Getting this wrong is silent:
% the symptom is simply that short queries stop matching.
E = testCase.TestData.E;

verifyGreaterThanOrEqual(testCase, E.hash.dtMax, E.shortQuery.dtMax, ...
    'Short-query dtMax exceeds the enrolment target zone.');
verifyGreaterThanOrEqual(testCase, E.hash.fanout, E.shortQuery.fanout, ...
    'Short-query fan-out exceeds the enrolment fan-out.');

if ~isempty(E.hash.queryDtMax)
    verifyGreaterThanOrEqual(testCase, E.hash.dtMax, E.hash.queryDtMax);
end
end
