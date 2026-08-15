function ax = plotConstellation(Smag, peaks, Cfg, ax)
%PLOTCONSTELLATION Spectrogram with the constellation map overlaid.
%
%   AX = PLOTCONSTELLATION(SMAG, PEAKS, CFG) draws into a new figure.
%   AX = PLOTCONSTELLATION(SMAG, PEAKS, CFG, AX) draws into an existing axes,
%   which is how the GUI and the paper figures share one implementation.
%
%   Magnitude is shown in dB relative to the spectrogram maximum, so the image
%   looks the same whatever gain the signal arrived at - the same reason
%   Cfg.peaks.floorDb is relative rather than absolute.
%
%   Milestone: M6.  Blueprint: sections 3.3, 4.
%
%   See also PICKPEAKS, PLOTOFFSETHISTOGRAM, HIMIGTRANSFORMAPP.

narginchk(3, 4);

if nargin < 4 || isempty(ax)
    ax = axes('Parent', figure('Color', 'w'));
end

cla(ax, 'reset');

if isempty(Smag)
    title(ax, 'No signal');
    return
end

nFrames = size(Smag, 2);
tSec = ((0:nFrames - 1) * Cfg.stft.hop + Cfg.stft.winLen / 2) / Cfg.audio.fs;
fHz  = (0:size(Smag, 1) - 1) * Cfg.derived.binWidthHz;

peakMag = max(Smag(:));
if peakMag <= 0
    peakMag = 1;
end
SdB = 20 * log10(max(Smag, realmin) / peakMag);

imagesc(ax, tSec, fHz, SdB);
set(ax, 'YDir', 'normal');
ax.CLim = [-80 0];          % not caxis(): clim/caxis naming moved in R2022a
colormap(ax, gray);

hold(ax, 'on');

nPeaks = numel(peaks.tIdx);
if nPeaks > 0
    pt = (double(peaks.tIdx) - 1) * Cfg.stft.hop / Cfg.audio.fs ...
         + Cfg.stft.winLen / (2 * Cfg.audio.fs);
    pf = (double(peaks.fIdx) - 1) * Cfg.derived.binWidthHz;

    plot(ax, pt, pf, 'o', ...
        'MarkerSize', 4, 'LineWidth', 0.9, ...
        'MarkerEdgeColor', [1.00 0.35 0.25]);
end

hold(ax, 'off');

xlabel(ax, 'Time (s)');
ylabel(ax, 'Frequency (Hz)');

durSec = max(tSec(end), eps);
title(ax, sprintf('Constellation map - %d peaks (%.1f/s)', ...
    nPeaks, nPeaks / durSec));

xlim(ax, [0 max(tSec(end), eps)]);
ylim(ax, [0 Cfg.audio.fs / 2]);

end
