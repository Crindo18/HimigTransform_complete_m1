function Sclean = spectralSubtract(S, Nmag, Cfg)
%SPECTRALSUBTRACT Spectral-subtraction denoising, magnitude only, phase preserved.
%
%   |Shat| = max(|Y| - alpha*|Nhat|, beta*|Y|), original phase retained.
%
%   QUERY SIDE ONLY. References are clean and are never denoised. That
%   asymmetry is intentional but must be validated: denoising shifts peak
%   locations slightly, so a CLEAN query passed through the denoiser can
%   score
%   worse than one that was not. The M4 exit gate is <= 2 pp loss on clean
%   10 s queries; if it fails, gate the denoiser on estimated SNR instead of
%   running it unconditionally.
%
%   Milestone: M4.  Blueprint: section(s) 3.6, 3.7.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also ESTIMATENOISESPECTRUM, PREPROCESSSIGNAL.

error('HimigTransform:NotImplemented', ...
    'spectralSubtract is a stub (Milestone M4). See docs/designNotes.md.');

end
