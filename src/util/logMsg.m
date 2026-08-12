function logMsg(level, fmt, varargin)
%LOGMSG Single timestamped logging entry point.
%
%   LOGMSG(LEVEL, FMT, ...) prints a timestamped message. LEVEL is one of
%   'info', 'warn' or 'error'. FMT and the trailing arguments are passed
%   straight to SPRINTF, so the call site reads like FPRINTF:
%
%       logMsg('info', 'Ingested %d of %d files.', k, n);
%
%   'warn' and 'error' go to stderr (fid 2), 'info' to stdout. LOGMSG never
%   throws on your behalf - raising the error is the caller's job. This keeps
%   the log line and the exception independent, which matters inside try/catch
%   blocks where you want the message recorded even though you are recovering.
%
%   Verbosity is set once, globally, for the session:
%
%       logMsg('verbosity', 'warn');   % suppress info
%       logMsg('verbosity', 'info');   % back to the default
%
%   Long enrolment and evaluation runs produce a parseable transcript: use
%   diary() around a script and every line carries a timestamp and a level.
%
%   Milestone: M0.  Blueprint: section 4.
%
%   See also DIARY, SPRINTF.

persistent threshold
if isempty(threshold)
    threshold = 1;   % 1 = info, 2 = warn, 3 = error
end

levelNames = {'info', 'warn', 'error'};
level      = lower(char(level));

% ---- Verbosity control ------------------------------------------------
if strcmp(level, 'verbosity')
    idx = find(strcmp(lower(char(fmt)), levelNames), 1);
    if isempty(idx)
        error('HimigTransform:BadLogLevel', ...
            'Verbosity must be info, warn or error (got "%s").', char(fmt));
    end
    threshold = idx;
    return
end

% ---- Normal logging ---------------------------------------------------
idx = find(strcmp(level, levelNames), 1);
if isempty(idx)
    error('HimigTransform:BadLogLevel', ...
        'Unknown log level "%s" (expected info, warn or error).', level);
end

if idx < threshold
    return
end

if nargin < 2
    fmt = '';
end

msg   = sprintf(fmt, varargin{:});
stamp = char(datetime('now', 'Format', 'HH:mm:ss'));
line  = sprintf('[%s] %-5s %s\n', stamp, upper(level), msg);

if idx >= 2
    fprintf(2, '%s', line);
else
    fprintf(1, '%s', line);
end

end