function T = computeMetrics(R, groupVars)
%COMPUTEMETRICS Aggregate results into metrics with Wilson score confidence intervals.
%
%   Metric definitions are in blueprint 8.3 and must appear verbatim in the
%   paper - precision and recall are vacuous without the rejection rule:
%     closed-set top-1 accuracy   pred1 == songID, threshold ignored
%     identification accuracy     correct AND accepted
%     precision                   correct-and-accepted / all accepted
%     recall                      correct-and-accepted / all in-DB queries
%     FAR                         accepted holdout / all holdout
%   Report n in every cell.
%
%   Milestone: M3.  Blueprint: section(s) 8.3, 8.4.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also MCNEMARTEST, RUNEXPERIMENT.

error('HimigTransform:NotImplemented', ...
    'computeMetrics is a stub (Milestone M3). See docs/designNotes.md.');

end
