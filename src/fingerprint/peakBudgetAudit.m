function audit = peakBudgetAudit(Cfg, verbose)
%PEAKBUDGETAUDIT Can the configured peak density actually be reached?
%
%   AUDIT = PEAKBUDGETAUDIT(CFG) compares Cfg.peaks.densityPerSec against the
%   ceiling imposed by the local-maximum neighbourhood, globally and per
%   frequency band. PEAKBUDGETAUDIT(CFG, TRUE) also prints the table.
%
%   WHY THIS EXISTS. Two independent mechanisms limit constellation density
%   and only one of them is a parameter:
%
%     1. GEOMETRY. A peak must be the maximum over an nbhdF x nbhdT
%        neighbourhood, so two peaks cannot sit closer than that in both
%        dimensions. The most peaks a spectrogram can hold per second is
%
%            ceiling = (frameRate / nbhdT) * (nBins / nbhdF)
%
%     2. THE DENSITY CAP. ENFORCEPEAKDENSITY keeps the top K per (second,
%        band), with K = round(densityPerSec / nBands).
%
%   If the target sits above the ceiling, the cap can never bind. The
%   parameter then does nothing: density is whatever the neighbourhood
%   happens to yield, and it varies from track to track. That is a silent
%   failure - nothing errors, the pipeline runs, accuracy on clean queries
%   looks fine - so it needs a diagnostic rather than a comment.
%
%   WHY IT MATTERS BEYOND TIDINESS. Blueprint 3.3 caps per second and per band
%   for two specific reasons: so a six-minute track cannot dominate the index
%   over a two-minute one, and so the bass region cannot swallow the whole
%   budget. Neither guarantee holds while the cap is inert. And at M4 both
%   peak pickers run through ENFORCEPEAKDENSITY precisely so fixed and
%   adaptive are compared at equal peak budget - if the cap never binds, the
%   adaptive picker can win by emitting more peaks, which is the exact
%   confound the design was meant to remove.
%
%   THE CEILING IS AN UPPER BOUND, NOT A PREDICTION. Real music does not fill
%   every neighbourhood; measured density on the 100-song corpus came in near
%   two thirds of the ceiling. Use AUDIT.ceilingPerSec to rule a target out,
%   and ENROLLDATABASE's measured density to see what a target actually
%   delivers.
%
%   Fields: ceilingPerSec, targetPerSec, capCanBind, headroom, perBand (table
%   of band edges, bin counts, per-band ceiling and per-band budget K), and
%   suggestedNbhd - the odd neighbourhood whose ceiling would sit far enough
%   above the target for the cap to bind.
%
%   Milestone: M2.  Blueprint: section 3.3.
%
%   See also ENFORCEPEAKDENSITY, PICKPEAKS, ENROLLDATABASE.

if nargin < 2
    verbose = false;
end

frameRate = Cfg.derived.frameRate;
nBins     = Cfg.derived.nBins;
binWidth  = Cfg.derived.binWidthHz;

nbhdF = Cfg.peaks.nbhdF;
nbhdT = Cfg.peaks.nbhdT;

edges  = Cfg.peaks.bandEdgesHz(:)';
nBands = numel(edges) - 1;

target = Cfg.peaks.densityPerSec;
K      = max(1, round(target / nBands));

audit               = struct();
audit.ceilingPerSec = (frameRate / nbhdT) * (nBins / nbhdF);
audit.targetPerSec  = target;
audit.perBandBudget = K;
audit.nBands        = nBands;
audit.capCanBind    = target < audit.ceilingPerSec;
audit.headroom      = audit.ceilingPerSec / max(target, eps);

% Per band. The bands are deliberately unequal in width, so an equal budget K
% means the narrow low bands can be unable to fill their allocation even when
% the global ceiling is generous.
bandLo    = zeros(nBands, 1);
bandHi    = zeros(nBands, 1);
bandBins  = zeros(nBands, 1);
bandCeil  = zeros(nBands, 1);

for b = 1:nBands
    bandLo(b)   = edges(b);
    bandHi(b)   = edges(b + 1);
    binLo       = floor(edges(b) / binWidth);
    binHi       = floor(edges(b + 1) / binWidth);
    bandBins(b) = max(binHi - binLo, 0);
    bandCeil(b) = (frameRate / nbhdT) * (bandBins(b) / nbhdF);
end

audit.perBand = table(bandLo, bandHi, bandBins, bandCeil, ...
    repmat(K, nBands, 1), bandCeil >= K, ...
    'VariableNames', {'loHz', 'hiHz', 'nBins', 'ceilingPerSec', ...
                      'budgetK', 'budgetReachable'});

audit.achievableSum = sum(bandCeil);

% LARGEST odd neighbourhood whose ceiling clears the target with the margin
% real music needs - the least aggressive change that makes the cap bind.
% The 1.5 factor comes from the measured achieved/ceiling ratio on the
% 100-song corpus, which came in at about two thirds.
%
% Searching downward matters. Going upward and taking the first hit returns
% the smallest neighbourhood, which is the most destructive option: a small
% neighbourhood admits weak, closely spaced maxima that are the first thing
% noise destroys, so it trades exactly the robustness this project is trying
% to measure.
audit.suggestedNbhd = NaN;
for r = 31:-2:3
    if (frameRate / r) * (nBins / r) >= 1.5 * target
        audit.suggestedNbhd = r;
        break
    end
end

if verbose
    fprintf('\n--- Peak budget audit (%s) ---\n', Cfg.tag);
    fprintf('  neighbourhood       : %d x %d (freq x time)\n', nbhdF, nbhdT);
    fprintf('  local-max ceiling   : %.1f peaks/s\n', audit.ceilingPerSec);
    fprintf('  configured target   : %d peaks/s\n', target);
    fprintf('  per-band budget K   : %d  (over %d bands)\n', K, nBands);
    fprintf('  sum of band ceilings: %.1f peaks/s\n', audit.achievableSum);

    if audit.capCanBind
        fprintf('  VERDICT             : cap CAN bind (headroom %.2fx)\n', audit.headroom);
    else
        fprintf('  VERDICT             : cap CANNOT bind - the target is above\n');
        fprintf('                        the ceiling, so densityPerSec is inert.\n');
        if ~isnan(audit.suggestedNbhd)
            fprintf('                        A %dx%d neighbourhood would clear it.\n', ...
                audit.suggestedNbhd, audit.suggestedNbhd);
        end
    end

    fprintf('\n  band   range (Hz)     bins   ceiling/s   budget K   reachable\n');
    for b = 1:nBands
        if audit.perBand.budgetReachable(b)
            flag = 'yes';
        else
            flag = 'NO';
        end
        fprintf('  %3d   %5.0f - %5.0f    %4d   %8.2f   %8d   %9s\n', ...
            b, bandLo(b), bandHi(b), bandBins(b), bandCeil(b), K, flag);
    end
    fprintf('\n');
end

end
