function tf = requireToolbox(name, mode)
%REQUIRETOOLBOX Check for a toolbox licence and dispatch to a fallback or fail clearly.
%
%   mode is 'require' (error if absent) or 'optional' (return false so the
%   caller can take the base-MATLAB path). Blueprint 1.2 lists the required
%   toolboxes and their fallbacks. The point is to fail at setup with a
%   readable message, not at integration week with an undefined function.
%
%   Milestone: M0.  Blueprint: section(s) 1.2.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.

error('HimigTransform:NotImplemented', ...
    'requireToolbox is a stub (Milestone M0). See docs/designNotes.md.');

end
