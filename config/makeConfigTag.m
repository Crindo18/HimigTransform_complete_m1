function tag = makeConfigTag(Cfg)
%MAKECONFIGTAG Deterministic filename tag keyed to the ENROLMENT config.
%
%   TAG = MAKECONFIGTAG(CFG) returns a tag of the form
%
%       base_fs8000_w512_h256_n17_d25_F8_dt32_fd1_fix_1a2b3c4d
%
%   a readable prefix naming the settings a reader cares about, followed by
%   eight hex characters hashing EVERY field that can change an enrolment
%   fingerprint. The tag keys the fingerprint cache directory and the index
%   filename.
%
%   WHAT IS HASHED, AND WHY THE QUERY-SIDE FIELDS ARE NOT
%
%   Hashed: audio, pre, stft, peaks, and the enrolment part of hash
%   (fanout, dtMin, dtMax, dfMaxBins, freqDecim). Change any of these and the
%   stored hashes are different numbers under the same names, so a cache built
%   before the change must not be reused after it. That failure mode is silent
%   - the index builds, queries run, and every accuracy figure is wrong in a
%   way no plot reveals - which is why the tag hashes rather than lists.
%
%   NOT hashed: denoise.*, shortQuery.*, hash.queryFanout, hash.queryDtMax,
%   match.*, eval.*, index.backend, seed, name. None of them touches an
%   enrolment fingerprint. Including the query-side ones (as an earlier version
%   did) is safe in the sense that it over-invalidates rather than under-, but
%   it has a real cost at M4: sweeping alpha and beta on dev would change the
%   tag at every sweep point, forcing a full re-extraction and writing a
%   separate index file for each - a dozen byte-identical databases under a
%   dozen names, and genuine ambiguity about which one "the baseline" is.
%
%   Results files still record the FULL Cfg (blueprint 6.4), so nothing about
%   the query side becomes untraceable; it is simply not part of the database
%   identity.
%
%   THE PREFIX IS NOT DECORATION. A pure hash is opaque: two indexes cannot be
%   told apart by eye, and a stale-cache error can only say that one tag is not
%   another, which tells nobody which field moved. The prefix restores that at
%   the cost of a longer filename.
%
%   NO JVM, NO TOOLBOX. The hash is FNV-1a over the serialised struct, in base
%   MATLAB integer arithmetic. The obvious alternative, java.security
%   .MessageDigest, is unavailable under -nojvm, which is a real configuration
%   on lab and cluster machines and precisely the sort of thing the M8
%   fresh-clone rehearsal is meant to catch. FNV-1a is not cryptographic and
%   does not need to be: it keys a cache, and 32 bits is ample for the handful
%   of configurations this project builds.
%
%   Field order is normalised before serialising, so two configs assembled in
%   a different order still hash the same.
%
%   CHANGING WHAT THIS FUNCTION HASHES CHANGES EVERY TAG. Existing fingerprint
%   caches and indexes become unreachable and must be rebuilt - s03_enroll does
%   that in about 12 s for 100 songs. The postings themselves are unaffected
%   whenever no extraction-relevant field moved.
%
%   Milestone: M0.  Blueprint: section(s) 2.1, 2.3, 2.4, 6.4.
%
%   See also DEFAULTCONFIG, BASELINECONFIG, FINGERPRINTCACHEDIR, LOADFINGERPRINT.

if ~isfield(Cfg, 'name') || isempty(Cfg.name)
    name = 'cfg';
else
    name = char(Cfg.name);
end

% ---- The extraction-relevant subset -------------------------------------
extCfg       = struct();
extCfg.audio = Cfg.audio;
extCfg.pre   = Cfg.pre;
extCfg.stft  = Cfg.stft;
extCfg.peaks = Cfg.peaks;

% Enrolment side of the hash config only. resolveQueryConfig owns the rest.
enrolHashFields = {'fanout', 'dtMin', 'dtMax', 'dfMaxBins', 'freqDecim'};
extCfg.hash = struct();
for k = 1:numel(enrolHashFields)
    f = enrolHashFields{k};
    if isfield(Cfg.hash, f)
        extCfg.hash.(f) = Cfg.hash.(f);
    end
end

% ---- Serialise deterministically ----------------------------------------
cfgStr = jsonencode(orderFieldsRecursive(extCfg));

% ---- Readable prefix ----------------------------------------------------
parts = { ...
    name, ...
    sprintf('fs%d',  round(Cfg.audio.fs)), ...
    sprintf('w%d',   round(Cfg.stft.winLen)), ...
    sprintf('h%d',   round(Cfg.stft.hop)), ...
    sprintf('n%d',   round(Cfg.peaks.nbhdF)), ...
    sprintf('d%d',   round(Cfg.peaks.densityPerSec)), ...
    sprintf('F%d',   round(Cfg.hash.fanout)), ...
    sprintf('dt%d',  round(Cfg.hash.dtMax)), ...
    sprintf('fd%d',  round(Cfg.hash.freqDecim)), ...
    peakModeAbbrev(Cfg.peaks.mode)};

if Cfg.peaks.nbhdT ~= Cfg.peaks.nbhdF
    % Only spell out the asymmetric case; the common one stays short.
    parts{5} = sprintf('n%dx%d', round(Cfg.peaks.nbhdF), round(Cfg.peaks.nbhdT));
end

tag = sprintf('%s_%s', strjoin(parts, '_'), fnv1a32(cfgStr));

end

% =======================================================================
function s = orderFieldsRecursive(s)
%ORDERFIELDSRECURSIVE Alphabetise field names at every level.
%
%   JSONENCODE emits fields in creation order, so two structs holding the same
%   values assembled in a different order serialise differently and hash
%   differently. Normalising removes that.

s = orderfields(s);
f = fieldnames(s);
for k = 1:numel(f)
    v = s.(f{k});
    if isstruct(v) && isscalar(v)
        s.(f{k}) = orderFieldsRecursive(v);
    end
end
end

% =======================================================================
function h = fnv1a32(str)
%FNV1A32 FNV-1a 32-bit hash of a char row vector, as 8 lowercase hex chars.

bytes = uint32(unicode2native(char(str), 'UTF-8'));

hash  = uint64(2166136261);      % FNV offset basis
prime = uint64(16777619);        % FNV prime
mask  = uint64(4294967296);      % 2^32

for k = 1:numel(bytes)
    hash = bitxor(hash, uint64(bytes(k)));
    hash = mod(hash * prime, mask);
end

h = lower(dec2hex(hash, 8));
end

% =======================================================================
function a = peakModeAbbrev(mode)
switch lower(char(mode))
    case 'fixed',    a = 'fix';
    case 'adaptive', a = 'adp';
    otherwise,       a = lower(char(mode));
end
end
