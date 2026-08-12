function tests = tPeakBudget
%TPEAKBUDGET The configured peak density must be reachable, or flagged.
%
%   Two independent mechanisms limit constellation density: the local-maximum
%   neighbourhood (geometry) and Cfg.peaks.densityPerSec (a parameter). When
%   the target sits above the geometric ceiling the parameter is inert -
%   nothing errors, nothing warns, and density silently becomes whatever the
%   neighbourhood yields on that particular track.
%
%   These tests do two things. They check the audit's arithmetic, and they
%   pin the current configuration so that a later change to nbhdF, nbhdT,
%   densityPerSec, bandEdgesHz or the STFT grid cannot quietly move the
%   effective peak budget out from under a frozen baseline.
%
%   Milestone: M2.  Blueprint: section 3.3.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
setupPaths();
testCase.TestData.Cfg = baselineConfig();
end

function testCeilingArithmetic(testCase)
Cfg = testCase.TestData.Cfg;
a = peakBudgetAudit(Cfg);

expected = (Cfg.derived.frameRate / Cfg.peaks.nbhdT) ...
         * (Cfg.derived.nBins / Cfg.peaks.nbhdF);

verifyEqual(testCase, a.ceilingPerSec, expected, 'RelTol', 1e-12, ...
    'Ceiling is (frameRate/nbhdT) * (nBins/nbhdF).');
verifyEqual(testCase, a.targetPerSec, Cfg.peaks.densityPerSec);
verifyEqual(testCase, a.capCanBind, Cfg.peaks.densityPerSec < a.ceilingPerSec);
end

function testPerBandCeilingsSumToTheGlobalCeiling(testCase)
% The bands partition the spectrum, so their ceilings must add up to the
% global one (to within the rounding of bin edges onto the FFT grid).
Cfg = testCase.TestData.Cfg;
a = peakBudgetAudit(Cfg);

verifyLessThan(testCase, abs(a.achievableSum - a.ceilingPerSec), 0.5, ...
    'Per-band ceilings do not sum to the global ceiling.');
end

function testSuggestionIsTheLeastAggressiveThatWorks(testCase)
% The suggestion must be the LARGEST neighbourhood that clears the target,
% not the smallest. A small neighbourhood admits weak, closely spaced maxima
% that noise destroys first - which trades away exactly the robustness this
% project exists to measure.
Cfg = testCase.TestData.Cfg;
a = peakBudgetAudit(Cfg);

assumeFalse(testCase, isnan(a.suggestedNbhd), 'No suggestion to check.');

r = a.suggestedNbhd;
verifyEqual(testCase, mod(r, 2), 1, 'Neighbourhood must be odd.');

ceilAt = @(x) (Cfg.derived.frameRate / x) * (Cfg.derived.nBins / x);
verifyGreaterThanOrEqual(testCase, ceilAt(r), 1.5 * a.targetPerSec, ...
    'Suggested neighbourhood does not clear the target.');
verifyLessThan(testCase, ceilAt(r + 2), 1.5 * a.targetPerSec, ...
    'A larger neighbourhood would also have worked; suggestion is too aggressive.');
end

function testCurrentConfigurationIsPinned(testCase)
% DOCUMENTS THE KNOWN STATE rather than asserting a policy.
%
% At nbhd 21x21 the ceiling is 18.2 peaks/s against a target of 25, so the
% density cap cannot bind and Cfg.peaks.densityPerSec currently has no
% effect. Measured density on the 100-song corpus was 12.1/s.
%
% This is an open decision for M3 (docs/designNotes.md). Until it is settled
% this test holds the state still: if someone changes the neighbourhood, the
% target, the band edges or the STFT grid, this fails and forces the change
% to be deliberate rather than incidental.
Cfg = testCase.TestData.Cfg;
a = peakBudgetAudit(Cfg);

verifyEqual(testCase, [Cfg.peaks.nbhdF, Cfg.peaks.nbhdT], [21 21], ...
    'Neighbourhood changed. Re-measure density and update designNotes.');
verifyEqual(testCase, Cfg.peaks.densityPerSec, 25, ...
    'Density target changed. Re-run the audit and update designNotes.');
verifyFalse(testCase, a.capCanBind, ...
    ['The density cap now binds. That is the intended fix - update ' ...
     'docs/designNotes.md, re-measure accuracy, and correct this test.']);
end

function testCapBindsOnceTheNeighbourhoodShrinks(testCase)
% Proves the audit is measuring something real: the same target becomes
% reachable at the suggested neighbourhood.
Cfg = testCase.TestData.Cfg;
a = peakBudgetAudit(Cfg);

assumeFalse(testCase, isnan(a.suggestedNbhd), 'No suggestion available.');

Shrunk = Cfg;
Shrunk.peaks.nbhdF = a.suggestedNbhd;
Shrunk.peaks.nbhdT = a.suggestedNbhd;

b = peakBudgetAudit(Shrunk);
verifyTrue(testCase, b.capCanBind, ...
    'Cap still cannot bind at the suggested neighbourhood.');
end

function testNarrowBandsCannotFillAnEqualBudget(testCase)
% Structural, not a defect: the band edges are geometrically spaced, so band
% 1 holds 16 bins and band 5 holds 128. An equal per-band budget K means the
% low bands are ceiling-limited whatever the neighbourhood, and the realised
% density is dominated by the top band. Worth knowing before reading any
% figure that splits results by frequency.
Cfg = testCase.TestData.Cfg;
a = peakBudgetAudit(Cfg);

verifyLessThan(testCase, a.perBand.ceilingPerSec(1), a.perBand.budgetK(1), ...
    'Band 1 can now fill its budget; the band-edge analysis has changed.');
verifyGreaterThan(testCase, a.perBand.nBins(end), a.perBand.nBins(1), ...
    'Top band should be the widest under the configured edges.');
end
