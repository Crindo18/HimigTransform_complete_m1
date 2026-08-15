function Cfg = defaultConfig()
%DEFAULTCONFIG Canonical HimigTransform configuration struct.
%
%   CFG = DEFAULTCONFIG() returns the complete parameter set for the
%   fingerprinting pipeline. Every function that has a tunable parameter
%   reads it from CFG. There are no magic numbers in function bodies.
%
%   CFG is serialised into every index and every results file, so any figure
%   can be traced back to the exact settings that produced it.
%
%   Do not call this directly for experiments - use BASELINECONFIG or
%   ENHANCEDCONFIG, which apply the system-specific overrides on top.
%
%   See also BASELINECONFIG, ENHANCEDCONFIG, MAKECONFIGTAG, RESOLVEQUERYCONFIG.
%
%   Blueprint: section 2.1.

Cfg = struct();

% =====================================================================
% Identity
% =====================================================================
Cfg.name = 'default';   % short prefix used by MAKECONFIGTAG
Cfg.seed = 42;          % rng(Cfg.seed,'twister') at the top of every script

% =====================================================================
% Audio ingest
% =====================================================================
Cfg.audio.fs             = 8000;   % Hz - retains the sub-4 kHz fingerprint band
Cfg.audio.mono           = true;
Cfg.audio.targetRmsDbfs  = -20;    % RMS, NOT peak. See blueprint 6.1: peak
                                   % normalisation makes loudness-war masters
                                   % and dynamic recordings behave differently
                                   % under a fixed peak-picking threshold, and
                                   % makes SNR mixing meaningless.

% =====================================================================
% Preprocessing  (applied IDENTICALLY to reference and query - see 3.7)
% =====================================================================
Cfg.pre.dcRemove     = true;
Cfg.pre.preemphAlpha = 0.97;   % set to 0 to disable; must match on both sides

% =====================================================================
% STFT grid
%   frameRate  = fs/hop     = 31.25 frames/s
%   binWidthHz = fs/nfft    = 15.625 Hz
%   nBins      = nfft/2 + 1 = 257
% =====================================================================
Cfg.stft.winLen = 512;         % samples = 64.0 ms
Cfg.stft.hop    = 256;         % samples = 32.0 ms (50% overlap)
Cfg.stft.nfft   = 512;
Cfg.stft.window = 'hamming';

% =====================================================================
% Peak picking / constellation map
% =====================================================================
Cfg.peaks.mode           = 'fixed';   % 'fixed' (baseline) | 'adaptive' (Enh 1b)
Cfg.peaks.nbhdF          = 21;        % bins   - local-max neighbourhood
Cfg.peaks.nbhdT          = 21;        % frames - local-max neighbourhood
Cfg.peaks.densityPerSec  = 25;        % target peaks/second AFTER the density cap
Cfg.peaks.bandEdgesHz    = [0 250 500 1000 2000 4000];
Cfg.peaks.floorDb        = -80;       % 'fixed' mode: global magnitude floor
Cfg.peaks.kappaDb        = 6;         % 'adaptive' mode: dB above the LOCAL median

% =====================================================================
% Combinatorial hashing
%
% Packing layout is fixed at 32 bits and must not be changed casually:
%     bits 31..23  f1  anchor bin   (freqBits = 9, values 0..511)
%     bits 22..14  f2  target bin   (freqBits = 9)
%     bits 13..0   dt  t2 - t1      (dtBits  = 14, values 0..16383)
% Maximum packed value is exactly intmax('uint32') - the layout is tight.
%
% Fan-out / target-zone resolution has three tiers (see RESOLVEQUERYCONFIG):
%     1. enrolment and default query     -> Cfg.hash.fanout / Cfg.hash.dtMax
%     2. query-side override (optional)  -> Cfg.hash.queryFanout / queryDtMax
%     3. short queries, when enabled     -> Cfg.shortQuery.fanout / dtMax
% =====================================================================
Cfg.hash.fanout      = 8;    % targets kept per anchor
Cfg.hash.dtMin       = 1;    % frames
Cfg.hash.dtMax       = 32;   % frames (~1.02 s)
Cfg.hash.dfMaxBins   = 64;   % max |f2 - f1| in bins
Cfg.hash.freqDecim   = 1;    % bin >> log2(freqDecim) before packing.
                             % 1 = full 15.6 Hz resolution; 2 = ~31 Hz, more
                             % tolerant of noise-induced peak drift. ABLATE
                             % THIS AT M4 rather than guessing (blueprint 3.2).
