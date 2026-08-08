function counts = alignOffsets(post, Tq, nSongs, Cfg)
%ALIGNOFFSETS Histogram time-offset differences per candidate song.
%
%   delta = t1_ref - Tq in integer frames, shifted into a positive range,
%   then
%   counts = accumarray([songID, delta], 1, [], @sum, 0, true) as a sparse
%   nSongs x nOffsets matrix.
%
%   Smooth by +/- Cfg.match.offsetTolFrames for the top Cfg.match.topK songs
%   ONLY - smoothing the whole sparse matrix is wasted work.
%
%   Milestone: M1.  Blueprint: section(s) 3.5.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also QUERYINDEX, SCORECANDIDATES.

error('HimigTransform:NotImplemented', ...
    'alignOffsets is a stub (Milestone M1). See docs/designNotes.md.');

end
