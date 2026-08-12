function tests = tIndexBackendParity
%TINDEXBACKENDPARITY The csr and map backends must be interchangeable.
%
%   Blueprint D3 keeps containers.Map as the proposal-faithful backend while
%   defaulting to CSR for speed. That is only honest if the two return
%   identical postings - otherwise the benchmark reported in the paper
%   compares two different systems rather than one system against itself, and
%   the scalability claim collapses.
%
%   Milestone: M2.  Blueprint: sections 0 (D3), 2.4, 5.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
setupPaths();

Cfg = baselineConfig();
[catalog, sigs] = loadToyCorpus(testCase, Cfg);

dbRows = catalog(catalog.role == 'db', :);
assumeTrue(testCase, height(dbRows) >= 3, ...
    'Need at least 3 enrolled toy songs. Run s00_makeToySet.');

ids = double(dbRows.songID);
fps = cell(numel(ids), 1);
for k = 1:numel(ids)
    fps{k} = extractFingerprint(sigs(ids(k)), Cfg);
end

CfgCsr = Cfg; CfgCsr.index.backend = 'csr';
CfgMap = Cfg; CfgMap.index.backend = 'map';

testCase.TestData.Cfg    = Cfg;
testCase.TestData.sigs   = sigs;
testCase.TestData.ids    = ids;
testCase.TestData.fps    = fps;
testCase.TestData.IdxCsr = buildIndex(fps, ids, CfgCsr);
testCase.TestData.IdxMap = buildIndex(fps, ids, CfgMap);
end

% =======================================================================
% CSR structural invariants
% =======================================================================

function testCsrStructureIsWellFormed(testCase)
Idx = testCase.TestData.IdxCsr;

verifyTrue(testCase, issorted(Idx.hashKeys), 'hashKeys must be sorted.');
verifyEqual(testCase, numel(Idx.bucketPtr), numel(Idx.hashKeys) + 1);
verifyEqual(testCase, double(Idx.bucketPtr(end)), Idx.stats.nHashes + 1);
verifyEqual(testCase, numel(Idx.songID), Idx.stats.nHashes);
verifyEqual(testCase, numel(Idx.t1),     Idx.stats.nHashes);
verifyEqual(testCase, numel(unique(Idx.hashKeys)), numel(Idx.hashKeys), ...
    'hashKeys must be unique.');
end

function testSingleHashLookupReturnsAColumn(testCase)
% THE REGRESSION TEST. repelem returns a ROW when its first argument is 1x1,
% because a 1x1 array is simultaneously a row and a column vector. In the
% expansion inside queryIndex that made the subsequent subtraction broadcast
% into an M x M matrix, so every returned field came back square.
%
% This is invisible for a real query - thousands of postings across many keys
% means every intermediate is a genuine column - and appears ONLY when exactly
% one query hash matches exactly one bucket. Which is what this test does.
Idx = testCase.TestData.IdxCsr;

lens = double(diff(double(Idx.bucketPtr)));

j = find(lens >= 3, 1);
if isempty(j)
    j = find(lens >= 2, 1);
end
assumeNotEmpty(testCase, j, 'Toy corpus produced no multi-posting key.');

post = queryIndex(Idx, Idx.hashKeys(j));

verifySize(testCase, post.songID, [lens(j), 1], ...
    'Single-hash lookup must return an [M x 1] column, not a matrix.');
verifySize(testCase, post.t1,   [lens(j), 1]);
verifySize(testCase, post.qIdx, [lens(j), 1]);
verifyTrue(testCase, all(post.qIdx == 1), ...
    'Every posting from a single query hash must carry qIdx == 1.');
end

function testQueryIndexReturnsExactlyTheBucket(testCase)
Idx = testCase.TestData.IdxCsr;
rng(1, 'twister');

nSample = min(300, numel(Idx.hashKeys));
sampleKeys = randperm(numel(Idx.hashKeys), nSample);

