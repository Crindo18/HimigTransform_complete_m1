function Sclean = spectralSubtract(S, Nmag, Cfg)
%SPECTRALSUBTRACT Magnitude spectral subtraction, phase preserved (Enh. 1a).
%
%   SCLEAN = SPECTRALSUBTRACT(S, NMAG, CFG) applies
%
%       |Shat| = max(|S| - alpha*|Nhat|, beta*|S|)
%
%   to the complex spectrogram S [nBins x nFrames] using the noise magnitude
%   estimate NMAG [nBins x 1], and returns the result carrying S's original
%   phase. alpha and beta come from Cfg.denoise.
%
%   QUERY SIDE ONLY. References are enrolled clean and are never denoised
%   (blueprint 3.7). That asymmetry is deliberate, and blueprint 3.6 requires
%   it to be validated: denoising shifts peak locations slightly, so a clean
%   query passed through here can score worse than one that was not. The
%   clean-query regression gate at M4 is what decides whether the denoiser is
%   always-on or conditioned on an estimated SNR.
%
%   NMAG IS FORCED TO A COLUMN. The subtraction relies on implicit expansion
%   of [nBins x nFrames] against [nBins x 1]. Hand it a ROW of the same length
%   and MATLAB does not error for most query lengths - it errors only when the
%   frame count differs from the bin count. At exactly 257 frames (8.22 s at
%   this hop) the two agree, expansion happens along the wrong axis, and the
%   function quietly subtracts the noise estimate across time instead of
%   frequency. This project has now hit the same class of bug twice, both
%   times in an expansion that was correct for every size but one, and both
%   times invisible to an integration run. A (:) costs nothing.
%
%   PHASE IS REUSED, NOT RECONSTRUCTED. abs/angle followed by exp(1i*theta)
%   is a lossy round-trip through two transcendental functions on every bin of
%   every frame; S ./ max(abs(S), eps) is the same unit phasor, exactly, and
%   is markedly cheaper. On a full evaluation grid this runs on the order of
%   10^4 queries, so the difference is worth having.
%
%   Milestone: M4.  Blueprint: section(s) 3.6, 3.7.
%
%   See also ESTIMATENOISESPECTRUM, PREPROCESSSIGNAL, COMPUTESTFT.

if nargin < 3 || isempty(Cfg)
    Cfg = defaultConfig();
end

validateattributes(S, {'numeric'}, {'2d'}, mfilename, 'S');
validateattributes(Nmag, {'numeric'}, {'real', 'nonnegative', 'vector'}, mfilename, 'Nmag');

Nmag = double(Nmag(:));

nBins = size(S, 1);
if numel(Nmag) ~= nBins
    error('HimigTransform:NoiseSpectrumSizeMismatch', ...
        ['Nmag has %d element(s) but S has %d frequency bin(s). ' ...
         'ESTIMATENOISESPECTRUM must be called on the same STFT grid.'], ...
        numel(Nmag), nBins);
end

alpha = Cfg.denoise.alpha;
beta  = Cfg.denoise.beta;

Ymag = abs(S);

% max(|Y| - alpha*|N|, beta*|Y|)  -- the floor is on the NOISY magnitude,
% exactly as blueprint 3.6 specifies. beta is what keeps isolated surviving
% bins from becoming musical noise.
Shat = max(Ymag - alpha * Nmag, beta * Ymag);

% Unit phasor of S, guarding the zero-magnitude bins.
phasor = S ./ max(Ymag, eps);

Sclean = Shat .* phasor;

end
