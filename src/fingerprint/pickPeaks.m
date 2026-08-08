function peaks = pickPeaks(Smag, Cfg)
%PICKPEAKS Dispatch to the fixed or adaptive peak picker, then cap density.
%
%   Reads Cfg.peaks.mode. Always applies ENFORCEPEAKDENSITY afterwards, so
%   both modes are compared at the same peak budget - otherwise the adaptive
%   picker could 'win' simply by emitting more peaks.
%
%   Milestone: M1.  Blueprint: section(s) 3.3.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also PICKPEAKSFIXED, PICKPEAKSADAPTIVE, ENFORCEPEAKDENSITY.

error('HimigTransform:NotImplemented', ...
    'pickPeaks is a stub (Milestone M1). See docs/designNotes.md.');

end
