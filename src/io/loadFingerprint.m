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

if ~isfield(S, 'cfgTag') || ~strcmp(S.cfgTag, Cfg.tag)
    if wantOk
        return
    end
    error('HimigTransform:StaleFingerprint', ...
        ['Cached fingerprint for songID %d was built under config tag "%s" but "%s" ' ...
         'was requested. Delete the cache directory and re-enrol.'], ...
        double(songID), S.cfgTag, Cfg.tag);
end

if ~isempty(expectedSha) && ~isempty(S.sha256) && ~strcmp(S.sha256, expectedSha)
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