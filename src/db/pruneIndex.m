function [Idx, stats] = pruneIndex(Idx, Cfg)
%PRUNEINDEX Drop hashes whose posting lists exceed Cfg.match.maxPostingsPerHash.
%
%   Near-universal hashes contribute nothing to discrimination and dominate
%   lookup cost - textbook IR stop-word pruning applied to fingerprints.
%   Log how many keys were dropped and report the effect on both accuracy
%   and
%   match time; it is a cheap half-paragraph of results.
%
%   Milestone: M2.  Blueprint: section(s) 6.5.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also BUILDINDEX, INDEXSTATS.

error('HimigTransform:NotImplemented', ...
    'pruneIndex is a stub (Milestone M2). See docs/designNotes.md.');

end