for j = sampleKeys
    a = double(Idx.bucketPtr(j));
    b = double(Idx.bucketPtr(j + 1)) - 1;

    post = queryIndex(Idx, Idx.hashKeys(j));

    verifyEqual(testCase, double(post.songID), double(Idx.songID(a:b)), ...
        sprintf('Bucket %d contents differ.', j));
    verifyEqual(testCase, double(post.t1), double(Idx.t1(a:b)));
end
end

% =======================================================================
% Cross-backend parity
% =======================================================================

function testIdenticalPostingsForSameQuery(testCase)
IdxCsr = testCase.TestData.IdxCsr;
IdxMap = testCase.TestData.IdxMap;
Cfg    = testCase.TestData.Cfg;

verifyEqual(testCase, IdxMap.hashKeys, IdxCsr.hashKeys, ...
    'The two backends indexed different key sets.');
verifyEqual(testCase, IdxMap.stats.nHashes, IdxCsr.stats.nHashes);
verifyEqual(testCase, IdxMap.stats.nDistinct, IdxCsr.stats.nDistinct);

% A real query, then two deliberately degenerate ones.
fs   = Cfg.audio.fs;
sigs = testCase.TestData.sigs;
ids  = testCase.TestData.ids;

x  = sigs(ids(1));
q  = x(1 : min(8 * fs, numel(x)));
fp = extractFingerprint(q, resolveQueryConfig(Cfg, numel(q) / fs));

pc = queryIndex(IdxCsr, fp.hashes.h);
pm = queryIndex(IdxMap, fp.hashes.h);

verifyEqual(testCase, pm.qIdx,   pc.qIdx,   'qIdx differs between backends.');
verifyEqual(testCase, pm.songID, pc.songID, 'songID differs between backends.');
verifyEqual(testCase, pm.t1,     pc.t1,     't1 differs between backends.');

% Single hash, and a hash that is absent from both.
one = IdxCsr.hashKeys(1);
verifyEqual(testCase, queryIndex(IdxMap, one).songID, ...
                      queryIndex(IdxCsr, one).songID);

missing = intmax('uint32');
verifyEqual(testCase, numel(queryIndex(IdxMap, missing).songID), ...
                      numel(queryIndex(IdxCsr, missing).songID));
end

function testIdenticalDecisionsEndToEnd(testCase)
Cfg    = testCase.TestData.Cfg;
sigs   = testCase.TestData.sigs;
ids    = testCase.TestData.ids;
IdxCsr = testCase.TestData.IdxCsr;
IdxMap = testCase.TestData.IdxMap;
fs     = Cfg.audio.fs;

for k = 1:numel(ids)
    x = sigs(ids(k));
    lo = 1 + 3 * fs;
    hi = min(lo + 8 * fs - 1, numel(x));
    q = x(lo : hi);

    rc = identifyQuery(q, IdxCsr, Cfg);
    rm = identifyQuery(q, IdxMap, Cfg);

    verifyEqual(testCase, rm.pred1, rc.pred1, ...
        sprintf('Song %d: backends predicted differently.', ids(k)));
    verifyEqual(testCase, rm.score1, rc.score1, ...
        sprintf('Song %d: scores differ.', ids(k)));
    verifyEqual(testCase, rm.normScore, rc.normScore, 'AbsTol', 1e-12);
    verifyEqual(testCase, rm.accepted, rc.accepted);
end
end

% =======================================================================
% Pruning
% =======================================================================

function testPruningIsAppliedEqually(testCase)
Cfg = testCase.TestData.Cfg;
fps = testCase.TestData.fps;
ids = testCase.TestData.ids;

% Force the threshold low enough to actually bite on the toy corpus. At the
% default of 500 nothing is dropped, so a test using it would pass without
% exercising a single line of the pruning path.
CfgCsr = Cfg; CfgCsr.index.backend = 'csr'; CfgCsr.match.maxPostingsPerHash = 2;
CfgMap = Cfg; CfgMap.index.backend = 'map'; CfgMap.match.maxPostingsPerHash = 2;

