function Cfg = baselineConfig()
%BASELINECONFIG Frozen reference system - Wang/Shazam-style fingerprinting.
%
%   CFG = BASELINECONFIG() returns DEFAULTCONFIG with the baseline overrides
%   applied explicitly. Nothing here relies on a default value staying put:
%   every setting that distinguishes the baseline from the enhanced system is
%   written out, so that changing a default later cannot silently redefine
%   what "baseline" means.
%
%   This configuration is frozen at Milestone M3 and git-tagged
%   v0.1-baseline-frozen. Every later comparison points at that tag.
%
%   See also DEFAULTCONFIG, ENHANCEDCONFIG.
%
%   Blueprint: sections 0 (D1), 2.1, 7 (M2-M3).

Cfg = defaultConfig();

Cfg.name = 'base';

% --- No enhancements -------------------------------------------------
Cfg.peaks.mode        = 'fixed';   % global magnitude floor, not local median
Cfg.denoise.enable    = false;     % no spectral subtraction on the query
Cfg.shortQuery.enable = false;     % one fan-out for every query length

% --- Freeze peak neighbourhood at 17x17 so density cap binds ---
Cfg.peaks.nbhdF       = 17;
Cfg.peaks.nbhdT       = 17;

% --- Baseline hashing ------------------------------------------------
Cfg.hash.fanout      = 8;
Cfg.hash.dtMin       = 1;
Cfg.hash.dtMax       = 32;
Cfg.hash.freqDecim   = 1;
Cfg.hash.queryFanout = [];   % query side inherits the enrolment settings
Cfg.hash.queryDtMax  = [];

Cfg.tag = makeConfigTag(Cfg);

end
