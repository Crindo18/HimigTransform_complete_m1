function y = resampleAudio(x, fsIn, fsOut, method)
%RESAMPLEAUDIO Anti-aliased sample-rate conversion.
%
%   Y = RESAMPLEAUDIO(X, FSIN, FSOUT) converts the column signal X from FSIN
%   to FSOUT with anti-alias filtering. Output length is
%   CEIL(NUMEL(X)*FSOUT/FSIN), matching RESAMPLE, so the two paths below are
%   drop-in interchangeable.
%
%   Y = RESAMPLEAUDIO(X, FSIN, FSOUT, METHOD) forces a path:
%       'auto'      Signal Processing Toolbox if licensed, else fallback (default)
%       'toolbox'   RESAMPLE; errors if the toolbox is missing
%       'fallback'  base-MATLAB windowed-sinc resampler
%   The METHOD argument exists so tests can compare the two paths against each
%   other on a machine that has the toolbox (see tDataSpine).
%
%   Why a hand-written fallback. Per blueprint 1.2 every toolbox call sits
%   behind a wrapper with a base-MATLAB fallback, and RESAMPLE is the one
%   genuinely required toolbox function. The obvious substitutes - DECIMATE,
%   UPFIRDN, FIR1, FILTFILT, HAMMING - are all Signal Processing Toolbox as
%   well, so the fallback has to be written from primitives.
%
%   The fallback is bandlimited interpolation: each output sample is a
%   windowed-sinc weighted sum of nearby input samples, with the sinc cutoff
%   set to the lower of the two Nyquist rates. That is the same operation
%   polyphase resampling performs, evaluated directly instead of via a filter
%   bank. Zero-stuffing by P and filtering would be textbook-correct and
%   catastrophic here: 44100 -> 8000 is P/Q = 80/441, so the intermediate rate
%   is 3.5 MHz and a 3-minute track becomes 740 million samples. Direct
%   evaluation keeps the cost at O(nOut * taps) with bounded memory.
%
%   It is slower than RESAMPLE by roughly an order of magnitude. That is the
%   correct trade: a member without the toolbox can still run the pipeline,
%   just not quickly.
%
%   Milestone: M0.  Blueprint: section 1.2.
%
%   See also LOADAUDIO, REQUIRETOOLBOX, RESAMPLE.

persistent warnedOnce

if nargin < 4 || isempty(method)
    method = 'auto';
end
method = lower(char(method));

validateattributes(x,     {'numeric'}, {'vector', 'real', 'finite'}, mfilename, 'x');
validateattributes(fsIn,  {'numeric'}, {'scalar', 'positive', 'finite'}, mfilename, 'fsIn');
validateattributes(fsOut, {'numeric'}, {'scalar', 'positive', 'finite'}, mfilename, 'fsOut');

x = double(x(:));

if fsIn == fsOut
    y = x;
    return
end

[p, q] = rateFactors(fsIn, fsOut);

switch method
    case 'auto'
        if requireToolbox('signal', 'optional')
            y = resample(x, p, q);
        else
            if isempty(warnedOnce)
                logMsg('warn', ...
                    ['Signal Processing Toolbox not available - using the base-MATLAB ' ...
                     'windowed-sinc resampler. Correct but roughly 10x slower. ' ...
                     'This message appears once per session.']);
                warnedOnce = true;
            end
            y = sincResample(x, p, q);
        end

    case 'toolbox'
        requireToolbox('signal', 'require');
        y = resample(x, p, q);

    case 'fallback'
        y = sincResample(x, p, q);

    otherwise
        error('HimigTransform:BadMethod', ...
            'method must be auto, toolbox or fallback (got "%s").', method);
end

y = y(:);

end

% =======================================================================
function [p, q] = rateFactors(fsIn, fsOut)
%RATEFACTORS Smallest integer P/Q with P/Q == fsOut/fsIn.

if fsIn == round(fsIn) && fsOut == round(fsOut)
    g = gcd(round(fsIn), round(fsOut));
    p = round(fsOut) / g;
    q = round(fsIn)  / g;
else
    [p, q] = rat(fsOut / fsIn, 1e-9);
end

end

% =======================================================================
function y = sincResample(x, p, q)
%SINCRESAMPLE Bandlimited interpolation in base MATLAB.
%
%   Output sample m (0-based) sits at input position m*q/p. The kernel is a
%   Hamming-windowed sinc with cutoff at MIN(1, p/q) of the input Nyquist,
%   truncated at L zero crossings each side, and normalised per output sample
%   so DC gain is exactly 1 (truncation otherwise leaves a small ripple).

L     = 12;                  % zero crossings retained either side
nIn   = numel(x);
ratio = p / q;               % fsOut / fsIn
nOut  = ceil(nIn * ratio);   % matches RESAMPLE's output length
fc    = min(1, ratio);       % normalised cutoff, 1 == input Nyquist
hw    = ceil(L / fc);        % kernel half-width, in input samples

xPad = [zeros(hw, 1); x; zeros(hw, 1)];
y    = zeros(nOut, 1);
offs = -hw:hw;

% Chunk so the working arrays stay around 2M elements regardless of the rate
% conversion ratio.
chunk = max(1, floor(2e6 / numel(offs)));

for m0 = 1:chunk:nOut
    m1 = min(m0 + chunk - 1, nOut);

    tt = ((m0:m1)' - 1) / ratio;    % 0-based position in the input grid
    kc = floor(tt);                 % 0-based index of the nearest input sample
    u  = tt - (kc + offs);          % distance to each tap, in input samples

    w = fc * sincHT(fc * u) .* (0.54 + 0.46 * cos(pi * u / (hw + 1)));
    w(abs(u) > hw) = 0;
    w = w ./ sum(w, 2);

    idx = kc + offs + hw + 1;       % 1-based index into xPad
    y(m0:m1) = sum(xPad(idx) .* w, 2);
end

end

% =======================================================================
function s = sincHT(u)
%SINCHT sin(pi*u)/(pi*u), with the removable singularity filled in.
%
%   Named to avoid shadowing SINC, which lives in the Signal Processing
%   Toolbox - shadowing it would be exactly the naming trap of blueprint 4.1.

s = ones(size(u));
nz = u ~= 0;
s(nz) = sin(pi * u(nz)) ./ (pi * u(nz));

end