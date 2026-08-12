function fileTable = makeToyLibrary(Cfg, varargin)
%MAKETOYLIBRARY Synthesise the five-song toy library used by M0 and M1.
%
%   FILETABLE = MAKETOYLIBRARY(CFG) writes five synthetic WAV files under
%   data/toy/raw, laid out exactly like data/raw so INGESTLIBRARY's scanner
%   treats them the same way, and returns a table describing what it wrote.
%
%   Name-value options:
%       'RawRoot'   write somewhere other than data/toy/raw
%       'Force'     true regenerates files that already exist
%
%   WHY SYNTHETIC AUDIO. The M0 exit criterion needs a five-song set to ingest
%   and M1's tSelfMatch needs one to match against, but no real music can live
%   in the repository - data/raw is gitignored and the group's libraries are
%   licensed for personal use, not redistribution (blueprint 1.4). Generating
%   the toy set from a seed solves both problems at once: it is byte-identical
%   on every machine, it costs nothing in the repo, and it means the fresh-
%   clone rehearsal at M8 can run the tests on a machine holding no audio at
%   all. It also decouples the five workstreams in blueprint 10 from the data
%   sourcing risk R2 - nobody waits on the 120 songs to start writing code.
%
%   THE SET EXERCISES THE INGEST PATH ON PURPOSE. The five files differ in
%   sample rate (44100, 22050, 48000, 16000 and 8000 Hz), channel count and
%   level, so a single run of s01_ingest covers every branch that matters at
%   M0: the 80/441 and 160/441 rational resampling ratios, an integer 6:1 and
%   2:1 decimation, the fsIn == fsOut passthrough, the stereo downmix, and an
%   18 dB spread of source loudness for RMSNORMALIZE to close up. The
%   filenames vary too, so BUILDCATALOG's metadata parser meets a leading
%   track number, a bracketed year, and a file with no artist at all.
%
%   THE SIGNALS ARE DESIGNED NOT TO REPEAT. Each track is a seeded, non-
%   repeating sequence of notes over a slower bass line, with noise-burst
%   transients and a low broadband floor. The non-repetition is the important
%   part and it is easy to get wrong: a toy track built from a looped two-bar
%   phrase produces an offset histogram with several equally tall peaks, so
%   score1 and score2 come out nearly equal, and tSelfMatch's "margin > 3"
%   fails for a reason that has nothing to do with the matcher being broken.
%   Different seeds also keep the five tracks harmonically distinct from one
%   another, which is what makes the margin large when the matcher is right.
%
%   These are not music and are not meant to sound like music. They are a
%   dense, reproducible, unambiguous constellation of spectral peaks.
%
%   Milestone: M0.  Blueprint: sections 1.4, 7 (M0).
%
%   See also INGESTLIBRARY, BUILDCATALOG, LOADAUDIO.

if nargin < 1 || isempty(Cfg)
    Cfg = defaultConfig();
end

projRoot = setupPaths();

opt = parseOpts(struct( ...
    'RawRoot', fullfile(projRoot, 'data', 'toy', 'raw'), ...
    'Force',   false), varargin);

%   relative path (forward slashes)                              fsSrc  nCh  durSec  rmsDbfs  seed offset
spec = { ...
    'american/Toy Ensemble - Blue Meridian (1998).wav',          44100,  2,   38,     -12,     1
    'american/02. Toy Ensemble - Copper Lantern.wav',            22050,  1,   45,     -24,     2
    'opm/Toy Kundiman - Hanging Sa Umaga (2004).wav',            48000,  2,   41,     -16,     3
    'opm/Paalam Na Sinta.wav',                                   16000,  1,   35,     -30,     4
    'holdout/american/Toy Ensemble - Ninth Harbour (2011).wav',   8000,  1,   33,     -20,     5
    };

nFile = size(spec, 1);

