function fp = extractFingerprint(sig, Cfg)
%EXTRACTFINGERPRINT Full fingerprint extraction for one signal: preprocess to hashes.
%
%   The single entry point shared by enrolment and query, which is what
%   keeps
%   the two paths symmetric (blueprint 3.7). Returns the struct of blueprint
%   2.3: fp.peaks (tIdx, fIdx, magDb) and fp.hashes (h, t1).
%
%   Milestone: M1.  Blueprint: section(s) 2.3, 3.7.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also ENROLLDATABASE, IDENTIFYQUERY.

error('HimigTransform:NotImplemented', ...
    'extractFingerprint is a stub (Milestone M1). See docs/designNotes.md.');

end
