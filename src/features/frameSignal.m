function F = frameSignal(sig, winLen, hop)
%FRAMESIGNAL Split a signal into overlapping frames, one frame per column.
%
%   Hand-rolled framing. Returns [winLen x nFrames]. The trailing partial
%   frame
%   is dropped, so nFrames = floor((numel(sig)-winLen)/hop) + 1.
%
%   Milestone: M1.  Blueprint: section(s) 3.1.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also COMPUTESTFT.

error('HimigTransform:NotImplemented', ...
    'frameSignal is a stub (Milestone M1). See docs/designNotes.md.');

end
