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
testCase.assumeFail('Pending: packHash/unpackHash not implemented (M1).');
end

function testRoundTripRandom(testCase)
% CONTRACT: same, over a large random sample of the valid range.
testCase.assumeFail('Pending: packHash/unpackHash not implemented (M1).');
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
