function h = packHash(f1, f2, dt, Cfg)
%PACKHASH Pack (anchor bin, target bin, time delta) into a uint32 code. Vectorised.
%
%   H = PACKHASH(F1, F2, DT, CFG) returns uint32 codes with the layout
%
%       bits 31..23   f1   anchor bin   (Cfg.hash.freqBits = 9, values 0..511)
%       bits 22..14   f2   target bin   (9 bits)
%       bits 13..0    dt   t2 - t1      (Cfg.hash.dtBits = 14, values 0..16383)
%
%   The maximum packed value is 511*2^23 + 511*2^14 + 16383, which is exactly
%   intmax('uint32'). The layout is tight and lossless - there is no spare bit
%   to borrow, so any change to freqBits or dtBits is a change to the whole
%   index format.
%
%   Inputs broadcast: any of F1, F2, DT may be scalar. H has the shape of the
%   non-scalar inputs.
%
%   Cfg.hash.freqDecim is applied to the bin indices BEFORE packing, as
%   floor(f / freqDecim). For the power-of-two values this accepts, that is
%   the right-shift the blueprint describes.
%
%   WHY DECIMATION IS HERE AND NOT SOMEWHERE MORE OBVIOUS. At freqDecim = 1 a
%   peak that drifts by a single bin under noise - 15.6 Hz, which is nothing -
%   produces a completely different hash and contributes zero to the match.
%   freqDecim = 2 coarsens to about 31 Hz, buying tolerance to spectral
%   smearing at the cost of discriminability, because more unrelated peak
%   pairs now collide. Which way that trade falls is an empirical question,
%   which is why blueprint 3.2 says to ablate it at M4 rather than guess.
%   Doing it at pack time means the knob costs nothing anywhere else.
%
%   EXACT INVERSE - WITH ONE CAVEAT. UNPACKHASH inverts the bit packing
%   exactly. It inverts PACKHASH as a whole only when freqDecim == 1, because
%   decimation throws information away on purpose; at freqDecim = 2 the round
%   trip returns the decimated bins, not the originals. tHashPack tests both
%   behaviours.
%
%   NO RANGE CHECK AGAINST nBins. The field holds 0..511 and the default grid
%   only uses 0..256, so the validation here is against the LAYOUT, not
%   against the current STFT. That is deliberate: it lets tHashPack exercise
%   the corners of the field, which is where an off-by-one in a shift hides.
%
%   Milestone: M1.  Blueprint: section 3.2.
%
%   See also UNPACKHASH, MAKEHASHES.

if nargin < 4 || isempty(Cfg)
    Cfg = defaultConfig();
end

freqBits = Cfg.hash.freqBits;
dtBits   = Cfg.hash.dtBits;
decim    = Cfg.hash.freqDecim;

if decim < 1 || decim ~= fix(decim) || bitand(uint32(decim), uint32(decim - 1)) ~= 0
    error('HimigTransform:BadFreqDecim', ...
        'Cfg.hash.freqDecim must be a positive power of two; got %g.', decim);
end

f1 = double(f1);
f2 = double(f2);
dt = double(dt);

maxF  = 2 ^ freqBits - 1;
maxDt = 2 ^ dtBits   - 1;

f1d = floor(f1 / decim);
f2d = floor(f2 / decim);

checkRange(f1d, 0, maxF,  'f1', freqBits);
checkRange(f2d, 0, maxF,  'f2', freqBits);
checkRange(dt,  0, maxDt, 'dt', dtBits);

% Computed in double, then cast once. Every intermediate is an exact integer
% far below 2^53, so this is lossless - and it sidesteps the question of
% whether MATLAB's integer arithmetic saturates or wraps at the top of the
% range, which is exactly where this function has to be right.
h = uint32(f1d * 2 ^ (freqBits + dtBits) + f2d * 2 ^ dtBits + dt);

end

% =======================================================================
function checkRange(v, lo, hi, name, bits)

if any(v(:) < lo) || any(v(:) > hi) || any(v(:) ~= fix(v(:)))
    error('HimigTransform:HashFieldOverflow', ...
        ['%s must be an integer in [%d, %d] to fit its %d-bit field ' ...
         '(after freqDecim, where it applies). Offending range: [%g, %g].'], ...
        name, lo, hi, bits, min(v(:)), max(v(:)));
end

end