function tests = tHashPack
%THASHPACK packHash and unpackHash must be exact inverses.
%
%   The 32-bit layout is tight: 9 + 9 + 14 bits, whose maximum packed value is
%   exactly intmax('uint32'). An off-by-one in the shift silently corrupts
%   every hash in the database, and the symptom is simply "nothing matches" -
%   which is expensive to trace. Test the edges explicitly.
%
%   Milestone: M1.  Blueprint: sections 3.2, 5.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
setupPaths();
testCase.TestData.Cfg = defaultConfig();
end

function testRoundTripExhaustiveEdges(testCase)
% CONTRACT: unpackHash(packHash(f1,f2,dt)) == (f1,f2,dt) for the corners of
% the valid range: f in {0, 1, 256, 511}, dt in {0, 1, 64, 16383}.
Cfg = testCase.TestData.Cfg;

fVals  = [0 1 256 511];
dtVals = [0 1 64 16383];

[F1, F2, DT] = ndgrid(fVals, fVals, dtVals);
F1 = F1(:); F2 = F2(:); DT = DT(:);

h = packHash(F1, F2, DT, Cfg);

verifyClass(testCase, h, 'uint32');

[g1, g2, gd] = unpackHash(h, Cfg);

verifyEqual(testCase, g1, F1, 'Anchor bin did not survive the round trip.');
verifyEqual(testCase, g2, F2, 'Target bin did not survive the round trip.');
verifyEqual(testCase, gd, DT, 'Time delta did not survive the round trip.');
end

function testRoundTripRandom(testCase)
% CONTRACT: same, over a large random sample of the valid range.
Cfg = testCase.TestData.Cfg;
rng(Cfg.seed, 'twister');

n  = 20000;
F1 = randi([0 511],   n, 1);
F2 = randi([0 511],   n, 1);
DT = randi([0 16383], n, 1);

[g1, g2, gd] = unpackHash(packHash(F1, F2, DT, Cfg), Cfg);

verifyEqual(testCase, [g1 g2 gd], [F1 F2 DT]);
end

function testFieldsDoNotBleedIntoEachOther(testCase)
% The failure this catches: a shift that is off by one makes the top bit of dt
% land in f2, so hashes differ only when dt crosses a power of two - a bug
% that a coarse random test can easily miss.
Cfg = testCase.TestData.Cfg;

verifyEqual(testCase, packHash(0, 0, 0, Cfg), uint32(0));
verifyEqual(testCase, packHash(511, 511, 16383, Cfg), intmax('uint32'), ...
    'The maximum triple does not pack to intmax(uint32) - the layout is not tight.');

% Each field alone, at its lowest set bit.
verifyEqual(testCase, packHash(0, 0, 1, Cfg), uint32(1));
verifyEqual(testCase, packHash(0, 1, 0, Cfg), uint32(2^14));
verifyEqual(testCase, packHash(1, 0, 0, Cfg), uint32(2^23));

% dt at its maximum must not disturb f2.
verifyEqual(testCase, packHash(0, 0, 16383, Cfg), uint32(16383));
verifyEqual(testCase, packHash(0, 1, 16383, Cfg), uint32(2^14 + 16383));
end

function testDistinctTriplesGiveDistinctHashes(testCase)
% Losslessness stated directly: 200k distinct triples, 200k distinct codes.
Cfg = testCase.TestData.Cfg;
rng(Cfg.seed + 1, 'twister');

n = 200000;
T = unique([randi([0 511], n, 1), randi([0 511], n, 1), randi([0 16383], n, 1)], 'rows');

h = packHash(T(:,1), T(:,2), T(:,3), Cfg);

verifyEqual(testCase, numel(unique(h)), size(T, 1), ...
    'Two distinct (f1,f2,dt) triples collided - the packing is lossy.');
end

function testOverflowIsRejectedNotWrapped(testCase)
% Silently wrapping would produce a valid-looking hash for an invalid triple.
Cfg = testCase.TestData.Cfg;

verifyError(testCase, @() packHash(512, 0, 0, Cfg), 'HimigTransform:HashFieldOverflow');
verifyError(testCase, @() packHash(0, 512, 0, Cfg), 'HimigTransform:HashFieldOverflow');
verifyError(testCase, @() packHash(0, 0, 16384, Cfg), 'HimigTransform:HashFieldOverflow');
verifyError(testCase, @() packHash(-1, 0, 0, Cfg), 'HimigTransform:HashFieldOverflow');
end

function testFreqDecimIsAppliedBeforePacking(testCase)
% Blueprint 3.2's robustness knob. At freqDecim = 2 two bins one apart must
% collapse to the same hash - that IS the tolerance being bought. The round
% trip then returns decimated bins, which is lossy by design.
Cfg = testCase.TestData.Cfg;
Cfg.hash.freqDecim = 2;

verifyEqual(testCase, packHash(100, 200, 5, Cfg), packHash(101, 201, 5, Cfg), ...
    'freqDecim = 2 did not merge adjacent bins.');

verifyNotEqual(testCase, packHash(100, 200, 5, Cfg), packHash(102, 200, 5, Cfg), ...
    'freqDecim = 2 merged bins two apart - it is decimating too hard.');

[g1, g2, gd] = unpackHash(packHash(100, 200, 5, Cfg), Cfg);
verifyEqual(testCase, [g1 g2 gd], [50 100 5], ...
    'Unpacking should return decimated bins when freqDecim > 1.');

% And the decimated range must still fit its field.
verifyWarningFree(testCase, @() packHash(1022, 1022, 0, Cfg));
end

function testVectorisationAndBroadcasting(testCase)
Cfg = testCase.TestData.Cfg;

hv = packHash([1;2;3], 10, 4, Cfg);
verifySize(testCase, hv, [3 1]);
verifyEqual(testCase, hv(2), packHash(2, 10, 4, Cfg));

[g1, ~, ~] = unpackHash(hv, Cfg);
verifyEqual(testCase, g1, [1;2;3]);
end

function testMaxPackedValueFitsUint32(testCase)
% Live: pure arithmetic on the layout constants.
Cfg = testCase.TestData.Cfg;
maxF  = 2^Cfg.hash.freqBits - 1;
maxDt = 2^Cfg.hash.dtBits  - 1;
maxPacked = maxF * 2^(Cfg.hash.freqBits + Cfg.hash.dtBits) ...
          + maxF * 2^Cfg.hash.dtBits + maxDt;
verifyEqual(testCase, maxPacked, double(intmax('uint32')), ...
    'The 9/9/14 packing layout no longer fills a uint32 exactly.');
end

function testNBinsFitsInFreqField(testCase)
% Live: the frequency field must be wide enough for every STFT bin.
Cfg = testCase.TestData.Cfg;
verifyLessThanOrEqual(testCase, Cfg.derived.nBins - 1, 2^Cfg.hash.freqBits - 1, ...
    'nfft is too large for the 9-bit frequency field in the hash layout.');
end