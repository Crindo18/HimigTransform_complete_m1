function res = identifyQuery(sig, Idx, Cfg)
%IDENTIFYQUERY The online entry point: audio in, identification decision out.
%
%   RES = IDENTIFYQUERY(SIG, IDX, CFG) resolves the query config for the clip
%   length, extracts the fingerprint, looks up postings, aligns time offsets,
%   scores candidates and applies the open-set rule.
%
%   SIG must be mono at Cfg.audio.fs. RES contains:
%
%       pred1, score1     top-1 songID and its aligned count
%       pred2, score2     runner-up
%       normScore         score1 / nQueryHashes
%       margin            score1 / max(score2, 1)
%       accepted          normScore >= tau AND margin >= rho
%       nQueryHashes      hashes emitted by this clip
%       nCandidateSongs   songs with at least one aligned hash
%       tHashSec          fingerprint extraction time
%       tMatchSec         lookup + align + score time
%       tTotalSec         the two above, which is the number blueprint 6.3 times
%       offsetHist        [nOffsets x 1] histogram for the winner (GUI figure)
%       offsetFrames      the matching frame-offset axis
%       bestOffsetFrames  where the winning spike sat
%       peaks             the query constellation (GUI overlay)
%       topPred, topScore the full top-K ranking for the GUI results table
%
%   CFG IS RESOLVED HERE, NOT BY THE CALLER. RESOLVEQUERYCONFIG needs the clip
%   duration, which only this function knows, and Enhancement 2 is precisely a
%   query-length-conditional fan-out. Resolving in one place means the GUI and
%   the evaluation harness cannot disagree about what a 3 s query does.
%
%   THE INDEX'S CONFIG WINS ON EVERYTHING STRUCTURAL. Passing a Cfg whose STFT
%   grid or hash layout differs from the one the index was built with produces
%   hashes that cannot collide - zero matches, no error, nothing in the logs.
%   The check below turns that into a sentence. The query-side fields the
%   caller is allowed to vary (denoise, shortQuery, tau, rho) are left alone.
%
%   NO DISPLAY, NO FILE I/O, NO PLOTTING. This is the function the GUI calls
%   and the function the evaluation harness times 10,800 times per system. A
%   stray fprintf or figure would corrupt the timing that success criterion #3
%   depends on, and would make parfor at M7 unusable.
%
%   TIMING IS SPLIT because the two halves scale differently: tHashSec is
%   linear in clip length and independent of catalogue size, tMatchSec grows
%   with the index. Index LOADING is excluded entirely - it is a one-time
%   startup cost, reported separately (blueprint 6.3).
%
%   Milestone: M1.  Blueprint: sections 3.5, 5.
%
%   See also EXTRACTFINGERPRINT, ALIGNOFFSETS, SCORECANDIDATES, DECIDEOPENSET.

if nargin < 3 || isempty(Cfg)
    Cfg = Idx.cfg;
end

sig         = double(sig(:));
durationSec = numel(sig) / Cfg.audio.fs;

Cfg = adoptIndexStructure(Cfg, Idx);
Cfg = resolveQueryConfig(Cfg, durationSec);

% ---- Fingerprint --------------------------------------------------------
tHash = tic;
fp    = extractFingerprint(sig, Cfg);
tHashSec = toc(tHash);

h  = fp.hashes.h;
t1 = fp.hashes.t1;

% ---- Lookup, align, score ----------------------------------------------
tMatch = tic;

post = queryIndex(Idx, h);

[counts, offsetInfo] = alignOffsets(post, t1, Idx.nSongs, Cfg);

[topPred, topScore, normScore, margin] = scoreCandidates(counts, numel(h), Cfg);

tMatchSec = toc(tMatch);

% ---- Assemble -----------------------------------------------------------
res                 = struct();
res.pred1           = topPred(1);
res.score1          = topScore(1);

if numel(topPred) >= 2
    res.pred2  = topPred(2);
    res.score2 = topScore(2);
else
    res.pred2  = 0;
    res.score2 = 0;
end

res.normScore       = normScore;
res.margin          = margin;
res.accepted        = decideOpenSet(normScore, margin, Cfg);

res.nQueryHashes    = numel(h);
res.nCandidateSongs = nnz(max(counts, [], 2));
res.nPostings       = numel(post.qIdx);
res.durationSec     = durationSec;

res.tHashSec        = tHashSec;
res.tMatchSec       = tMatchSec;
res.tTotalSec       = tHashSec + tMatchSec;

res.topPred         = topPred;
res.topScore        = topScore;

% ---- GUI diagnostics ----------------------------------------------------
res.peaks        = fp.peaks;
res.offsetFrames = offsetInfo.deltaFrames;

if res.pred1 > 0
    res.offsetHist = full(counts(res.pred1, :))';
    [~, iBest]     = max(res.offsetHist);
    res.bestOffsetFrames = offsetInfo.deltaFrames(iBest);
    res.bestOffsetSec    = res.bestOffsetFrames / Cfg.derived.frameRate;
else
    res.offsetHist       = zeros(offsetInfo.nOffsets, 1);
    res.bestOffsetFrames = NaN;
    res.bestOffsetSec    = NaN;
end

res.cfgTag = Cfg.tag;

end

% =======================================================================
function Cfg = adoptIndexStructure(Cfg, Idx)
%ADOPTINDEXSTRUCTURE Make the query's structural parameters match the index's.
%
%   Everything that determines whether two hashes CAN collide has to be
%   identical on both sides. Rather than silently overwriting, this reports
%   the mismatch: a caller who passed the wrong config has a bug, and finding
%   it here costs a second where finding it at M3 costs an afternoon.

if ~isfield(Idx, 'cfg') || isempty(Idx.cfg)
    return
end

R = Idx.cfg;

structural = { ...
    'audio.fs',          'the sample rate'
    'stft.winLen',       'the STFT window length'
    'stft.hop',          'the STFT hop'
    'stft.nfft',         'the FFT length'
    'hash.freqBits',     'the hash frequency field width'
    'hash.dtBits',       'the hash time field width'
    'hash.freqDecim',    'frequency decimation'
    'hash.dtMin',        'the minimum target-zone delta'
    'pre.preemphAlpha',  'pre-emphasis'
    };

bad = {};

for k = 1:size(structural, 1)
    path = strsplit(structural{k, 1}, '.');
    a = Cfg.(path{1}).(path{2});
    b = R.(path{1}).(path{2});
    if ~isequal(a, b)
        bad{end + 1} = sprintf('%s (%s): query %g, index %g', ...
            structural{k, 1}, structural{k, 2}, a, b); %#ok<AGROW>
    end
end

if ~isempty(bad)
    error('HimigTransform:ConfigIndexMismatch', ...
        ['The query config differs from the config the index was built with, ' ...
         'on parameters that decide whether hashes can collide at all. ' ...
         'Nothing would match and nothing would warn.\n  %s\n' ...
         'Pass the config that built the index (Idx.cfg), or rebuild the index.'], ...
        strjoin(bad, sprintf('\n  ')));
end

% Structurally identical, so adopt the index's window and STFT verbatim -
% including anything not listed above - and keep the caller's query-side
% choices (denoise, shortQuery, tau, rho, topK).
Cfg.stft    = R.stft;
Cfg.audio   = R.audio;
Cfg.pre     = R.pre;
Cfg.derived = R.derived;

end