relPath     = strings(nFile, 1);
repertoire  = strings(nFile, 1);
role        = strings(nFile, 1);
fsSource    = zeros(nFile, 1);
nChannels   = zeros(nFile, 1);
durationSec = zeros(nFile, 1);
rmsDbfs     = zeros(nFile, 1);
action      = strings(nFile, 1);

logMsg('info', 'Toy library: target %s', opt.RawRoot);

for k = 1:nFile
    rel     = spec{k, 1};
    fsSrc   = spec{k, 2};
    nCh     = spec{k, 3};
    durSec  = spec{k, 4};
    levelDb = spec{k, 5};
    seedOff = spec{k, 6};

    outFile = fullfile(opt.RawRoot, strrep(rel, '/', filesep));
    outDir  = fileparts(outFile);
    if ~isfolder(outDir)
        mkdir(outDir);
    end

    parts         = strsplit(rel, '/');
    repertoire(k) = string(parts{find(ismember(parts, {'american', 'opm'}), 1)});
    if any(strcmp(parts, 'holdout'))
        role(k) = "holdout";
    else
        role(k) = "db";
    end

    relPath(k)   = string(rel);
    fsSource(k)  = fsSrc;
    nChannels(k) = nCh;

    if ~opt.Force && isfile(outFile)
        ai = audioinfo(outFile);
        if ai.SampleRate == fsSrc && ai.NumChannels == nCh
            y              = audioread(outFile);
            durationSec(k) = ai.TotalSamples / ai.SampleRate;
            rmsDbfs(k)     = 20 * log10(max(sqrt(mean(y(:, 1) .^ 2)), realmin));
            action(k)      = "skipped";
            continue
        end
        logMsg('warn', 'Toy library: %s exists but is %d Hz / %d ch - regenerating.', ...
            rel, ai.SampleRate, ai.NumChannels);
    end

    % Seed offset by track, so the five tracks are independent of each other
    % but the whole set is a deterministic function of Cfg.seed alone.
    y = synthesizeToyTrack(durSec, fsSrc, nCh, levelDb, Cfg.seed + 1000 * seedOff);

    audiowrite(outFile, y, fsSrc, 'BitsPerSample', 16);

    ai             = audioinfo(outFile);
    durationSec(k) = ai.TotalSamples / ai.SampleRate;
    rmsDbfs(k)     = 20 * log10(max(sqrt(mean(y(:, 1) .^ 2)), realmin));
    action(k)      = "written";

    logMsg('info', 'Toy library: %s  (%d Hz, %d ch, %.0f s, %.1f dBFS)', ...
        rel, fsSrc, nCh, durationSec(k), rmsDbfs(k));
end

fileTable = table(relPath, repertoire, role, fsSource, nChannels, ...
    durationSec, rmsDbfs, action, ...
    'VariableNames', {'relPath', 'repertoire', 'role', 'fsSource', ...
                      'nChannels', 'durationSec', 'rmsDbfs', 'action'});

logMsg('info', 'Toy library: %d written, %d already present.', ...
    nnz(action == "written"), nnz(action == "skipped"));

end

% =======================================================================
function y = synthesizeToyTrack(durSec, fs, nCh, targetRmsDbfs, seedVal)
%SYNTHESIZETOYTRACK One deterministic pseudo-musical track.
%
%   Three layers, all bandlimited well below 4 kHz so nothing is lost to the
%   anti-alias filter on the way to 8 kHz, plus a broadband floor that IS
%   partly discarded - which is the point, since it means the downsampler is
%   doing visible work rather than copying samples.

rng(seedVal, 'twister');

n = round(durSec * fs);
x = zeros(n, 1);

MAX_HZ    = 3800;                    % keep partials inside the 8 kHz band
scale     = [0 2 4 5 7 9 11];        % major scale, in semitones
rootMidi  = 55 + randi([0 6]);       % G3 .. D4, per track
noteSec   = 0.20 + 0.12 * rand();    % per track, so the tracks differ in pace
nNote     = floor(durSec / noteSec);

