function [y, gainDb] = rmsNormalize(x, targetRmsDbfs)
%RMSNORMALIZE Scale a signal to a target RMS level in dBFS.
%
%   Y = RMSNORMALIZE(X, TARGETRMSDBFS) scales X by a single constant so that
%   20*log10(rms(Y)) equals TARGETRMSDBFS. TARGETRMSDBFS defaults to
%   CFG.audio.targetRmsDbfs (-20). Shape and orientation are preserved; the
%   output is always double.
%
%   [Y, GAINDB] = RMSNORMALIZE(...) also returns the gain applied, in dB.
%   INGESTLIBRARY records it per file, and the spread of GAINDB across the
%   catalog is the number that justifies this function existing: if it is
%   narrow, the library was already consistent, and if it is 20 dB wide then
%   a fixed peak-picking threshold would have behaved like a different
%   algorithm on each end of the catalog.
%
%   RMS, NOT PEAK. See blueprint 6.1. A loudness-war master is compressed to
%   sit near full scale almost continuously; a dynamic 1970s recording touches
%   full scale on one snare hit and averages 15 dB below it. Peak-normalising
%   both puts their peaks together and leaves their average levels far apart,
%   which breaks two things at once. First, the fixed magnitude floor in
%   PICKPEAKSFIXED admits a dense constellation from one and a sparse one from
%   the other. Second, and worse, MIXATSNR derives its noise gain from the
%   measured power of the excerpt, so "0 dB SNR" would mean a different
%   physical amount of noise for every track and the x-axis of the headline
%   figure would be meaningless. RMS normalisation puts average power - the
%   quantity SNR is actually defined over - on a common footing.
%
%   NO CLIP GUARD HERE. This function does exactly one thing: apply a gain.
%   Whether the result clips depends on the crest factor of the source, and
%   what to do about it depends on the caller. INGESTLIBRARY is writing 16-bit
%   integers and must scale down and flag it; PREPROCESSSIGNAL is working in
%   double in memory where nothing clips and must not touch the level again.
%   Folding a guard in here would silently change the RMS the caller asked
%   for, which is the one thing it is relying on.
%
%   DC IS NOT REMOVED HERE EITHER. A DC offset contributes to the measured
%   RMS, so a badly-transferred file with a large offset normalises slightly
%   quiet. That is correct behaviour for this function: DC removal is a
%   separate, symmetric preprocessing stage (blueprint 3.7) owned by
%   PREPROCESSSIGNAL, and doing it here would mean the reference and query
%   paths each removed DC at a different point.
%
%   CONVENTION. Full scale is +/-1.0, so a full-scale sine measures
%   -3.01 dBFS RMS. The -20 dBFS target therefore leaves roughly 17 dB of
%   headroom for a sine and rather less for real music, whose crest factor
%   runs 10-18 dB - which is why the clip guard in INGESTLIBRARY fires on the
%   most dynamic tracks and not on the compressed ones.
%
%   Milestone: M0.  Blueprint: sections 6.1, 6.2.
%
%   See also PREPROCESSSIGNAL, INGESTLIBRARY, MIXATSNR, DEFAULTCONFIG.

if nargin < 2 || isempty(targetRmsDbfs)
    targetRmsDbfs = defaultConfig().audio.targetRmsDbfs;
end

validateattributes(x, {'numeric'}, {'vector', 'real'}, mfilename, 'x');
validateattributes(targetRmsDbfs, {'numeric'}, ...
    {'scalar', 'real', 'finite'}, mfilename, 'targetRmsDbfs');

x = double(x);

if ~all(isfinite(x))
    error('HimigTransform:NonFiniteAudio', ...
        ['Signal contains %d non-finite sample(s). Normalising would spread them ' ...
         'over the whole file and the failure would surface much later, in the STFT.'], ...
        nnz(~isfinite(x)));
end

rmsIn = sqrt(mean(x .^ 2));

% ---- Digital silence ---------------------------------------------------
% No finite gain reaches the target. Returning the input unchanged with 0 dB
% of gain is honest; returning zeros scaled by Inf would produce NaNs.
if rmsIn <= 0
    logMsg('warn', ...
        'rmsNormalize: input is digital silence (RMS = 0). Returned unchanged, gain 0 dB.');
    y      = x;
    gainDb = 0;
    return
end

rmsInDbfs = 20 * log10(rmsIn);
gain      = 10 ^ (targetRmsDbfs / 20) / rmsIn;
gainDb    = 20 * log10(gain);

% A very large boost means the source was near-silent, which is almost always
% a bad rip, a leading silence that swallowed the whole file, or a track that
% is mostly fade. Worth a line in the log; not worth failing over, because the
% ingest report shows it per file and the group can decide.
if gainDb > 40
    logMsg('warn', ...
        ['rmsNormalize: applying +%.1f dB to reach %.1f dBFS (source RMS %.1f dBFS). ' ...
         'Check the file is not near-silence or a mostly-empty rip.'], ...
        gainDb, targetRmsDbfs, rmsInDbfs);
end

y = gain * x;

end