function [f1, f2, dt] = unpackHash(h, Cfg)
%UNPACKHASH Exact inverse of the PACKHASH bit layout. Vectorised.
%
%   [F1, F2, DT] = UNPACKHASH(H, CFG) recovers the three packed fields from
%   uint32 codes H. Outputs are double, the same shape as H.
%
%   Used for diagnostics and for the constellation overlay in the GUI: given a
%   hash that contributed to a match, this is what says which two peaks it
%   came from so they can be drawn.
%
%   THE VALUES ARE IN THE DECIMATED DOMAIN. When Cfg.hash.freqDecim > 1,
%   PACKHASH divided the bin indices before packing, so F1 and F2 come back
%   divided too. Multiply by Cfg.hash.freqDecim to get back to STFT bins, and
%   remember the result is only accurate to within freqDecim - 1 bins,
%   because the decimation was lossy by design. At the default freqDecim = 1
%   the round trip is exact and this caveat disappears.
%
%   Milestone: M1.  Blueprint: section 3.2.
%
%   See also PACKHASH.

if nargin < 2 || isempty(Cfg)
    Cfg = defaultConfig();
end

freqBits = Cfg.hash.freqBits;
dtBits   = Cfg.hash.dtBits;

h = uint32(h);

dt = double(bitand(h, uint32(2 ^ dtBits - 1)));
f2 = double(bitand(bitshift(h, -dtBits), uint32(2 ^ freqBits - 1)));
f1 = double(bitshift(h, -(freqBits + dtBits)));

end