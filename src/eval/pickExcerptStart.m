function [startSample, info] = pickExcerptStart(src, lengthSec, Cfg, stream)
%PICKEXCERPTSTART Choose an energy-gated excerpt start (Risk R10).
%
%   STARTSAMPLE = PICKEXCERPTSTART(SRC, LENGTHSEC, CFG) picks a uniformly
%   random start for a LENGTHSEC excerpt, restricted to windows whose mean
%   frame energy is at least Cfg.eval.excerptEnergyGate times the track's
%   median frame energy.
%
%   SRC is either a catalog procPath (resolved through RESOLVEPROCPATH) or an
%   already-loaded signal vector. Pass the signal when picking several
%   excerpts from the same song - BUILDQUERYMANIFEST takes nine per track, and
%   re-reading the WAV for each one is the difference between a manifest that
%   builds in seconds and one that builds in minutes.
%
%   [STARTSAMPLE, INFO] = PICKEXCERPTSTART(...) also returns
%       info.nAdmissible   candidate starts that passed the gate
%       info.nCandidates   candidate starts considered
%       info.passFrac      nAdmissible / nCandidates
%       info.gated         true if the gate was applied, false if it was
%                          empty and the fallback ran
%   Risk R10 asks for the rejection rate to be logged; INFO is how callers get
%   it without this function printing inside a loop.
%
%   PICKEXCERPTSTART(..., STREAM) draws from a RandStream instead of the
%   global generator, so building a manifest cannot perturb - or be perturbed
%   by - any other random state in the session.
%
%   UNIFORM OVER ADMISSIBLE WINDOWS, NOT REJECTION SAMPLING. The gate is
%   evaluated for every candidate start at once via a cumulative sum, and the
%   choice is then uniform over the ones that passed. The obvious alternative
%   - draw, test, retry up to 50 times, give up and return an ungated window -
%   biases toward whatever the generator happens to offer early and, worse,
%   fails silently on exactly the tracks the gate exists for: a track that is
%   half silence hits the retry limit, falls through, and hands back the
%   ungated window anyway. R10 then looks mitigated when it is not.
%
%   Milestone: M3.  Blueprint: section(s) 2.5, 9 (R10).
%
%   See also BUILDQUERYMANIFEST, SYNTHESIZEQUERY, RESOLVEPROCPATH.

if nargin < 3 || isempty(Cfg)
    Cfg = defaultConfig();
end
if nargin < 4 || isempty(stream)
    stream = [];
end

fs = Cfg.audio.fs;

% ---- Signal -------------------------------------------------------------
if isnumeric(src)
    x = double(src(:));
else
    f = resolveProcPath(src);
    if ~isfile(f)
        error('HimigTransform:FileNotFound', ...
            'No such processed audio file: %s\nRun s01_ingest, or check catalog.csv procPath.', f);
    end
    [x, fsIn] = audioread(f);
    if fsIn ~= fs
        error('HimigTransform:WrongSampleRate', ...
            '%s is %d Hz, expected %d Hz. Re-run s01_ingest.', f, fsIn, fs);
    end
    x = double(x(:, 1));
end

totalSamples   = numel(x);
excerptSamples = round(lengthSec * fs);

info = struct('nAdmissible', 0, 'nCandidates', 0, 'passFrac', 0, 'gated', false);

if excerptSamples <= 0
    error('HimigTransform:BadExcerptLength', ...
        'lengthSec = %g yields %d samples.', lengthSec, excerptSamples);
end

if totalSamples <= excerptSamples
    % Track shorter than the excerpt. The caller gets what there is; the
    % length assertion in SYNTHESIZEQUERY is what turns this into a visible
    % failure rather than a silently short query.
    startSample      = 1;
    info.nCandidates = 1;
    info.nAdmissible = 1;
    info.passFrac    = 1;
    return
end

maxStart         = totalSamples - excerptSamples + 1;
info.nCandidates = maxStart;

% ---- Frame energies via cumulative sum ----------------------------------
% cs(k+1) = sum(x(1:k).^2), so the energy of x(a:b) is cs(b+1) - cs(a).
cs = [0; cumsum(x.^2)];

winLen = Cfg.stft.winLen;
hop    = Cfg.stft.hop;
nFrames = floor((totalSamples - winLen) / hop) + 1;

if nFrames < 1
    startSample      = randStart(maxStart, stream);
    info.nAdmissible = maxStart;
    info.passFrac    = 1;
    return
end

frameStart    = 1 + (0:nFrames-1)' * hop;                 % first sample of each frame
frameEnergies = cs(frameStart + winLen) - cs(frameStart); % sum over winLen samples
medianEnergy  = median(frameEnergies);

if ~(medianEnergy > 0)
    % Whole track is silent. Nothing to gate on.
    logMsg('warn', 'pickExcerptStart: track has zero median frame energy; gate skipped.');
    startSample      = randStart(maxStart, stream);
    info.nAdmissible = maxStart;
    info.passFrac    = 1;
    return
end

% ---- Gate every candidate window at once --------------------------------
% Mean frame energy inside a candidate window, expressed on the same scale as
% frameEnergies: (window energy / window samples) * winLen.
starts     = (1:maxStart)';
winEnergy  = cs(starts + excerptSamples) - cs(starts);
candEnergy = (winEnergy / excerptSamples) * winLen;

gateThreshold = Cfg.eval.excerptEnergyGate * medianEnergy;
admissible    = find(candEnergy >= gateThreshold);

info.nAdmissible = numel(admissible);
info.passFrac    = info.nAdmissible / info.nCandidates;

if isempty(admissible)
    % Gate too strict for this track. Fall back, but say so - a silent
    % fallback is how R10 stops being a mitigation.
    logMsg('warn', ...
        ['pickExcerptStart: no %.0f s window clears %.2f x median frame energy; ' ...
         'falling back to an ungated window.'], lengthSec, Cfg.eval.excerptEnergyGate);
    startSample = randStart(maxStart, stream);
    return
end

info.gated  = true;
pick        = randStart(info.nAdmissible, stream);
startSample = admissible(pick);

end

% =======================================================================
function s = randStart(n, stream)
if isempty(stream)
    s = randi(n);
else
    s = randi(stream, n);
end
end
