function R = runExperiment(M, Idx, Cfg, systemName)
%RUNEXPERIMENT Run the evaluation grid and return long-format results.
%
%   One row per (query x system) with the columns of blueprint 2.6. Long
%   format, not wide - every figure is then a groupsummary away.
%
%   Embeds Cfg, Cfg.tag, the MATLAB version and the git commit hash in the
%   saved file so any number in the paper traces back to what produced it.
%
%   Milestone: M3.  Blueprint: section(s) 2.6, 6.4, 8.1.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also COMPUTEMETRICS, SYNTHESIZEQUERY.

error('HimigTransform:NotImplemented', ...
    'runExperiment is a stub (Milestone M3). See docs/designNotes.md.');

end
