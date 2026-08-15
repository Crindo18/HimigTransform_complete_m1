function tests = tConfigTag
%TCONFIGTAG The tag must change with enrolment settings and only with those.
%
%   The tag keys the fingerprint cache and the index filename, so it has to be
%   correct in two directions and each failure looks different:
%
%   TOO STABLE is the dangerous one. A parameter that changes fingerprints
%   without changing the tag means a fresh index quietly assembled from stale
%   cached fingerprints. It builds, it queries, and every accuracy figure is
%   wrong with nothing to show for it. That happened here: nbhdF was not in
%   the tag, the 21x21 cache was reused after the move to 17x17, and the index
%   was written carrying a config it did not match.
%
%   TOO SENSITIVE is merely wasteful, but not free. A query-side parameter in
%   the tag forces a full re-extraction and a separate index file at every
%   point of an M4 alpha/beta sweep - a dozen byte-identical databases under a
%   dozen names.
%
%   Milestone: M0.  Blueprint: section(s) 2.1, 2.3, 6.4.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
setupPaths();
end

% =======================================================================
% Must change: anything that alters an enrolment fingerprint
% =======================================================================

function testTagChangesWithExtractionParameters(testCase)
mutations = {
    'peaks.nbhdF',        @(C) setfield(C, 'peaks', setfield(C.peaks, 'nbhdF', C.peaks.nbhdF + 2))
    'peaks.nbhdT',        @(C) setfield(C, 'peaks', setfield(C.peaks, 'nbhdT', C.peaks.nbhdT + 2))
    'peaks.densityPerSec',@(C) setfield(C, 'peaks', setfield(C.peaks, 'densityPerSec', C.peaks.densityPerSec + 1))
    'peaks.mode',         @(C) setfield(C, 'peaks', setfield(C.peaks, 'mode', 'adaptive'))
    'peaks.floorDb',      @(C) setfield(C, 'peaks', setfield(C.peaks, 'floorDb', C.peaks.floorDb - 5))
    'peaks.bandEdgesHz',  @(C) setfield(C, 'peaks', setfield(C.peaks, 'bandEdgesHz', [0 200 500 1000 2000 4000]))
    'stft.winLen',        @(C) setfield(C, 'stft',  setfield(C.stft,  'winLen', 1024))
    'stft.hop',           @(C) setfield(C, 'stft',  setfield(C.stft,  'hop', 128))
    'pre.preemphAlpha',   @(C) setfield(C, 'pre',   setfield(C.pre,   'preemphAlpha', 0.95))
    'audio.targetRmsDbfs',@(C) setfield(C, 'audio', setfield(C.audio, 'targetRmsDbfs', -14))
    'hash.fanout',        @(C) setfield(C, 'hash',  setfield(C.hash,  'fanout', 20))
    'hash.dtMax',         @(C) setfield(C, 'hash',  setfield(C.hash,  'dtMax', 64))
    'hash.dtMin',         @(C) setfield(C, 'hash',  setfield(C.hash,  'dtMin', 2))
    'hash.dfMaxBins',     @(C) setfield(C, 'hash',  setfield(C.hash,  'dfMaxBins', 32))
    'hash.freqDecim',     @(C) setfield(C, 'hash',  setfield(C.hash,  'freqDecim', 2))
    };

base    = baselineConfig();
baseTag = makeConfigTag(base);

for k = 1:size(mutations, 1)
    mutated = mutations{k, 2}(baselineConfig());
    verifyNotEqual(testCase, makeConfigTag(mutated), baseTag, ...
        sprintf(['Tag did not change after mutating %s. That field alters the ' ...
                 'stored fingerprint, so a stale cache would be reused silently.'], ...
                 mutations{k, 1}));
end
end

% =======================================================================
% Must NOT change: anything applied after extraction
% =======================================================================

