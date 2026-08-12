function outFile = saveFingerprint(fp, songID, Cfg)
%SAVEFINGERPRINT Write one song's fingerprint cache to db/fingerprints/<tag>/song_%04d.mat.
%
%   OUTFILE = SAVEFINGERPRINT(FP, SONGID, CFG) writes FP (as returned by
%   EXTRACTFINGERPRINT) and returns the path written.
%
%   PER SONG, NOT ONE BIG FILE. Re-enrolment after a code change then costs
%   only the songs whose fingerprints actually changed, instead of the whole
%   catalogue every time. It also makes the cache safe to write from a parfor
%   loop: each worker owns its own file, so there is no shared handle and no
%   ordering dependency.
%
%   THE PROVENANCE FIELDS ARE THE POINT. Alongside the fingerprint the file
%   records cfgTag, the song's sha256 and the MATLAB release. LOADFINGERPRINT
%   refuses a cache whose cfgTag or checksum disagrees with what is being
%   asked for, which is what stops the single worst failure mode here: a stale
%   fingerprint from an older config silently mixed into a fresh index. That
%   index would build without complaint, query without error, and return
%   quietly wrong accuracy numbers.
%
%   Milestone: M1.  Blueprint: section 2.3.
%
%   See also LOADFINGERPRINT, EXTRACTFINGERPRINT, ENROLLDATABASE.

if nargin < 3 || isempty(Cfg)
    Cfg = defaultConfig();
end

cacheDir = fingerprintCacheDir(Cfg);

if ~isfolder(cacheDir)
    mkdir(cacheDir);
end

outFile = fullfile(cacheDir, sprintf('song_%04d.mat', double(songID)));

payload             = struct();
payload.fp          = fp;
payload.songID      = uint16(songID);
payload.cfgTag      = Cfg.tag;
payload.matlabVer   = version('-release');
payload.savedOn     = datetime('now');

if isfield(fp, 'meta') && isfield(fp.meta, 'sha256')
    payload.sha256 = fp.meta.sha256;
else
    payload.sha256 = '';
end

save(outFile, '-struct', 'payload', '-v7');

end