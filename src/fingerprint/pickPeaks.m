function peaks = pickPeaks(Smag, Cfg)
%PICKPEAKS Dispatch to the fixed or adaptive peak picker, then cap density.
%
%   PEAKS = PICKPEAKS(SMAG, CFG) reads Cfg.peaks.mode and calls
%   PICKPEAKSFIXED ('fixed', the baseline) or PICKPEAKSADAPTIVE ('adaptive',
%   Enhancement 1b), then ALWAYS applies ENFORCEPEAKDENSITY.
%
%   The density cap is applied here rather than inside each picker so that it
%   cannot be forgotten in one of them. That is not a tidiness argument: both
%   modes have to be compared at the same peak budget, or the adaptive picker
%   "wins" by the uninteresting route of simply emitting more peaks, and the
%   10-percentage-point claim at 0 dB would be measuring index size rather
%   than noise robustness. Keeping the cap in the dispatcher makes that
%   impossible to get wrong by accident.
%
%   Milestone: M1.  Blueprint: section 3.3.
%
%   See also PICKPEAKSFIXED, PICKPEAKSADAPTIVE, ENFORCEPEAKDENSITY.

if nargin < 2 || isempty(Cfg)
    Cfg = defaultConfig();
end

switch lower(Cfg.peaks.mode)
    case 'fixed'
        peaks = pickPeaksFixed(Smag, Cfg);
    case 'adaptive'
        peaks = pickPeaksAdaptive(Smag, Cfg);
    otherwise
        error('HimigTransform:UnknownPeakMode', ...
            'Cfg.peaks.mode = "%s" is not recognised. Use ''fixed'' or ''adaptive''.', ...
            Cfg.peaks.mode);
end

peaks = enforcePeakDensity(peaks, size(Smag, 2), Cfg);

peaks.mode = Cfg.peaks.mode;

end