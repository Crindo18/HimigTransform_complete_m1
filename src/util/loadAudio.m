function [x, fs, info] = loadAudio(filePath, Cfg)
%LOADAUDIO Read an audio file and return it as mono double at Cfg.audio.fs.
%
%   [X, FS] = LOADAUDIO(FILEPATH, CFG) reads any format AUDIOREAD can open,
%   mixes to mono, and resamples to CFG.audio.fs via RESAMPLEAUDIO. X is a
%   double column vector; FS equals CFG.audio.fs.
%
%   [X, FS, INFO] = LOADAUDIO(...) also returns what the file looked like
%   before conversion: INFO.fsIn, INFO.nChannelsIn, INFO.nSamplesIn,
%   INFO.durationSec, INFO.peak, INFO.rmsDbfs. INGESTLIBRARY logs these so a
%   surprising result later can be traced to a surprising source file.
%
%   This is the ONLY place in the project that calls AUDIOREAD. Everything
%   else goes through here, so the ingest contract - mono, double, 8 kHz -
%   lives in one file and cannot drift between callers.
%
%   Level is deliberately NOT touched here. Normalisation belongs to
%   RMSNORMALIZE, called by INGESTLIBRARY on the way to disk and by
%   PREPROCESSSIGNAL on both the reference and query paths (blueprint 3.7).
%   Keeping the reader level-neutral means INFO.rmsDbfs reports the true
%   source level, which is what you want in the ingest report.
%
%   Milestone: M0.  Blueprint: sections 1.2, 4.
%
%   See also RESAMPLEAUDIO, RMSNORMALIZE, PREPROCESSSIGNAL.

if nargin < 2 || isempty(Cfg)
    Cfg = defaultConfig();
end

filePath = char(filePath);

if ~isfile(filePath)
    error('HimigTransform:FileNotFound', 'No such audio file: %s', filePath);
end

try
    [raw, fsIn] = audioread(filePath);
catch err
    error('HimigTransform:AudioReadFailed', ...
        'audioread could not open %s\n  (%s)\n  Codec support varies by platform - convert to WAV or FLAC and retry.', ...
        filePath, err.message);
end

raw = double(raw);

info = struct();
info.fsIn        = fsIn;
info.nChannelsIn = size(raw, 2);
info.nSamplesIn  = size(raw, 1);

if isempty(raw)
    error('HimigTransform:EmptyAudio', 'File decoded to zero samples: %s', filePath);
end

% ---- Mono downmix ------------------------------------------------------
% MEAN, not SUM: summing correlated channels adds up to 6 dB and can push a
% loud master past full scale before we have measured anything.
if size(raw, 2) > 1
    if ~Cfg.audio.mono
        error('HimigTransform:StereoUnsupported', ...
            ['Cfg.audio.mono is false but %s has %d channels. The whole pipeline ' ...
             'assumes a single channel; multichannel is out of scope.'], ...
            filePath, size(raw, 2));
    end
    x = mean(raw, 2);
else
    x = raw;
end
x = x(:);

% ---- Rate conversion ---------------------------------------------------
fs = Cfg.audio.fs;
x  = resampleAudio(x, fsIn, fs);

info.durationSec = numel(x) / fs;
info.peak        = max(abs(x));
if info.peak > 0
    info.rmsDbfs = 20 * log10(max(sqrt(mean(x.^2)), realmin));
else
    info.rmsDbfs = -Inf;
end

end