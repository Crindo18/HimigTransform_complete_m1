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

    case 'enh1'
        % ABLATION: Enhancement 1 alone - spectral subtraction on the query
        % plus adaptive peak picking - measured against the BASELINE
        % enrolment zone.
        %
        % The full enhanced system bundles three changes, and one of them
        % (the wider enrolment zone) affects every query while only paying
        % back on clips under 5 s. Without this variant a loss cannot be
        % attributed: the M7 test run came out 1.8 pp WORSE at 5 s and 1.6 pp
        % worse at 10 s, which is exactly where Enhancement 2 is switched off
        % and only the wider index is in play.
        Cfg = baselineConfig();
        Cfg.name = 'enh1';

        Cfg.peaks.mode     = 'adaptive';
        Cfg.denoise.enable = true;

        % Enrolment zone stays at the baseline's, so the index has the same
        % posting count and the same chance-collision floor.
        Cfg.shortQuery.enable = false;
        Cfg.hash.fanout       = 8;
        Cfg.hash.dtMax        = 32;
        Cfg.hash.queryFanout  = [];
        Cfg.hash.queryDtMax   = [];

        Cfg.tag = makeConfigTag(Cfg);

    case 'enh2'
        % ABLATION: Enhancement 2 alone - the wider enrolment zone and the
        % short-query fan-out - with baseline peak picking and no denoising.
        %
        % Read the 5 s and 10 s rows of this run carefully: at those lengths
        % the short-query override is inactive, so the query side is
        % IDENTICAL to the baseline and the only difference left is the
        % 2.3x larger index. Those two rows are a direct measurement of what
        % the wider enrolment zone costs on its own.
        Cfg = baselineConfig();
        Cfg.name = 'enh2';

        Cfg.peaks.mode     = 'fixed';
        Cfg.denoise.enable = false;

        Cfg.shortQuery.enable       = true;
        Cfg.shortQuery.thresholdSec = 5;
        Cfg.shortQuery.fanout       = 20;
        Cfg.shortQuery.dtMax        = 64;

        Cfg.hash.fanout      = 20;
        Cfg.hash.dtMax       = 64;
        Cfg.hash.queryFanout = 8;
        Cfg.hash.queryDtMax  = 32;

        Cfg.tag = makeConfigTag(Cfg);

    otherwise
        error('HimigTransform:UnknownSystem', ...
            ['Unknown system "%s". Expected baseline, enhanced, enh1 or ' ...
             'enh2. Every variant gets a named entry here rather than an ' ...
             'edited script, so the label and the config cannot disagree.'], ...
            name);
end

% The label the caller asked for must be the label the results carry.
Cfg.systemName = name;

end
