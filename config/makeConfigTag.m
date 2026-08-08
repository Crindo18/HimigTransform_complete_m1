function tag = makeConfigTag(Cfg)
%MAKECONFIGTAG Deterministic, filesystem-safe identifier for a configuration.
%
%   TAG = MAKECONFIGTAG(CFG) builds a short string from the parameters that
%   change the contents of an index or a fingerprint cache. The tag is used in
%   filenames:
%
%       db/index_<tag>.mat
%       db/fingerprints/<tag>/song_%04d.mat
%
%   Two configurations that would produce identical fingerprints must produce
%   identical tags, and any change that invalidates a cached index must change
%   the tag. Parameters that only affect matching or evaluation (tau, rho, the
%   eval grid) are deliberately EXCLUDED - they do not invalidate an index.
%
%   Examples
%       base_fs8000_w512_h256_d25_F8_dt32_fd1_fix
%       enh_fs8000_w512_h256_d25_F20_dt64_fd1_ada_ss
%
%   See also DEFAULTCONFIG, BASELINECONFIG, ENHANCEDCONFIG.
%
%   Blueprint: sections 2.1, 2.3, 2.4.

modeAbbrev = struct('fixed', 'fix', 'adaptive', 'ada');
if ~isfield(modeAbbrev, Cfg.peaks.mode)
    error('HimigTransform:BadConfig', ...
        'Unknown Cfg.peaks.mode "%s" (expected fixed or adaptive).', Cfg.peaks.mode);
end

tag = sprintf('%s_fs%d_w%d_h%d_d%d_F%d_dt%d_fd%d_%s', ...
    Cfg.name, ...
    Cfg.audio.fs, ...
    Cfg.stft.winLen, ...
    Cfg.stft.hop, ...
    Cfg.peaks.densityPerSec, ...
    Cfg.hash.fanout, ...
    Cfg.hash.dtMax, ...
    Cfg.hash.freqDecim, ...
    modeAbbrev.(Cfg.peaks.mode));

% Query-side flags do not change the index, but carrying them makes the tag
% self-documenting when it appears in a results table.
if Cfg.denoise.enable
    tag = [tag '_ss'];
end
if Cfg.shortQuery.enable
    tag = [tag '_sq'];
end

end