[Pc, sc] = pruneIndex(buildIndex(fps, ids, CfgCsr), CfgCsr);
[Pm, sm] = pruneIndex(buildIndex(fps, ids, CfgMap), CfgMap);

verifyGreaterThan(testCase, sc.keysDropped, 0, ...
    'Threshold of 2 dropped nothing - the test is not exercising pruning.');

verifyEqual(testCase, sm.keysDropped,   sc.keysDropped,   'Key sets differ.');
verifyEqual(testCase, sm.postingsDropped, sc.postingsDropped);
verifyEqual(testCase, Pm.hashKeys, Pc.hashKeys, ...
    'The two backends kept different keys.');
verifyLessThanOrEqual(testCase, sc.maxPostingLenAfter, 2);
verifyLessThanOrEqual(testCase, sm.maxPostingLenAfter, 2);
end

function testPruningIsIdempotent(testCase)
Cfg = testCase.TestData.Cfg;
Cfg.match.maxPostingsPerHash = 2;

[P1, ~]  = pruneIndex(testCase.TestData.IdxCsr, Cfg);
[P2, s2] = pruneIndex(P1, Cfg);

verifyEqual(testCase, s2.keysDropped, 0, 'Second prune removed more keys.');
verifyEqual(testCase, P2.hashKeys, P1.hashKeys);
verifyEqual(testCase, P2.stats.nHashes, P1.stats.nHashes);
end

function testPruningPreservesSurvivingBuckets(testCase)
% Pruning must not disturb the postings of the keys it keeps. A rebuilt CSR
% offset table is easy to get subtly wrong, and the symptom would be a slow
% accuracy drift rather than an error.
Cfg = testCase.TestData.Cfg;
Cfg.match.maxPostingsPerHash = 2;

Idx = testCase.TestData.IdxCsr;
P   = pruneIndex(Idx, Cfg);

rng(2, 'twister');
sample = P.hashKeys(randperm(numel(P.hashKeys), min(200, numel(P.hashKeys))));

for j = 1:numel(sample)
    before = queryIndex(Idx, sample(j));
    after  = queryIndex(P,   sample(j));
    verifyEqual(testCase, after.songID, before.songID, ...
        'A surviving bucket changed contents during pruning.');
    verifyEqual(testCase, after.t1, before.t1);
end
end

function testDefaultThresholdIsInert(testCase)
% Documents the current operating point rather than asserting a policy: at
% Cfg.match.maxPostingsPerHash = 500 and a 100-song database whose largest
% posting list measured 261, pruning removes nothing. If a config change ever
% makes the default bite, this test fails and forces the decision to be
% deliberate.
Cfg = testCase.TestData.Cfg;
[~, s] = pruneIndex(testCase.TestData.IdxCsr, Cfg);
verifyEqual(testCase, s.keysDropped, 0, ...
    'The default threshold now prunes. Re-measure accuracy and match time.');
end

% =======================================================================
function [catalog, sigs] = loadToyCorpus(testCase, Cfg)
%LOADTOYCORPUS Read the toy catalog and its processed audio into memory.
%
%   Mirrors the loader in tSelfMatch. Both use ASSUMETRUE rather than
%   VERIFYTRUE so a member who has not yet run s00_makeToySet sees the suite
%   report these as pending rather than broken.

root    = setupPaths();
catPath = fullfile(root, 'db', 'catalogToy.csv');

assumeTrue(testCase, isfile(catPath), ...
    'db/catalogToy.csv not found. Run s00_makeToySet first.');

catalog = loadCatalog(Cfg, catPath);

sigs = containers.Map('KeyType', 'double', 'ValueType', 'any');

for k = 1:height(catalog)
    f = fullfile(root, 'data', 'toy', 'processed', ...
        strrep(char(catalog.procPath(k)), '/', filesep));
    assumeTrue(testCase, isfile(f), ...
        sprintf('Missing toy audio %s. Re-run s00_makeToySet.', catalog.procPath(k)));
    sigs(double(catalog.songID(k))) = audioread(f);
end

end
