function [p, stats] = mcnemarTest(correctA, correctB, alpha)
%MCNEMARTEST Exact paired significance test for baseline vs enhanced.
%
%   [P, STATS] = MCNEMARTEST(CORRECTA, CORRECTB) takes two logical vectors of
%   per-query outcomes, ALIGNED BY QUERY, and returns the two-sided exact
%   McNemar p-value.
%
%   [P, STATS] = MCNEMARTEST(CORRECTA, CORRECTB, ALPHA) also sets the
%   confidence level for the interval on the accuracy difference (default
%   0.05).
%
%   STATS fields
%       n            pairs compared
%       b            A correct, B wrong   (discordant, favours A)
%       c            A wrong, B correct   (discordant, favours B)
%       nDiscordant  b + c
%       accA, accB   marginal accuracies
%       diff         accB - accA, in proportion (multiply by 100 for pp)
%       diffLo/diffHi  Wald interval on the paired difference
%       oddsRatio    c / b, the paired effect size
%       significant  p < alpha
%
%   WHY PAIRED, AND WHY EXACT.
%
%   The two systems answer the SAME queries - same excerpt, same noise
%   segment, same SNR - because the manifest fixes all of that before either
%   system runs. That pairing is what this test exploits, and it is far more
%   sensitive than comparing two independent proportions. At n = 900 per cell
%   the Wilson half-width on a single accuracy is around 3 pp, so two
%   intervals can overlap while the paired difference is unambiguous.
%   Overlapping error bars are NOT evidence of no difference; this test is
%   what settles it.
%
%   Only the DISCORDANT pairs carry information. Queries both systems get
%   right, or both get wrong, say nothing about which is better - they cancel.
%   Under the null "the enhancement changes nothing", each discordant pair is
%   a fair coin, so the count follows Binomial(b + c, 0.5) and the exact test
%   is a two-sided binomial tail. No chi-square approximation, no continuity
%   correction to argue about, and it stays valid when b + c is small - which
%   is exactly the situation in the cells where the systems nearly agree.
%
%   USE IT PER CELL, NOT POOLED. Pooling across the SNR grid mixes cells where
%   the systems are identical with cells where they differ, and the pooled
%   p-value then depends on how many of each the grid happens to contain.
%
%   Example
%       mA = R.system == "baseline" & R.lengthSec == 3 & R.targetSnrDb == -10;
%       mB = R.system == "enhanced" & R.lengthSec == 3 & R.targetSnrDb == -10;
%       % sort BOTH by queryID first - alignment is the caller's job
%       [p, s] = mcnemarTest(R.correct(mA), R.correct(mB));
%
%   Milestone: M5.  Blueprint: section 8.4.
%
%   See also COMPUTEMETRICS, WILSONINTERVAL.

narginchk(2, 3);
if nargin < 3 || isempty(alpha)
    alpha = 0.05;
end

correctA = logical(correctA(:));
correctB = logical(correctB(:));

if numel(correctA) ~= numel(correctB)
    error('HimigTransform:UnpairedInputs', ...
        ['McNemar needs paired outcomes: got %d and %d. Both vectors must ' ...
         'be the same queries in the same order - sort by queryID before ' ...
         'calling, do not assume the two result files came out aligned.'], ...
        numel(correctA), numel(correctB));
end

n = numel(correctA);

stats            = struct();
stats.n          = n;
stats.b          = nnz(correctA & ~correctB);
stats.c          = nnz(~correctA & correctB);
stats.nDiscordant = stats.b + stats.c;
stats.nBothRight = nnz(correctA & correctB);
stats.nBothWrong = nnz(~correctA & ~correctB);
stats.alpha      = alpha;

if n == 0
    p = NaN;
    [stats.accA, stats.accB, stats.diff] = deal(NaN);
    [stats.diffLo, stats.diffHi, stats.oddsRatio] = deal(NaN);
    stats.significant = false;
    return
end

stats.accA = mean(correctA);
stats.accB = mean(correctB);
stats.diff = stats.accB - stats.accA;

% ---- Exact two-sided binomial on the discordant pairs -------------------
b = stats.b;
c = stats.c;
m = stats.nDiscordant;

if m == 0
    % The systems never disagreed on a single query. There is no evidence of
    % a difference and none against one either; p = 1 is the honest answer.
    p = 1;
else
    k = min(b, c);
    % Two-sided: double the smaller tail, capped at 1. Computed through
    % GAMMALN so it stays exact for large m without Statistics Toolbox.
    p = min(1, 2 * binomTailLE(k, m));
end

% ---- Interval on the paired difference ---------------------------------
% The variance of a paired difference of proportions depends only on the
% discordant counts: the concordant pairs contribute nothing.
if m > 0
    se = sqrt(m) / n;
else
    se = 0;
end
z = normQuantile(1 - alpha / 2);
stats.diffLo = stats.diff - z * se;
stats.diffHi = stats.diff + z * se;

if b > 0
    stats.oddsRatio = c / b;
elseif c > 0
    stats.oddsRatio = Inf;
else
    stats.oddsRatio = NaN;
end

stats.significant = p < alpha;

end

% =======================================================================
function pr = binomTailLE(k, m)
%BINOMTAILLE P(X <= k) for X ~ Binomial(m, 0.5), via log-gamma.

j  = (0:k)';
lc = gammaln(m + 1) - gammaln(j + 1) - gammaln(m - j + 1);
pr = sum(exp(lc - m * log(2)));

end

% =======================================================================
function z = normQuantile(q)
%NORMQUANTILE Standard normal inverse CDF, from ERFCINV (base MATLAB).
%
%   NORMINV lives in Statistics Toolbox; the project's toolbox policy
%   (blueprint 1.2) keeps that off the required list.

z = -sqrt(2) * erfcinv(2 * q);

end
