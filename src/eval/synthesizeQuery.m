function [y, meas] = synthesizeQuery(manifestRow, catalog, Cfg)
%SYNTHESIZEQUERY Reconstruct one query waveform from its manifest row.
%
%   Deterministic and reproducible bit-for-bit from (songID, startSample,
%   noiseFile, noiseStartSample, targetSnrDb, seed). Returns
%   meas.snrDbMeasured
%   for verification.
%
%   Milestone: M3.  Blueprint: section(s) 0 (D2), 2.5.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also BUILDQUERYMANIFEST, MIXATSNR.

error('HimigTransform:NotImplemented', ...
    'synthesizeQuery is a stub (Milestone M3). See docs/designNotes.md.');

end
