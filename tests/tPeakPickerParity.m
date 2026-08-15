function tests = tPeakPickerParity
%TPEAKPICKERPARITY The two pickers must differ in the threshold rule and nothing else.
%
%   At M4 the fixed and adaptive pickers are compared head to head, and the
%   comparison only means something if everything except the admission rule is
%   held identical: the same struct contract, the same neighbourhood geometry,
%   the same boundary handling, the same dB reference, and the density cap
%   applied exactly once to both.
%
%   THE CAP WAS BEING APPLIED TWICE ON THE ADAPTIVE PATH. PICKPEAKS calls
%   ENFORCEPEAKDENSITY after dispatching, and PICKPEAKSADAPTIVE also called it
%   internally. The selection is idempotent so no score ever moved, which is
%   why it survived - but the second pass overwrote peaks.nBeforeDensity with
%   the already-capped count. That field is the raw pre-cap peak count and it
%   is what PLOTPEAKDENSITYVSSNR draws to demonstrate the mechanism behind
%   Enhancement 1b. Correct for fixed and corrupted for adaptive, it would
%   have made the mechanism figure understate the effect it exists to show.
%
%   Milestone: M4.  Blueprint: section 3.3.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
setupPaths();
testCase.TestData.Cfg = baselineConfig();
testCase.TestData.Smag = syntheticSpectrogram(testCase.TestData.Cfg);
end

% =======================================================================
function testBothPickersReturnTheSameContract(testCase)
Cfg  = testCase.TestData.Cfg;
Smag = testCase.TestData.Smag;

pf = pickPeaksFixed(Smag, Cfg);

Ca = Cfg;
Ca.peaks.mode = 'adaptive';
pa = pickPeaksAdaptive(Smag, Ca);

for f = {'tIdx', 'fIdx', 'magDb', 'nFrames'}
    verifyTrue(testCase, isfield(pf, f{1}), sprintf('fixed is missing %s', f{1}));
    verifyTrue(testCase, isfield(pa, f{1}), sprintf('adaptive is missing %s', f{1}));
    verifyClass(testCase, pa.(f{1}), class(pf.(f{1})), ...
        sprintf('Field %s has a different type in the two pickers.', f{1}));
end

verifyEqual(testCase, pa.nFrames, pf.nFrames, ...
    'The pickers disagree about the frame count of the same spectrogram.');
end

% =======================================================================
function testNeitherPickerAppliesTheDensityCapItself(testCase)
% The cap belongs to PICKPEAKS, once, for both modes. A picker that caps
% internally reports a pre-cap count that has already been capped.
Cfg  = testCase.TestData.Cfg;
Smag = testCase.TestData.Smag;

for mode = {'fixed', 'adaptive'}
    C = Cfg;
    C.peaks.mode = mode{1};

    switch mode{1}
        case 'fixed',    raw = pickPeaksFixed(Smag, C);
        case 'adaptive', raw = pickPeaksAdaptive(Smag, C);
    end

    verifyFalse(testCase, isfield(raw, 'nBeforeDensity'), ...
        sprintf(['%s picker returned nBeforeDensity, so it applied the density ' ...
                 'cap itself. PICKPEAKS owns that step.'], mode{1}));
    verifyFalse(testCase, isfield(raw, 'densityPerSec'), ...
        sprintf('%s picker returned densityPerSec; it should not cap.', mode{1}));
end
end

% =======================================================================
function testDispatcherReportsTheTrueRawPeakCount(testCase)
% nBeforeDensity must equal what the picker actually produced, for both modes.
Cfg  = testCase.TestData.Cfg;
Smag = testCase.TestData.Smag;

