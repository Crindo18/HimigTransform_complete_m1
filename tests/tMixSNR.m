function tests = tMixSNR
%TMIXSNR mixAtSNR must hit the requested SNR to within 0.1 dB.
%
%   Every accuracy-versus-SNR figure in the paper rests on this being right.
%   If the mixer is off by 3 dB the whole x-axis is wrong and nothing
%   downstream will reveal it.
%
%   Milestone: M3.  Blueprint: sections 5, 6.2.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
setupPaths();
testCase.TestData.Cfg = defaultConfig();
end

function testMeasuredSnrMatchesTarget(testCase)
% CONTRACT: |snrMeasured - target| <= 0.1 dB for target in
% [Inf 20 10 5 0 -5], across several signal/noise power ratios.
testCase.assumeFail('Pending: mixAtSNR not implemented (M3).');
end

function testNoClippingInOutput(testCase)
% CONTRACT: max(abs(y)) <= 1. Rescaling the mixture to avoid clipping must NOT
% change the measured SNR.
testCase.assumeFail('Pending: mixAtSNR not implemented (M3).');
end

function testCleanPassesThroughUnchanged(testCase)
% CONTRACT: snrDb = Inf returns x unmodified and g = 0.
testCase.assumeFail('Pending: mixAtSNR not implemented (M3).');
end
