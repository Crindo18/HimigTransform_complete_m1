function [lo, hi, p] = wilsonInterval(k, n, alpha)
%WILSONINTERVAL Wilson score confidence interval for a binomial proportion.
%
%   [LO, HI, P] = WILSONINTERVAL(K, N) returns the 95% Wilson score interval
%   for K successes in N trials, plus the point estimate P = K/N. K and N may
%   be arrays of the same size (or either may be scalar); the interval is
%   computed elementwise.
%
%   [...] = WILSONINTERVAL(K, N, ALPHA) uses a 100*(1-ALPHA)% interval.
%
%   WHY WILSON AND NOT THE NORMAL APPROXIMATION. The textbook interval
%   p +/- z*sqrt(p(1-p)/n) is the one everybody reaches for and it fails
%   exactly where this project needs it: near p = 1. Every clean cell in the
%   results table sits at or near 100% top-1, where the normal interval has
%   zero width - it would report 100% +/- 0.0 pp from 150 queries, which is
%   not a claim anyone should put in front of a panel. It also runs past 1 for
%   moderate p and small n. Wilson does neither: it stays inside [0, 1] and
%   keeps sensible width at the boundary.
%
%   N = 0 returns NaN rather than erroring, so an empty cell in a
%   GROUPSUMMARY - a noise type that never appears at a given length, say -
%   propagates as missing instead of stopping a figure script.
%
%   No Statistics Toolbox: the z quantile comes from ERFCINV, which is base
%   MATLAB (blueprint 1.2).
%
%   Milestone: M3.  Blueprint: section(s) 8.4.
%
%   See also COMPUTEMETRICS, MCNEMARTEST.

if nargin < 3 || isempty(alpha)
    alpha = 0.05;
end

k = double(k);
n = double(n);

% Two-sided normal quantile without the Statistics Toolbox:
%   norminv(1 - alpha/2) == -sqrt(2) * erfcinv(2*(1 - alpha/2))
z = -sqrt(2) * erfcinv(2 * (1 - alpha / 2));

p = k ./ n;

denom  = 1 + z.^2 ./ n;
centre = (p + z.^2 ./ (2 * n)) ./ denom;
half   = (z ./ denom) .* sqrt(p .* (1 - p) ./ n + z.^2 ./ (4 * n.^2));

lo = centre - half;
hi = centre + half;

% Clamp for floating-point overshoot at the boundaries.
lo = max(lo, 0);
hi = min(hi, 1);

empty = (n == 0);
if any(empty(:))
    p(empty)  = NaN;
    lo(empty) = NaN;
    hi(empty) = NaN;
end

end
