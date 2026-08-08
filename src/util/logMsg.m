function logMsg(level, fmt, varargin)
%LOGMSG Single timestamped logging entry point.
%
%   level is one of 'info', 'warn', 'error'. Everything that prints progress
%   goes through here, so verbosity can be changed in one place and long
%   enrolment or evaluation runs produce a parseable transcript.
%
%   Milestone: M0.  Blueprint: section(s) 4.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.

error('HimigTransform:NotImplemented', ...
    'logMsg is a stub (Milestone M0). See docs/designNotes.md.');

end
