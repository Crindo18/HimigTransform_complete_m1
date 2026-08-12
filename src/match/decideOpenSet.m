function accepted = decideOpenSet(normScore, margin, Cfg)
%DECIDEOPENSET Apply the open-set accept rule: normScore >= tau AND margin >= rho.
%
%   ACCEPTED = DECIDEOPENSET(NORMSCORE, MARGIN, CFG) is vectorised over
%   NORMSCORE and MARGIN, so a whole results table can be re-thresholded in
%   one call - which is what TUNETHRESHOLDS does when it sweeps the dev split.
%
%   BOTH CONDITIONS, because the two statistics catch different failures.
%   normScore alone accepts a weak match that had no competition; margin alone
%   accepts a match that beat its rivals while being poor in absolute terms,
%   which is exactly what a noisy 3 s query against an unenrolled song looks
%   like.
%
%   WHY THIS FUNCTION EXISTS AT M1 EVEN THOUGH IT IS TAGGED M5. The rule is
%   two comparisons; what arrives at M5 is the machinery around it -
%   TUNETHRESHOLDS sweeping tau and rho on dev, PLOTOPENSETROC over the 20
%   holdout songs, and the operating point being written into enhancedConfig
%   before the test split is touched. Keeping the rule itself in one function
%   from the start means IDENTIFYQUERY has a real .accepted field throughout
%   M1-M4, and that M5 changes the numbers without changing any code that
%   reads them.
%
%   TAU AND RHO MUST BE RE-TUNED PER SYSTEM. Enhanced mode emits more hashes,
%   so nQueryHashes grows and normScore shifts. Reusing the baseline threshold
%   on the enhanced system is the easiest way to report a number that does not
%   survive questioning at the defence.
%
%   Milestone: M1 (the rule).  M5 (tuning tau and rho, and the ROC).
%   Blueprint: sections 3.5, 8.3.
%
%   See also TUNETHRESHOLDS, SCORECANDIDATES.

if nargin < 3 || isempty(Cfg)
    Cfg = defaultConfig();
end

validateattributes(normScore, {'numeric'}, {'real', 'nonnegative'}, mfilename, 'normScore');
validateattributes(margin,    {'numeric'}, {'real', 'nonnegative'}, mfilename, 'margin');

accepted = (normScore >= Cfg.match.tau) & (margin >= Cfg.match.rho);

end