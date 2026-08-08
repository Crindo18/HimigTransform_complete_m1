function catalog = buildCatalog(fileList, Cfg)
%BUILDCATALOG Assemble the catalog table and assign songID, role and split.
%
%   songID is the primary key: assigned once, never reused, never
%   renumbered.
%   split is assigned at SONG level (blueprint 8.2) - splitting at query
%   level
%   leaks tuning data into the reported results.
%
%   Milestone: M0.  Blueprint: section(s) 2.2, 8.2.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also INGESTLIBRARY, LOADCATALOG.

error('HimigTransform:NotImplemented', ...
    'buildCatalog is a stub (Milestone M0). See docs/designNotes.md.');

end
