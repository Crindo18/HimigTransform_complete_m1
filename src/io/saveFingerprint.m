function saveFingerprint(fp, songID, Cfg)
%SAVEFINGERPRINT Write one song's fingerprint cache to db/fingerprints/<tag>/song_%04d.mat.
%
%   Per-song files make re-enrolment incremental after a code change rather
%   than all-or-nothing.
%
%   Milestone: M1.  Blueprint: section(s) 2.3.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also LOADFINGERPRINT, EXTRACTFINGERPRINT.

error('HimigTransform:NotImplemented', ...
    'saveFingerprint is a stub (Milestone M1). See docs/designNotes.md.');

end
