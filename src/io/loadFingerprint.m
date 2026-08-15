function [fp, ok] = loadFingerprint(songID, Cfg, expectedSha)
%LOADFINGERPRINT Read one song's cached fingerprint, refusing a stale one.
%
%   FP = LOADFINGERPRINT(SONGID, CFG) reads the cache and errors if it is
%   missing or stale.
%
%   [FP, OK] = LOADFINGERPRINT(...) returns OK = false instead of erroring
%   when the cache is missing or stale, with FP = []. That is the form
%   ENROLLDATABASE uses, since a cache miss there is routine rather than
%   exceptional - it just means the song needs extracting.
%
%   [...] = LOADFINGERPRINT(SONGID, CFG, EXPECTEDSHA) additionally requires
%   the cached checksum to match the catalog's, so re-ripping a song
%   invalidates its fingerprint even when the config has not moved.
%
%   WHY THE STALENESS CHECK IS NOT OPTIONAL. A fingerprint cache is keyed by
%   config tag precisely because the fingerprint IS a function of the config -
%   change winLen, or freqDecim, or the fan-out, and the hashes are different
%   numbers with the same names. An index assembled from a mixture of old and
%   new fingerprints builds without error and queries without error, and every
%   accuracy figure that comes out of it is wrong in a way no plot will show.
%   Erroring on a tag mismatch converts that into one clear sentence.
%
%   Milestone: M1.  Blueprint: section 2.3.
%
%   See also SAVEFINGERPRINT, ENROLLDATABASE.

if nargin < 2 || isempty(Cfg)
    Cfg = defaultConfig();
end
if nargin < 3
    expectedSha = '';
end

wantOk = nargout >= 2;

fp = [];
ok = false;

f = fullfile(fingerprintCacheDir(Cfg), sprintf('song_%04d.mat', double(songID)));

if ~isfile(f)
    if wantOk
        return
    end
    error('HimigTransform:FingerprintNotCached', ...
        'No cached fingerprint for songID %d at %s.', double(songID), f);
end

S = load(f);

% The stale-cache branch must never itself throw. Reading S.cfgTag inside the
% error() call was fine when the field existed and raised "Reference to
% non-existent field 'cfgTag'" when it did not - replacing the one clear
% sentence this function exists to produce with MATLAB's least helpful
% message, in exactly the case (a cache written by an older version) where the
% clear sentence matters most.
if isfield(S, 'cfgTag')
    cachedTag = char(S.cfgTag);
else
    cachedTag = '<none recorded>';
end

if ~isfield(S, 'cfgTag') || ~strcmp(cachedTag, Cfg.tag)
    if wantOk
        return
    end
    error('HimigTransform:StaleFingerprint', ...
        ['Cached fingerprint for songID %d was built under config tag "%s" but "%s" ' ...
         'was requested.%s\nDelete %s and re-enrol.'], ...
        double(songID), cachedTag, Cfg.tag, tagDiffHint(S, Cfg), fileparts(f));
end

if isfield(S, 'sha256')
    cachedSha = char(S.sha256);
else
    cachedSha = '';
end

if ~isempty(expectedSha) && ~isempty(cachedSha) && ~strcmp(cachedSha, expectedSha)
    if wantOk
        return
    end
    error('HimigTransform:FingerprintChecksumMismatch', ...
        ['Cached fingerprint for songID %d was built from a different audio file ' ...
         '(checksum mismatch). Re-enrol this song.'], double(songID));
end

fp = S.fp;
ok = true;

end

% =======================================================================
function hint = tagDiffHint(S, Cfg)
%TAGDIFFHINT Name the fields that differ, when the cache recorded its config.
%
%   The tag is a hash, so "tag A is not tag B" is true and useless. SAVEFINGERPRINT
%   stores the extraction config alongside the fingerprint precisely so this
%   function can say WHICH field moved. Older caches predate that field, in
%   which case there is nothing to diff and the message stays as it was.

hint = '';

if ~isfield(S, 'extCfg') || ~isstruct(S.extCfg)
    return
end

try
    changed = diffStruct(S.extCfg, currentExtCfg(Cfg), '');
catch
    return
end

if isempty(changed)
    return
end

hint = sprintf('\nChanged since the cache was written: %s.', strjoin(changed, ', '));

end

% =======================================================================
function e = currentExtCfg(Cfg)
e       = struct();
e.audio = Cfg.audio;
e.pre   = Cfg.pre;
e.stft  = Cfg.stft;
e.peaks = Cfg.peaks;
f = {'fanout', 'dtMin', 'dtMax', 'dfMaxBins', 'freqDecim'};
e.hash = struct();
for k = 1:numel(f)
    if isfield(Cfg.hash, f{k})
        e.hash.(f{k}) = Cfg.hash.(f{k});
    end
end
end

% =======================================================================
function changed = diffStruct(a, b, prefix)
changed = {};
names   = union(fieldnames(a), fieldnames(b));
for k = 1:numel(names)
    nm   = names{k};
    path = nm;
    if ~isempty(prefix)
        path = [prefix '.' nm]; %#ok<AGROW>
    end

    if ~isfield(a, nm) || ~isfield(b, nm)
        changed{end+1} = path; %#ok<AGROW>
        continue
    end

    va = a.(nm);
    vb = b.(nm);

    if isstruct(va) && isstruct(vb)
        changed = [changed, diffStruct(va, vb, path)]; %#ok<AGROW>
    elseif ~isequal(va, vb)
        if isnumeric(va) && isnumeric(vb) && isscalar(va) && isscalar(vb)
            changed{end+1} = sprintf('%s (%g -> %g)', path, va, vb); %#ok<AGROW>
        else
            changed{end+1} = path; %#ok<AGROW>
        end
    end
end
end