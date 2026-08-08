function peaks = pickPeaksFixed(Smag, Cfg)
%PICKPEAKSFIXED Baseline constellation: 2-D local maxima above a global magnitude floor.
%
%   A bin is a peak if it is the maximum over a Cfg.peaks.nbhdF x nbhdT
%   neighbourhood and exceeds Cfg.peaks.floorDb.
%
%   Milestone: M1.  Blueprint: section(s) 3.3.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also PICKPEAKS, PICKPEAKSADAPTIVE.

error('HimigTransform:NotImplemented', ...
    'pickPeaksFixed is a stub (Milestone M1). See docs/designNotes.md.');

end
