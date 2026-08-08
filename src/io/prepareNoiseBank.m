function noiseTable = prepareNoiseBank(Cfg)
%PREPARENOISEBANK Convert the DEMAND recordings into the 8 kHz mono noise bank.
%
%   Takes channel 01 of the 16 kHz DEMAND release and resamples to 8 kHz:
%     PCAFETER -> cafe      (busy office cafeteria)
%     STRAFFIC -> traffic   (busy traffic intersection)
%     SPSQUARE -> crowd     (public town square)
%   DEMAND is CC BY-SA 3.0: attribute it in the paper, and do not
%   redistribute
%   mixed audio derived from it.
%
%   Milestone: M0.  Blueprint: section(s) 1.4, 2.5.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also MIXATSNR, SYNTHESIZEQUERY.

error('HimigTransform:NotImplemented', ...
    'prepareNoiseBank is a stub (Milestone M0). See docs/designNotes.md.');

end