% ---- Melody: a non-repeating note sequence ----------------------------
for k = 1:nNote
    midi = rootMidi + scale(randi(numel(scale))) + 12 * randi([1 2]);
    f0   = 440 * 2 ^ ((midi - 69) / 12);

    i0  = round((k - 1) * noteSec * fs) + 1;
    i1  = min(n, i0 + round(1.7 * noteSec * fs) - 1);   % notes overlap slightly
    idx = (i0:i1)';
    if numel(idx) < 8
        continue
    end
    tau = (idx - i0) / fs;

    env = (1 - exp(-tau / 0.006)) .* exp(-tau / (0.18 + 0.30 * rand()));

    tone = zeros(numel(idx), 1);
    for h = 1:8
        fh = h * f0;
        if fh > MAX_HZ
            break
        end
        tone = tone + (1 / h ^ 1.3) * sin(2 * pi * fh * tau + 2 * pi * rand());
    end

    x(idx) = x(idx) + 0.7 * env .* tone;
end

% ---- Bass: same material an octave and a half down, four times slower ---
bassSec = 4 * noteSec;
nBass   = floor(durSec / bassSec);

for k = 1:nBass
    midi = rootMidi - 12 + scale(randi(numel(scale)));
    f0   = 440 * 2 ^ ((midi - 69) / 12);

    i0  = round((k - 1) * bassSec * fs) + 1;
    i1  = min(n, i0 + round(0.95 * bassSec * fs) - 1);
    idx = (i0:i1)';
    if numel(idx) < 8
        continue
    end
    tau = (idx - i0) / fs;

    env  = (1 - exp(-tau / 0.010)) .* exp(-tau / (0.6 * bassSec));
    tone = sin(2 * pi * f0 * tau) + 0.35 * sin(2 * pi * 2 * f0 * tau);

    x(idx) = x(idx) + 0.5 * env .* tone;
end

% ---- Transients: short noise bursts on a steady grid -------------------
% Broadband and sharply time-localised, so the constellation gets peaks that
% are pinned in time rather than only in frequency.
hitSec = 2 * noteSec;
nHit   = floor(durSec / hitSec);

for k = 1:nHit
    i0  = round((k - 1) * hitSec * fs) + 1;
    i1  = min(n, i0 + round(0.05 * fs) - 1);
    idx = (i0:i1)';
    if numel(idx) < 4
        continue
    end
    tau = (idx - i0) / fs;

    x(idx) = x(idx) + 0.30 * exp(-tau / 0.012) .* randn(numel(idx), 1);
end

% ---- Broadband floor ---------------------------------------------------
x = x + 10 ^ (-45 / 20) * randn(n, 1);

% ---- Level -------------------------------------------------------------
x = rmsNormalize(x, targetRmsDbfs);

% ---- Channels ----------------------------------------------------------
% A second channel that is nearly, but not exactly, the first. Enough to make
% the downmix in LOADAUDIO a real operation; not so much that a comb filter
% appears in the mono sum and quietly changes the spectrum being tested.
if nCh == 2
    y = [x, 0.95 * x + 0.05 * std(x) * randn(n, 1)];
else
    y = x;
end

% ---- Clip guard --------------------------------------------------------
pk = max(abs(y(:)));
if pk > 0.999
    y = y * (0.999 / pk);
end

end

% =======================================================================
function opt = parseOpts(opt, args)
%PARSEOPTS Minimal name-value parsing, matching INGESTLIBRARY.

if mod(numel(args), 2) ~= 0
    error('HimigTransform:BadOptions', 'Options must be name-value pairs.');
end

valid = fieldnames(opt);

for k = 1:2:numel(args)
    name = char(args{k});
    hit  = valid(strcmpi(valid, name));
    if isempty(hit)
        error('HimigTransform:BadOption', ...
            'Unknown option "%s". Valid: %s.', name, strjoin(valid', ', '));
    end
    opt.(hit{1}) = args{k + 1};
end

end