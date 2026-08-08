function [x, fs] = loadAudio(filePath, Cfg)
%LOADAUDIO Read an audio file and return it as mono double at Cfg.audio.fs.
%
%   Wraps audioread, mixes to mono, and resamples via RESAMPLEAUDIO. This is
%   the ONLY place in the project that touches audioread - everything else
%   goes through here so the ingest contract stays in one file.
%
%   Milestone: M0.  Blueprint: section(s) 1.2, 4.
%
%   STATUS: stub. The contract above is frozen (blueprint section 5); the body
%   is written at the milestone named above.
%
%   See also RESAMPLEAUDIO, PREPROCESSSIGNAL.

error('HimigTransform:NotImplemented', ...
    'loadAudio is a stub (Milestone M0). See docs/designNotes.md.');

end
