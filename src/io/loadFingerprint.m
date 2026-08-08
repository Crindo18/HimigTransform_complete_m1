function fp = loadFingerprint(songID, Cfg)
%LOADFINGERPRINT Read one song's cached fingerprint.
%
%   Errors if the cached cfgTag does not match Cfg.tag - a stale cache
%   silently
%   mixed into a fresh index is a very expensive bug to find later.
%
%   Milestone: M1.  Blueprint: section(s) 2.3.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also SAVEFINGERPRINT.

error('HimigTransform:NotImplemented', ...
    'loadFingerprint is a stub (Milestone M1). See docs/designNotes.md.');

end
