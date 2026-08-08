function sig = preprocessSignal(x, fs, Cfg)
%PREPROCESSSIGNAL DC removal, RMS normalisation and pre-emphasis.
%
%   Applied IDENTICALLY to reference and query. The only deliberate
%   asymmetry
%   in the whole pipeline is spectral subtraction, which is query-side only.
%   Blueprint 3.7 is the authoritative symmetry table; tPreprocessSymmetry
%   enforces it.
%
%   Milestone: M1.  Blueprint: section(s) 3.7, 6.1.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also COMPUTESTFT, SPECTRALSUBTRACT.

error('HimigTransform:NotImplemented', ...
    'preprocessSignal is a stub (Milestone M1). See docs/designNotes.md.');

end
