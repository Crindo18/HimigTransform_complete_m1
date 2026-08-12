function F = frameSignal(sig, winLen, hop)
%FRAMESIGNAL Split a signal into overlapping frames, one frame per column.
%
%   F = FRAMESIGNAL(SIG, WINLEN, HOP) returns a [WINLEN x nFrames] matrix in
%   which column k holds samples (k-1)*HOP + (1:WINLEN) of SIG.
%
%   The trailing partial frame is DROPPED, so
%
%       nFrames = floor((numel(SIG) - WINLEN) / HOP) + 1
%
%   and a signal shorter than one frame returns a [WINLEN x 0] matrix rather
%   than erroring. Dropping the tail is what makes this agree exactly with
%   SPECTROGRAM's framing, which tSTFT depends on. It also avoids the
%   alternative - zero-padding the last frame - which would put an artificial
%   discontinuity at the end of every song and every query, producing a
%   broadband smear that the peak picker would happily pick up as a
%   constellation peak in a fixed location, in every single file.
%
%   No windowing happens here. COMPUTESTFT applies the window, because the
%   window is a property of the transform and not of the framing, and keeping
%   them apart is what lets the framing be tested on its own.
%
%   MEMORY. The output is a dense copy, roughly winLen/hop times the size of
%   the input - a factor of 2 at the default 50% overlap. A 6-minute track at
%   8 kHz produces about 77 MB. That is fine per song, but it is worth knowing
%   before setting a large parfor pool at M2.
%
%   Milestone: M1.  Blueprint: section 3.1.
%
%   See also COMPUTESTFT.

validateattributes(sig,    {'numeric'}, {'vector', 'real', 'finite'}, mfilename, 'sig');
validateattributes(winLen, {'numeric'}, {'scalar', 'integer', 'positive'}, mfilename, 'winLen');
validateattributes(hop,    {'numeric'}, {'scalar', 'integer', 'positive'}, mfilename, 'hop');

sig = double(sig(:));
n   = numel(sig);

if n < winLen
    F = zeros(winLen, 0);
    return
end

nFrames = floor((n - winLen) / hop) + 1;

% One vectorised gather. idx(:,k) holds the sample indices of frame k, so
% sig(idx) returns the frames directly - MATLAB gives the result the shape of
% the index, not of the source, which is why sig may be a row or a column.
idx = (1:winLen)' + (0:nFrames - 1) * hop;

F = sig(idx);

end