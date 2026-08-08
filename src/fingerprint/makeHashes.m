function [h, t1] = makeHashes(peaks, Cfg)
%MAKEHASHES Pair anchor and target peaks and pack them into 32-bit hash codes.
%
%   For each anchor a, take targets b with dtMin <= t_b - t_a <= dtMax and
%   |f_b - f_a| <= dfMaxBins, keep the nearest Cfg.hash.fanout by time, and
%   emit (packHash(f_a, f_b, dt), t_a).
%
%   Cfg must already be resolved for the calling side: enrolment passes Cfg
%   unchanged, the query path passes RESOLVEQUERYCONFIG(Cfg, durationSec).
%
%   Milestone: M1.  Blueprint: section(s) 3.4.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also PACKHASH, RESOLVEQUERYCONFIG, PICKPEAKS.

error('HimigTransform:NotImplemented', ...
    'makeHashes is a stub (Milestone M1). See docs/designNotes.md.');

end
