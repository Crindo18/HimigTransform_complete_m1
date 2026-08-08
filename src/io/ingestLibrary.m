function catalog = ingestLibrary(Cfg)
%INGESTLIBRARY Convert data/raw audio to 8 kHz mono WAV and build the catalog.
%
%   Walks data/raw/{american,opm,holdout}, writes data/processed/mono8k, and
%   returns the catalog table of blueprint 2.2. Idempotent: files already
%   processed and checksum-matched are skipped.
%
%   Milestone: M0.  Blueprint: section(s) 2.2, 7 (M0).
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also BUILDCATALOG, LOADAUDIO.

error('HimigTransform:NotImplemented', ...
    'ingestLibrary is a stub (Milestone M0). See docs/designNotes.md.');

end
