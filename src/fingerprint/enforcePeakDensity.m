function peaks = enforcePeakDensity(peaks, nFrames, Cfg)
%ENFORCEPEAKDENSITY Cap constellation density per second and per frequency band.
%
%   Two non-obvious requirements (blueprint 3.3):
%     (a) cap PER SECOND, not per song - otherwise a 6-minute track
%   dominates
%         the index and a 2-minute track is under-represented;
%     (b) cap PER BAND using Cfg.peaks.bandEdgesHz - without band-wise
%         selection every peak collapses into the bass region where music
%   has
%         most of its energy, and the mid-frequency structure that actually
%         discriminates songs is lost.
%
%   Milestone: M1.  Blueprint: section(s) 3.3.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also PICKPEAKS.

error('HimigTransform:NotImplemented', ...
    'enforcePeakDensity is a stub (Milestone M1). See docs/designNotes.md.');

end
