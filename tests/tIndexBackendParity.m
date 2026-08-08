function tests = tIndexBackendParity
%TINDEXBACKENDPARITY The csr and map backends must be interchangeable.
%
%   Blueprint D3 keeps containers.Map as the proposal-faithful backend while
%   defaulting to CSR for speed. That is only honest if the two return
%   identical postings - otherwise the reported benchmark compares two
%   different systems, and the paper's scalability claim collapses.
%
%   Milestone: M2.  Blueprint: sections 0 (D3), 2.4, 5.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
setupPaths();
testCase.TestData.Cfg = baselineConfig();
end

function testIdenticalPostingsForSameQuery(testCase)
% CONTRACT: queryIndex returns the same (songID, t1) multiset from both
% backends for the same query hashes, on the toy database.
testCase.assumeFail('Pending: buildIndexCsr/buildIndexMap not implemented (M2).');
end

function testIdenticalDecisionsEndToEnd(testCase)
% CONTRACT: identifyQuery returns the same pred1 and score1 under both.
testCase.assumeFail('Pending: buildIndexCsr/buildIndexMap not implemented (M2).');
end

function testPruningIsApplidEqually(testCase)
% CONTRACT: pruneIndex drops the same key set from both backends.
testCase.assumeFail('Pending: pruneIndex not implemented (M2).');
end
