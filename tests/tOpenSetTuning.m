function tests = tOpenSetTuning
%TOPENSETTUNING The M5 open-set machinery: McNemar and threshold selection.
%
%   These are the two pieces the paper's headline claim rests on. The 10 pp
%   criterion is settled by a paired test, and every precision/recall/FAR
%   number depends on where the threshold was put and on which split.
%
%   Milestone: M5.  Blueprint: sections 8.2, 8.3, 8.4.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
setupPaths();
testCase.TestData.Cfg = baselineConfig();
end

% =======================================================================
% McNemar
% =======================================================================

function testExactPMatchesClosedForm(testCase)
% b = 10, c = 2, m = 12. Two-sided exact = 2 * P(X <= 2), X ~ Bin(12, 0.5)
%                                        = 2 * (1 + 12 + 66) / 4096
A = [true(10,1);  false(2,1); true(20,1);  false(20,1)];
B = [false(10,1); true(2,1);  true(20,1);  false(20,1)];

[p, s] = mcnemarTest(A, B);

verifyEqual(testCase, s.b, 10);
verifyEqual(testCase, s.c, 2);
verifyEqual(testCase, p, 2 * 79 / 4096, 'AbsTol', 1e-12, ...
    'Exact two-sided McNemar p does not match the closed form.');
end

function testConcordantPairsCarryNoInformation(testCase)
% Adding queries both systems get right, or both get wrong, must not move p.
% This is the property that makes the test paired, and it is easy to break by
% accidentally using the marginal counts.
A = [true(8,1);  false(3,1)];
B = [false(8,1); true(3,1)];
p1 = mcnemarTest(A, B);

pad = 500;
p2 = mcnemarTest([A; true(pad,1); false(pad,1)], ...
                 [B; true(pad,1); false(pad,1)]);

verifyEqual(testCase, p2, p1, 'AbsTol', 1e-12, ...
    'Concordant pairs changed the p-value; the test is not paired.');
end

function testIdenticalSystemsGivePOne(testCase)
[p, s] = mcnemarTest([true;false;true], [true;false;true]);
verifyEqual(testCase, p, 1);
verifyEqual(testCase, s.nDiscordant, 0);
end

function testSymmetricInItsArguments(testCase)
rng(3, 'twister');
A = rand(200,1) > 0.4;
B = rand(200,1) > 0.5;
verifyEqual(testCase, mcnemarTest(A,B), mcnemarTest(B,A), 'AbsTol', 1e-15);
end

function testLargeDiscordantCountStaysFinite(testCase)
% The gammaln path must not overflow where a factorial-based one would.
[p, s] = mcnemarTest([true(5000,1); false(5200,1)], ...
                     [false(5000,1); true(5200,1)]);
verifyEqual(testCase, s.nDiscordant, 10200);
verifyTrue(testCase, isfinite(p) && p > 0 && p <= 1);
end

function testUnpairedInputIsRejected(testCase)
verifyError(testCase, @() mcnemarTest(true(5,1), true(4,1)), ...
    'HimigTransform:UnpairedInputs');
end

% =======================================================================
% Threshold tuning
% =======================================================================

function testTestSplitRowsAreRefused(testCase)
% The single most important guard in M5. Tuning on the data you report is
% the failure a panel asks about.
R = syntheticDevResults();
R.split{7} = 'test';

verifyError(testCase, @() tuneThresholds(toTable(R), testCase.TestData.Cfg), ...
    'HimigTransform:NotDevSplit');
end

function testChosenPointRespectsTheFarBudget(testCase)
R = toTable(syntheticDevResults());
budget = 0.01;

[~, ~, sweep] = tuneThresholds(R, testCase.TestData.Cfg, 'FarBudget', budget);
k = sweep.Properties.UserData.chosenIdx;

verifyLessThanOrEqual(testCase, sweep.far(k), budget + 1e-12, ...
    'Chosen operating point exceeds the FAR budget.');
