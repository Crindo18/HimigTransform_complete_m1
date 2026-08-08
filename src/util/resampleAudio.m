function y = resampleAudio(x, fsIn, fsOut)
%RESAMPLEAUDIO Anti-aliased sample-rate conversion.
%
%   Uses resample (Signal Processing Toolbox). REQUIRETOOLBOX must gate this
%   call so the failure is a clear message rather than an undefined
%   function.
%
%   Milestone: M0.  Blueprint: section(s) 1.2.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also LOADAUDIO, REQUIRETOOLBOX.

error('HimigTransform:NotImplemented', ...
    'resampleAudio is a stub (Milestone M0). See docs/designNotes.md.');

end
