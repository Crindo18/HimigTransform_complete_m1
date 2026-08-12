function d = fingerprintCacheDir(Cfg)
%FINGERPRINTCACHEDIR Path of the per-config fingerprint cache.
%
%   D = FINGERPRINTCACHEDIR(CFG) returns db/fingerprints/<cfgTag>, the
%   directory blueprint 2.3 specifies. Keyed by config tag so that two
%   configurations never share a cache, which is what makes a clean ablation
%   at M4 a matter of changing the tag rather than remembering to delete
%   things.
%
%   Milestone: M1.  Blueprint: section 2.3.
%
%   See also SAVEFINGERPRINT, LOADFINGERPRINT.

%   The project root is cached in a persistent, because ENROLLDATABASE reaches
%   this function once per song inside a parfor and SETUPPATHS does real work
%   on every call. The root cannot move mid-session, so caching it is free.

persistent projRoot

if nargin < 1 || isempty(Cfg)
    Cfg = defaultConfig();
end

if isempty(projRoot)
    projRoot = setupPaths();
end

d = fullfile(projRoot, 'db', 'fingerprints', Cfg.tag);

end