function Cfg = enhancedConfig()
%ENHANCEDCONFIG Proposed system - Enhancement 1 + Enhancement 2.
%
%   CFG = ENHANCEDCONFIG() returns DEFAULTCONFIG with both enhancements
%   enabled:
%
%     Enhancement 1  spectral-subtraction denoising (query side) plus
%                    SNR-adaptive peak picking (local-median threshold).
%     Enhancement 2  short-query mode - higher hash fan-out and a wider
%                    target zone for clips below shortQuery.thresholdSec,
%                    with the decision score normalised by query hash count.
%
%   NOTE ON THE INDEX (blueprint D4). The enrolment target zone is widened to
%   dtMax = 64 so that short-query hashes have something to collide with. That
%   makes this a DIFFERENT index from the baseline - build both, do not share
%   one superset index, or the baseline comparison is contaminated.
%
%   Long queries deliberately fall back to the baseline fan-out via
%   hash.queryFanout / hash.queryDtMax, so Enhancement 2 can be ablated
%   independently of the wider database.
%
%   TUNING. alpha, beta, kappaDb, freqDecim, tau and rho are all tuned on the
%   DEV split at M4-M5 and written back into this file BEFORE the test split
%   is touched at M7. Do not tune them anywhere else.
%
%   See also DEFAULTCONFIG, BASELINECONFIG, RESOLVEQUERYCONFIG.
%
%   Blueprint: sections 0 (D4), 3.3, 3.4, 3.6, 7 (M4-M5), 8.2.

Cfg = baselineConfig();

% Re-label: the tag must not claim to be the baseline.
Cfg.name = 'enh';

% --- Enhancement 1a: query-side spectral subtraction -----------------
Cfg.denoise.enable         = true;
Cfg.denoise.alpha          = 2.0;    % TUNE ON DEV (M4)
Cfg.denoise.beta           = 0.02;   % TUNE ON DEV (M4)
Cfg.denoise.noiseFrameFrac = 0.10;

% --- Enhancement 1b: SNR-adaptive peak picking -----------------------
% --- Shared with the baseline: everything the enhancements do NOT change ---
% The peak neighbourhood was moved from 21x21 to 17x17 at the M2/M3 boundary
% (docs/designNotes.md), and that change was made in BASELINECONFIG only.
% Both files derive from DEFAULTCONFIG, so the enhanced system silently kept
% 21x21 - a different peak geometry from the system it is supposed to be
% compared against.
%
% That is a confound, not a detail. Enhancement 1 is a claim about peak
% SELECTION under noise; measuring it against a baseline with a different peak
% NEIGHBOURHOOD means any difference mixes the two effects and nothing about
% the enhancement can be concluded from it.
%
% Inheriting from BASELINECONFIG rather than DEFAULTCONFIG makes the two
% systems share every parameter by construction, so the only differences are
% the ones written below. tSystemParity asserts it.

Cfg.peaks.mode    = 'adaptive';
Cfg.peaks.kappaDb = 6;               % TUNE ON DEV (M4)

% --- Enhancement 2: short-query mode ---------------------------------
Cfg.shortQuery.enable       = true;
Cfg.shortQuery.thresholdSec = 5;
Cfg.shortQuery.fanout       = 20;
Cfg.shortQuery.dtMax        = 64;

% --- Enrolment must be a superset of every query mode ----------------
Cfg.hash.fanout      = 20;   % database side
Cfg.hash.dtMax       = 64;   % database side - >= shortQuery.dtMax
Cfg.hash.queryFanout = 8;    % long queries stay at the baseline fan-out
Cfg.hash.queryDtMax  = 32;   % long queries stay in the baseline target zone

Cfg.tag = makeConfigTag(Cfg);

end
