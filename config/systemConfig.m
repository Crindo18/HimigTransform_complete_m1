function Cfg = systemConfig(systemName)
%SYSTEMCONFIG Map a system NAME to its configuration. One source of truth.
%
%   CFG = SYSTEMCONFIG('baseline') returns BASELINECONFIG.
%   CFG = SYSTEMCONFIG('enhanced') returns ENHANCEDCONFIG.
%
%   WHY THIS EXISTS. The scripts previously hard-coded which config to build,
%   while a SEPARATE variable carried the system NAME into the results file,
%   the filename and the `system` column. Nothing tied the two together, so
%   setting s06_system = 'baseline' against a script hard-coded to
%   ENHANCEDCONFIG produced a file called results_baseline_*.csv, stamped
%   system = "baseline", containing enhanced numbers.
%
%   That failure is silent and total. Every downstream step - the metrics
%   table, the figures, the McNemar comparison - would read the label and
%   believe it. A McNemar test between two mislabelled files compares the
%   enhanced system against itself and reports no significant difference,
%   which looks exactly like a real negative result.
%
%   Deriving the config FROM the name makes the two impossible to disagree.
%
%   Milestone: M5.  Blueprint: sections 6.4, 8.4.
%
%   See also BASELINECONFIG, ENHANCEDCONFIG, S06_RUNEVALUATION.

narginchk(1, 1);

name = lower(strtrim(char(systemName)));

switch name
    case 'baseline'
        Cfg = baselineConfig();
    case 'enhanced'
        Cfg = enhancedConfig();
    otherwise
        error('HimigTransform:UnknownSystem', ...
            ['Unknown system "%s". Expected ''baseline'' or ''enhanced''. ' ...
             'Ablation runs (enh1 / enh2 alone) get their own named entry ' ...
             'here rather than an edited script - see docs/designNotes.md.'], ...
            name);
end

% The label the caller asked for must be the label the results carry.
Cfg.systemName = name;

end
