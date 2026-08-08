function accepted = decideOpenSet(normScore, margin, Cfg)
%DECIDEOPENSET Apply the open-set accept rule: normScore >= tau AND margin >= rho.
%
%   tau and rho MUST be re-tuned per system. Enhanced mode emits more
%   hashes,
%   so nQueryHashes grows and normScore shifts. Reusing the baseline
%   threshold
%   on the enhanced system is the easiest way to report a number that does
%   not
%   survive questioning at the defence.
%
%   Milestone: M5.  Blueprint: section(s) 3.5, 8.3.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also TUNETHRESHOLDS, SCORECANDIDATES.

error('HimigTransform:NotImplemented', ...
    'decideOpenSet is a stub (Milestone M5). See docs/designNotes.md.');

end