function testTagIgnoresQuerySideAndDownstreamParameters(testCase)
mutations = {
    'match.tau',           @(C) setfield(C, 'match',      setfield(C.match,      'tau', 0.99))
    'match.rho',           @(C) setfield(C, 'match',      setfield(C.match,      'rho', 9.0))
    'match.maxPostingsPerHash', @(C) setfield(C, 'match', setfield(C.match, 'maxPostingsPerHash', 50))
    'denoise.enable',      @(C) setfield(C, 'denoise',    setfield(C.denoise,    'enable', true))
    'denoise.alpha',       @(C) setfield(C, 'denoise',    setfield(C.denoise,    'alpha', 3.0))
    'denoise.beta',        @(C) setfield(C, 'denoise',    setfield(C.denoise,    'beta', 0.05))
    'shortQuery.enable',   @(C) setfield(C, 'shortQuery', setfield(C.shortQuery, 'enable', true))
    'shortQuery.fanout',   @(C) setfield(C, 'shortQuery', setfield(C.shortQuery, 'fanout', 32))
    'hash.queryFanout',    @(C) setfield(C, 'hash',       setfield(C.hash,       'queryFanout', 20))
    'hash.queryDtMax',     @(C) setfield(C, 'hash',       setfield(C.hash,       'queryDtMax', 64))
    'eval.snrDb',          @(C) setfield(C, 'eval',       setfield(C.eval,       'snrDb', [Inf 10 0]))
    'eval.repsPerSong',    @(C) setfield(C, 'eval',       setfield(C.eval,       'repsPerSong', 5))
    'index.backend',       @(C) setfield(C, 'index',      setfield(C.index,      'backend', 'map'))
    };

base    = baselineConfig();
baseTag = makeConfigTag(base);

for k = 1:size(mutations, 1)
    mutated = mutations{k, 2}(baselineConfig());
    verifyEqual(testCase, makeConfigTag(mutated), baseTag, ...
        sprintf(['Tag changed after mutating %s. That field does not touch an ' ...
                 'enrolment fingerprint, so it must not invalidate the cache or ' ...
                 'fork the index filename.'], mutations{k, 1}));
end
end

% =======================================================================
% Determinism and shape
% =======================================================================

function testTagIsIndependentOfFieldOrder(testCase)
% JSONENCODE emits fields in creation order, so two configs holding identical
% values assembled in a different order would otherwise hash differently and
% invalidate a perfectly good cache.
Cfg1 = baselineConfig();

Cfg2 = Cfg1;
Cfg2.peaks = orderfields(Cfg2.peaks, flipud(fieldnames(Cfg2.peaks)));
Cfg2.stft  = orderfields(Cfg2.stft,  flipud(fieldnames(Cfg2.stft)));

verifyEqual(testCase, makeConfigTag(Cfg2), makeConfigTag(Cfg1), ...
    'Tag depends on struct field order.');
end

function testTagIsStableAcrossCalls(testCase)
Cfg = baselineConfig();
verifyEqual(testCase, makeConfigTag(Cfg), makeConfigTag(Cfg), ...
    'makeConfigTag is not deterministic within one session.');
end

function testTagIsAUsableFilename(testCase)
% The tag becomes a directory name and part of a .mat filename.
tag = makeConfigTag(baselineConfig());

verifyTrue(testCase, ischar(tag), 'Tag must be a char row vector.');
verifyEmpty(testCase, regexp(tag, '[^A-Za-z0-9_\-]', 'once'), ...
    sprintf('Tag "%s" contains a character that is unsafe in a filename.', tag));
verifyLessThan(testCase, numel(tag), 120, ...
    'Tag is long enough to risk MAX_PATH problems on Windows.');
end

function testTagCarriesAReadablePrefix(testCase)
% A pure hash makes two indexes indistinguishable by eye and reduces a
% stale-cache error to "one opaque string is not another".
Cfg = baselineConfig();
tag = makeConfigTag(Cfg);

verifySubstring(testCase, tag, sprintf('fs%d', round(Cfg.audio.fs)));
verifySubstring(testCase, tag, sprintf('n%d',  round(Cfg.peaks.nbhdF)));
verifySubstring(testCase, tag, sprintf('F%d',  round(Cfg.hash.fanout)));
end

function testHashMatchesTheFnvReference(testCase)
% Pins the hash to the published FNV-1a 32-bit test vectors. If someone swaps
% the implementation for a different one, every existing cache silently
% orphans - this makes that a deliberate act rather than a surprise.
verifyEqual(testCase, fnvOf(''),      '811c9dc5');
verifyEqual(testCase, fnvOf('hello'), '4f9f2cab');

    function h = fnvOf(s)
        % Mirrors the private helper in makeConfigTag.
        bytes = uint32(unicode2native(char(s), 'UTF-8'));
        hash  = uint64(2166136261);
        for i = 1:numel(bytes)
            hash = bitxor(hash, uint64(bytes(i)));
            hash = mod(hash * uint64(16777619), uint64(4294967296));
        end
        h = lower(dec2hex(hash, 8));
    end
end
