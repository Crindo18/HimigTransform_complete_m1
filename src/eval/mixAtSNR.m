function [y, g, snrMeasured] = mixAtSNR(x, n, snrDb)
%MIXATSNR Mix noise into a signal at a target SNR and report the achieved SNR.
%
%   g = sqrt(Px / (Pn * 10^(snrDb/10))); y = x + g*n. Rescale y if it clips
%   -
%   rescaling the mixture does not change the SNR.
%
%   Mix AFTER both signals are at 8 kHz so the reported SNR is the in-band
%   SNR
%   the system actually experiences. Compute power over the excerpt, never
%   the
%   whole song. tMixSNR asserts snrMeasured within 0.1 dB of target.
%
%   Milestone: M3.  Blueprint: section(s) 6.2.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also SYNTHESIZEQUERY, PREPARENOISEBANK.

error('HimigTransform:NotImplemented', ...
    'mixAtSNR is a stub (Milestone M3). See docs/designNotes.md.');

end
