function [y, g, snrMeas] = mixAtSNR(x, n, targetSnrDb)
%MIXATSNR Mix a signal and a noise segment at a requested in-band SNR.
%
%   [Y, G, SNRMEAS] = MIXATSNR(X, N, TARGETSNRDB) scales N by G so that
%   Y = X + G*N carries the requested SNR, rescales Y if the sum would clip,
%   and returns the SNR measured back off Y.
%
%   TARGETSNRDB = Inf returns X unchanged with G = 0 and SNRMEAS = Inf.
%
%   SNRMEAS IS MEASURED, NOT RESTATED. The obvious implementation computes
%   10*log10(mean(x.^2) / mean((g*n).^2)) - but G was just solved for from
%   exactly those two powers, so that expression returns the target to within
%   floating point no matter what the function did in between. It cannot fail,
%   which means TMIXSNR cannot fail either, and blueprint 5's "within 0.1 dB"
%   contract becomes a tautology guarding nothing.
%
%   What is worth verifying is that Y really is the mixture it claims to be.
%   So the noise is recovered back out of the returned signal - undo the
%   anti-clipping rescale, subtract the clean excerpt, and measure what is
%   left. A length mismatch, a bad index range, a noise segment that never got
%   added, or a rescale applied to one term and not the other all move this
%   number; the arithmetic-only version moves for none of them.
%
%   RESCALING DOES NOT CHANGE THE SNR because it multiplies signal and noise
%   by the same factor (blueprint 6.2). That is a property worth preserving
%   and worth testing, not a reason to skip the measurement.
%
%   G IS THE PRE-RESCALE NOISE GAIN. When the mixture clips, Y is scaled but G
%   is not, so Y ~= X + G*N exactly. Callers wanting the components back
%   should scale both by max(abs(y))/0.99 as this function does internally.
%
%   Milestone: M3.  Blueprint: section(s) 5, 6.2.
%
%   See also SYNTHESIZEQUERY, BUILDQUERYMANIFEST.

if ~isscalar(targetSnrDb) || ~isreal(targetSnrDb) || isnan(targetSnrDb)
    error('HimigTransform:BadTargetSnr', ...
        'targetSnrDb must be a real scalar (Inf for clean); got a %s.', class(targetSnrDb));
end

x = double(x(:));
n = double(n(:));

% ---- Clean passes straight through --------------------------------------
if isinf(targetSnrDb) && targetSnrDb > 0
    y       = x;
    g       = 0;
    snrMeas = Inf;
    return
end

if isempty(x)
    error('HimigTransform:EmptyExcerpt', 'mixAtSNR received an empty signal.');
end

% ---- Match the noise to the excerpt, looping if the bank is short -------
lenX = numel(x);
if numel(n) >= lenX
    n = n(1:lenX);
elseif isempty(n)
    error('HimigTransform:EmptyNoise', 'mixAtSNR received an empty noise segment.');
else
    n = repmat(n, ceil(lenX / numel(n)), 1);
    n = n(1:lenX);
end

% ---- Powers over the excerpt, never the whole song (blueprint 6.2) ------
Px = mean(x.^2);
Pn = mean(n.^2);

if Pn == 0
    % Silent noise cannot be scaled to any finite SNR. The mixture is the
    % clean excerpt, and the honest measured SNR is +Inf.
    y       = x;
    g       = 0;
    snrMeas = Inf;
    return
end

if Px == 0
    % A silent EXCERPT is a different story: the noise is all there is, so the
    % measured SNR is -Inf, not +Inf. Returning +Inf here would relabel a
    % broken excerpt as a clean query and quietly pollute the clean row of
    % every results table. PICKEXCERPTSTART's energy gate exists to stop this
    % reaching us; if it does, it must be visible.
    logMsg('warn', ...
        'mixAtSNR: excerpt is digital silence; returning noise only with snrMeas = -Inf.');
    g       = 1;
    y       = n;
    peakY   = max(abs(y));
    if peakY > 0.99
        y = y * (0.99 / peakY);
    end
    snrMeas = -Inf;
    return
end

% ---- Noise gain for the requested ratio ---------------------------------
g = sqrt(Px / (Pn * 10^(targetSnrDb / 10)));

y = x + g * n;

% ---- Anti-clipping rescale ----------------------------------------------
peakY = max(abs(y));
if peakY > 0.99
    k = 0.99 / peakY;
    y = y * k;
else
    k = 1;
end

% ---- Measure the SNR back off the returned signal -----------------------
% Undo the rescale, then whatever is not the clean excerpt is the noise that
% actually landed in y.
nResidual = (y / k) - x;
Pres      = mean(nResidual.^2);

if Pres == 0
    snrMeas = Inf;
else
    snrMeas = 10 * log10(Px / Pres);
end

end
