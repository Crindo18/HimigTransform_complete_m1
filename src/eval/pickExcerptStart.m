function startSample = pickExcerptStart(sig, lengthSec, Cfg)
%PICKEXCERPTSTART Choose an excerpt start, gated on frame energy.
%
%   Risk R10: an excerpt landing on an intro, a fade-out or silence fails
%   for
%   reasons that have nothing to do with the algorithm. Reject candidate
%   windows whose mean frame energy falls below Cfg.eval.excerptEnergyGate
%   times the track median, and log the rejection rate.
%
%   Milestone: M3.  Blueprint: section(s) 9 (R10).
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also BUILDQUERYMANIFEST.

error('HimigTransform:NotImplemented', ...
    'pickExcerptStart is a stub (Milestone M3). See docs/designNotes.md.');

end
