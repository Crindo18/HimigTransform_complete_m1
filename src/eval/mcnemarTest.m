function [p, stats] = mcnemarTest(correctA, correctB)
%MCNEMARTEST Paired significance test for baseline vs enhanced.
%
%   Exact binomial McNemar on the discordant pairs. Valid because the
%   manifest
%   pairs each query across systems: same excerpt, same noise segment, same
%   SNR. At n = 150 per cell the Wilson half-width is about +/- 5.7 pp, so a
%   claimed 10 pp gain needs this test rather than non-overlapping error
%   bars.
%
%   Milestone: M7.  Blueprint: section(s) 8.4.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also COMPUTEMETRICS.

error('HimigTransform:NotImplemented', ...
    'mcnemarTest is a stub (Milestone M7). See docs/designNotes.md.');

end