for mode = {'fixed', 'adaptive'}
    C = Cfg;
    C.peaks.mode = mode{1};

    switch mode{1}
        case 'fixed',    raw = pickPeaksFixed(Smag, C);
        case 'adaptive', raw = pickPeaksAdaptive(Smag, C);
    end

    capped = pickPeaks(Smag, C);

    verifyEqual(testCase, capped.nBeforeDensity, numel(raw.tIdx), ...
        sprintf(['nBeforeDensity (%d) does not match the %s picker''s raw output ' ...
                 '(%d). The cap has run more than once.'], ...
                 capped.nBeforeDensity, mode{1}, numel(raw.tIdx)));

    verifyLessThanOrEqual(testCase, numel(capped.tIdx), numel(raw.tIdx), ...
        'The cap produced more peaks than the picker emitted.');
end
end

% =======================================================================
function testCapIsIdempotent(testCase)
% Relied on above, and worth asserting directly: applying the cap to an
% already-capped set must be a no-op.
Cfg  = testCase.TestData.Cfg;
Smag = testCase.TestData.Smag;

once  = pickPeaks(Smag, Cfg);
twice = enforcePeakDensity(once, once.nFrames, Cfg);

verifyEqual(testCase, twice.tIdx, once.tIdx, 'Second cap pass changed the peak set.');
verifyEqual(testCase, twice.fIdx, once.fIdx, 'Second cap pass changed the peak set.');
end

% =======================================================================
function testAdaptiveRejectsAnEvenNeighbourhood(testCase)
% The fixed picker errors clearly on an even neighbourhood; the adaptive one
% used to accept it and silently use an off-centre window.
Cfg = testCase.TestData.Cfg;
Cfg.peaks.mode  = 'adaptive';
Cfg.peaks.nbhdF = 16;

verifyError(testCase, @() pickPeaksAdaptive(testCase.TestData.Smag, Cfg), ...
    'HimigTransform:EvenNeighbourhood');
end

% =======================================================================
function testAdaptiveHandlesDigitalSilence(testCase)
% A query can legitimately land on a silent lead-in. Both pickers must return
% an empty constellation rather than erroring or admitting the whole plane.
Cfg = testCase.TestData.Cfg;
Cfg.peaks.mode = 'adaptive';

Smag = zeros(Cfg.derived.nBins, 200);
p    = pickPeaksAdaptive(Smag, Cfg);

verifyEmpty(testCase, p.tIdx, 'Silence produced peaks.');
verifyEqual(testCase, double(p.nFrames), 200, ...
    'nFrames was not reported for a silent spectrogram.');
end

% =======================================================================
function testAdaptiveAdmitsFewerPeaksAsKappaRises(testCase)
% Sanity on the admission rule itself: kappaDb is a threshold, so raising it
% must not admit more.
Cfg = testCase.TestData.Cfg;
Cfg.peaks.mode = 'adaptive';
Smag = testCase.TestData.Smag;

Cfg.peaks.kappaDb = 0;
low = pickPeaksAdaptive(Smag, Cfg);

Cfg.peaks.kappaDb = 24;
high = pickPeaksAdaptive(Smag, Cfg);

verifyLessThanOrEqual(testCase, numel(high.tIdx), numel(low.tIdx), ...
    'Raising kappaDb admitted more peaks.');
end

% =======================================================================
function Smag = syntheticSpectrogram(Cfg)
%SYNTHETICSPECTROGRAM A deterministic spectrogram with real structure.
%
%   Tones plus a decaying noise floor, so both pickers have something to
%   select and the density cap has something to bind on. Built from a fixed
%   RandStream so the test is reproducible without touching global state.

stream = RandStream('twister', 'Seed', 7);

nBins   = Cfg.derived.nBins;
nFrames = 600;

[F, T] = ndgrid(1:nBins, 1:nFrames);

Smag = 0.02 * abs(randn(stream, nBins, nFrames));
Smag = Smag + 0.5 * exp(-((F - 40).^2) / 50)  .* (1 + 0.5 * sin(2 * pi * T / 90));
Smag = Smag + 0.4 * exp(-((F - 110).^2) / 40) .* (1 + 0.5 * cos(2 * pi * T / 70));
Smag = Smag + 0.3 * exp(-((F - 200).^2) / 60) .* (1 + 0.5 * sin(2 * pi * T / 50));
Smag = abs(Smag);
end
