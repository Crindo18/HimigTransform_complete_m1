function hash = sha256File(filePath)
%SHA256FILE SHA-256 checksum of a file, as a lowercase hex char row vector.
%
%   Used to fill catalog.sha256 so group members can verify they hold
%   byte-identical processed audio. Implement with
%   java.security.MessageDigest.
%
%   Milestone: M0.  Blueprint: section(s) 2.2.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also BUILDCATALOG.

error('HimigTransform:NotImplemented', ...
    'sha256File is a stub (Milestone M0). See docs/designNotes.md.');

end