verifyGreaterThan(testCase, sweep.recall(k), 0.5, ...
    'Recall collapsed at this budget - check the sweep, not just the guard.');
end

function testFarIsMonotoneInTau(testCase)
% Raising tau can only reject more, so FAR must never increase. If this fails
% the sweep is not measuring what it claims.
R = toTable(syntheticDevResults());
[~, ~, sweep] = tuneThresholds(R, testCase.TestData.Cfg);

rhoVals = unique(sweep.rho);
sel = sweep.rho == rhoVals(1);
[~, ord] = sort(sweep.tau(sel));
far = sweep.far(sel);
far = far(ord);

verifyTrue(testCase, all(diff(far) <= 1e-12), ...
    'FAR increased as tau rose at fixed rho.');
end

function testMissingHoldoutIsAnError(testCase)
% Without holdout queries there is no FAR, so no open-set threshold can be
% chosen. Failing loudly beats returning a threshold tuned on nothing.
R = syntheticDevResults();
keep = R.isInDb;
f = fieldnames(R);
for k = 1:numel(f)
    R.(f{k}) = R.(f{k})(keep);
end

verifyError(testCase, @() tuneThresholds(toTable(R), testCase.TestData.Cfg), ...
    'HimigTransform:NoHoldout');
end

function testSnrRangeRestrictsTheTuningSet(testCase)
R = toTable(syntheticDevResults());

[~, ~, wide]   = tuneThresholds(R, testCase.TestData.Cfg, 'SnrRange', [-30 Inf]);
[~, ~, narrow] = tuneThresholds(R, testCase.TestData.Cfg, 'SnrRange', [0 Inf]);

verifyGreaterThan(testCase, wide.Properties.UserData.nInDb, ...
                            narrow.Properties.UserData.nInDb, ...
    'SnrRange did not restrict the tuning population.');
end

% =======================================================================
% System labelling
% =======================================================================

function testSystemConfigTiesTheLabelToTheConfig(testCase)
B = systemConfig('baseline');
E = systemConfig('enhanced');

verifyEqual(testCase, B.tag, baselineConfig().tag);
verifyEqual(testCase, E.tag, enhancedConfig().tag);
verifyNotEqual(testCase, B.tag, E.tag);
verifyEqual(testCase, B.systemName, 'baseline');
verifyEqual(testCase, E.systemName, 'enhanced');

verifyError(testCase, @() systemConfig('enhaced'), ...
    'HimigTransform:UnknownSystem');
end

% =======================================================================
function R = syntheticDevResults()
%SYNTHETICDEVRESULTS Dev-shaped results with realistic separation.

rng(11, 'twister');

n = 2000;
isInDb = [true(1500,1); false(500,1)];
snr    = repmat([Inf; 10; 5; 0; -10], n/5, 1);

ns   = zeros(n,1);
mg   = zeros(n,1);
corr = false(n,1);

for k = 1:n
    if isInDb(k)
        switch snr(k)
            case Inf, base = 0.30;
            case 10,  base = 0.26;
            case 5,   base = 0.20;
            case 0,   base = 0.13;
            otherwise, base = 0.03;
        end
        ns(k)   = max(0, base + 0.05 * randn());
        mg(k)   = max(1, 12 * ns(k) / 0.3 + 2 * randn());
        corr(k) = ns(k) > 0.05;
    else
        ns(k) = max(0, 0.012 + 0.010 * randn());
        mg(k) = max(1, 1.8 + 0.9 * randn());
    end
end

R = struct();
R.split       = repmat({'dev'}, n, 1);
R.isInDb      = isInDb;
R.correct     = corr;
R.normScore   = ns;
R.margin      = mg;
R.targetSnrDb = snr;
R.system      = repmat({'baseline'}, n, 1);

end

% =======================================================================
function T = toTable(R)
T = struct2table(R);
end
