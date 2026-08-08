function h = packHash(f1, f2, dt, Cfg)
%PACKHASH Pack (anchor bin, target bin, time delta) into a uint32 code. Vectorised.
%
%   Layout: bits 31..23 = f1 (9), bits 22..14 = f2 (9), bits 13..0 = dt
%   (14).
%   Maximum packed value is exactly intmax('uint32').
%
%   Cfg.hash.freqDecim is applied to the bin indices BEFORE packing.
%   Must be the exact inverse of UNPACKHASH over the full valid range,
%   including the edges - tHashPack enforces this.
%
%   Milestone: M1.  Blueprint: section(s) 3.2.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also UNPACKHASH, MAKEHASHES.

error('HimigTransform:NotImplemented', ...
    'packHash is a stub (Milestone M1). See docs/designNotes.md.');

end