Cfg.hash.queryFanout = [];   % [] = inherit Cfg.hash.fanout
Cfg.hash.queryDtMax  = [];   % [] = inherit Cfg.hash.dtMax
Cfg.hash.freqBits    = 9;    % packing layout - treat as read-only
Cfg.hash.dtBits      = 14;   % packing layout - treat as read-only

% =====================================================================
% Spectral subtraction  (Enhancement 1a - QUERY SIDE ONLY)
% =====================================================================
Cfg.denoise.enable         = false;
Cfg.denoise.alpha          = 2.0;   % over-subtraction factor
Cfg.denoise.beta           = 0.02;  % spectral floor
Cfg.denoise.noiseFrameFrac = 0.10;  % fraction of lowest-energy frames used
                                    % for the noise magnitude estimate

% =====================================================================
% Short-query mode  (Enhancement 2 - QUERY SIDE ONLY)
% =====================================================================
Cfg.shortQuery.enable       = false;
Cfg.shortQuery.thresholdSec = 5;    % queries shorter than this use the overrides
Cfg.shortQuery.fanout       = 20;
Cfg.shortQuery.dtMax        = 64;   % must be <= the enrolment Cfg.hash.dtMax,
                                    % or the extra hashes can never match

% =====================================================================
% Index
% =====================================================================
Cfg.index.backend = 'csr';   % 'csr' (fast, default) | 'map' (containers.Map,
                             % proposal-faithful). Both must return identical
                             % postings - see tIndexBackendParity.

% =====================================================================
% Matching and open-set decision
% =====================================================================
Cfg.match.offsetTolFrames    = 1;     % +/- frames when smoothing the histogram
Cfg.match.topK               = 20;    % candidate songs kept for smoothing
Cfg.match.maxPostingsPerHash = 500;   % read by PRUNEINDEX at build time
Cfg.match.tau                = 0.02;  % normScore accept threshold  - TUNE ON DEV
Cfg.match.rho                = 1.50;  % top1/top2 margin threshold  - TUNE ON DEV

% =====================================================================
% Evaluation grid
% =====================================================================
Cfg.eval.lengthsSec        = [3 5 10];
Cfg.eval.snrDb = [Inf, 10, 5, 0, -5, -10, -15, -20, -25];   % proposal grid.
                             % Blueprint 12.2 recommends [Inf 20 15 10 5 0] so
                             % the curve has a visible knee instead of a cliff.
                             % Costs nothing - the harness already loops.
Cfg.eval.noiseTypes        = {'cafe', 'traffic', 'crowd'};
Cfg.eval.repsPerSong       = 3;      % raise to 5 if the 10 pp claim is marginal
Cfg.eval.devSongFrac       = 0.20;   % SONG-level split - never query-level
Cfg.eval.excerptEnergyGate = 0.5;    % reject excerpt windows below this fraction
                                     % of the track's median frame energy (R10)

% =====================================================================
% Derived - computed, never set by hand
% =====================================================================
Cfg.derived.frameRate  = Cfg.audio.fs / Cfg.stft.hop;      % 31.25 frames/s
Cfg.derived.binWidthHz = Cfg.audio.fs / Cfg.stft.nfft;     % 15.625 Hz
Cfg.derived.nBins      = Cfg.stft.nfft / 2 + 1;            % 257
Cfg.derived.winMs      = 1000 * Cfg.stft.winLen / Cfg.audio.fs;
Cfg.derived.hopMs      = 1000 * Cfg.stft.hop    / Cfg.audio.fs;

Cfg.tag = makeConfigTag(Cfg);

end
