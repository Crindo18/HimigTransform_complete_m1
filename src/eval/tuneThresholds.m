function [tau, rho, sweep] = tuneThresholds(Rdev, Cfg)
%TUNETHRESHOLDS Sweep the open-set thresholds on the DEV split only.
%
%   THE TEST SPLIT IS TOUCHED EXACTLY ONCE, AT M7. Tuning a threshold on the
%   data you then report is the most common way a project like this produces
%   a
%   number it cannot defend at the panel.
%
%   Returns the chosen operating point plus the full sweep for the ROC
%   figure.
%   Write the chosen tau and rho back into enhancedConfig.m before M7.
%
%   Milestone: M5.  Blueprint: section(s) 8.2, 8.4.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also DECIDEOPENSET, PLOTOPENSETROC.

error('HimigTransform:NotImplemented', ...
    'tuneThresholds is a stub (Milestone M5). See docs/designNotes.md.');

end
