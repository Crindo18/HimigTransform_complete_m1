function noiseTable = prepareNoiseBank(Cfg, varargin)
%PREPARENOISEBANK Convert the DEMAND recordings into the 8 kHz mono noise bank.
%
%   NOISETABLE = PREPARENOISEBANK(CFG) finds channel 01 of the three DEMAND
%   recordings under data/noise/source, resamples each to CFG.audio.fs, and
%   writes them to data/noise:
%
%       PCAFETER -> cafe      busy office cafeteria
%       STRAFFIC -> traffic   busy traffic intersection
%       SPSQUARE -> crowd     public town square with tourists
%
%   Name-value options: 'SourceRoot', 'NoiseRoot', 'Force'.
%
%   NOISETABLE has one row per noise type: noiseType, demandCode, file,
%   durationSec, fsSource, rmsDbfs, sha256. s02_prepareNoise writes it to
%   db/noiseBank.csv, which is committed for the same reason catalog.csv is -
%   it is the checksum record proving every member mixed against byte-identical
%   noise, and it carries no audio.
%
%   TWO THINGS THAT ARE EASY TO GET WRONG HERE
%
%   Level is left alone. It is tempting to normalise the noise as well, but
%   MIXATSNR derives its gain from the measured power of both the excerpt and
%   the noise segment, so pre-normalising changes nothing about the resulting
%   SNR and only makes the stored file differ from the source for no reason.
%   The one exception is a clip guard on the write, since resampling can
%   overshoot a full-scale source by a fraction of a dB.
%
%   Resample first, mix later. The noise arrives at 16 kHz and is band-limited
%   to 8 kHz here before any mixing happens. Mixing at the source rate and
%   downsampling afterwards would report an SNR measured over 0-8 kHz while
%   the system only ever hears 0-4 kHz, so every point on the x-axis of the
%   accuracy-versus-SNR figure would be optimistic by however much noise power
%   sat in the discarded band - and for traffic noise that is a lot. Blueprint
%   6.2 makes the same point from the other direction.
%
%   DEMAND is CC BY-SA 3.0. Attribute it in the paper. ShareAlike applies to
%   derivatives you redistribute, so do not publish mixed audio - which is
%   another reason queries are synthesised from a manifest rather than stored
%   (blueprint D2).
%
%   Milestone: M0.  Blueprint: sections 1.4, 2.5, 6.2.
%
%   See also MIXATSNR, SYNTHESIZEQUERY, LOADAUDIO.

projRoot = setupPaths();

opt = parseOpts(struct( ...
    'SourceRoot', fullfile(projRoot, 'data', 'noise', 'source'), ...
    'NoiseRoot',  fullfile(projRoot, 'data', 'noise'), ...
    'Force',      false), varargin);

spec = { ...
%   DEMAND code   noiseType   description
    'PCAFETER',   'cafe',     'busy office cafeteria'
    'STRAFFIC',   'traffic',  'busy traffic intersection'
    'SPSQUARE',   'crowd',    'public town square with tourists'};

if ~isfolder(opt.SourceRoot)
    error('HimigTransform:NoDemandSource', ...
        ['DEMAND source folder not found: %s\n' ...
         'Download the 16 kHz release from Zenodo record 1227121, unzip PCAFETER, ' ...
         'STRAFFIC and SPSQUARE into that folder, and re-run. See data/README.md.'], ...
        opt.SourceRoot);
end

if ~isfolder(opt.NoiseRoot)
    mkdir(opt.NoiseRoot);
end

nType      = size(spec, 1);
noiseType  = strings(nType, 1);
demandCode = strings(nType, 1);
fileName   = strings(nType, 1);
durationSec = zeros(nType, 1);
fsSource   = zeros(nType, 1);
rmsDbfs    = zeros(nType, 1);
sha256     = strings(nType, 1);

for k = 1:nType
    code = spec{k, 1};
    ntype = spec{k, 2};

    srcFile = findChannel01(opt.SourceRoot, code);

    outName = sprintf('%s_ch01_%dk.wav', code, round(Cfg.audio.fs / 1000));
    outFile = fullfile(opt.NoiseRoot, outName);

    if ~opt.Force && isfile(outFile)
        ai = audioinfo(outFile);
        if ai.SampleRate == Cfg.audio.fs && ai.NumChannels == 1
            logMsg('info', 'Noise bank: %s already present, skipping.', outName);
            [noiseType(k), demandCode(k), fileName(k)] = deal(string(ntype), string(code), string(outName));
            durationSec(k) = ai.TotalSamples / ai.SampleRate;
            fsSource(k)    = NaN;
            y              = audioread(outFile);
            rmsDbfs(k)     = 20 * log10(max(sqrt(mean(y.^2)), realmin));
            sha256(k)      = string(sha256File(outFile));
            continue
        end
        logMsg('warn', 'Noise bank: %s exists but is %d Hz / %d ch - rebuilding.', ...
            outName, ai.SampleRate, ai.NumChannels);
    end

    logMsg('info', 'Noise bank: %s (%s) <- %s', ntype, code, srcFile);

    [y, fs, info] = loadAudio(srcFile, Cfg);

    if info.nChannelsIn > 1
        logMsg('warn', ...
            ['%s has %d channels; expected a single-channel DEMAND file. ' ...
             'Check you took ch01.wav and not a multichannel export.'], code, info.nChannelsIn);
    end
    if abs(info.durationSec - 300) > 5
        logMsg('warn', ...
            '%s is %.1f s; DEMAND recordings are trimmed to 300 s. Verify you have the right file.', ...
            code, info.durationSec);
    end

    pk = max(abs(y));
    if pk > 0.999
        y = y * (0.999 / pk);
        logMsg('warn', '%s: peak %.2f dBFS after resampling; scaled down for the 16-bit write.', ...
            code, 20 * log10(pk));
    end

    audiowrite(outFile, y, fs, 'BitsPerSample', 16);

    ai = audioinfo(outFile);
    if ai.SampleRate ~= Cfg.audio.fs || ai.NumChannels ~= 1
        error('HimigTransform:BadNoiseFile', ...
            'Wrote %s at %d Hz / %d ch; expected %d Hz mono.', ...
            outName, ai.SampleRate, ai.NumChannels, Cfg.audio.fs);
    end

    noiseType(k)   = string(ntype);
    demandCode(k)  = string(code);
    fileName(k)    = string(outName);
    durationSec(k) = ai.TotalSamples / ai.SampleRate;
    fsSource(k)    = info.fsIn;
    rmsDbfs(k)     = 20 * log10(max(sqrt(mean(y.^2)), realmin));
    sha256(k)      = string(sha256File(outFile));
end

noiseTable = table( ...
    setcats(categorical(noiseType), Cfg.eval.noiseTypes), ...
    demandCode, fileName, durationSec, fsSource, rmsDbfs, sha256, ...
    'VariableNames', {'noiseType', 'demandCode', 'file', 'durationSec', ...
                      'fsSource', 'rmsDbfs', 'sha256'});

missingTypes = setdiff(Cfg.eval.noiseTypes, cellstr(string(noiseTable.noiseType)));
if ~isempty(missingTypes)
    error('HimigTransform:IncompleteNoiseBank', ...
        'Noise bank is missing: %s. Cfg.eval.noiseTypes expects all three.', ...
        strjoin(missingTypes, ', '));
end

logMsg('info', 'Noise bank ready: %d file(s) in %s.', height(noiseTable), opt.NoiseRoot);

end

% =======================================================================
function srcFile = findChannel01(sourceRoot, code)
%FINDCHANNEL01 Locate channel 01 of a DEMAND recording, whatever the layout.
%
%   The Zenodo release unzips to <CODE>_16k/ch01.wav, but people rename things
%   and re-zip things, so match on the code appearing anywhere in the path and
%   'ch01' appearing in the filename. Ambiguity is reported rather than
%   resolved silently: picking the wrong channel would be invisible in every
%   downstream number.

listing = dir(fullfile(sourceRoot, '**', '*.wav'));
listing = listing(~[listing.isdir]);

hit = false(numel(listing), 1);
for k = 1:numel(listing)
    full = fullfile(listing(k).folder, listing(k).name);
    hit(k) = contains(upper(full), upper(code)) && contains(lower(listing(k).name), 'ch01');
end

idx = find(hit);

if isempty(idx)
    error('HimigTransform:DemandFileNotFound', ...
        ['Could not find channel 01 of %s under %s.\n' ...
         'Expected something like %s_16k%sch01.wav. See data/README.md.'], ...
        code, sourceRoot, code, filesep);
end

if numel(idx) > 1
    % Prefer the 16 kHz release when both rates are present.
    prefer = idx(contains(lower({listing(idx).folder}'), '16k'));
    if isscalar(prefer)
        idx = prefer;
    else
        paths = arrayfun(@(k) fullfile(listing(k).folder, listing(k).name), idx, ...
            'UniformOutput', false);
        error('HimigTransform:AmbiguousDemandFile', ...
            'Multiple channel-01 candidates for %s:\n  %s\nLeave exactly one under %s.', ...
            code, strjoin(paths, sprintf('\n  ')), sourceRoot);
    end
end

srcFile = fullfile(listing(idx).folder, listing(idx).name);

end

% =======================================================================
function opt = parseOpts(opt, args)
%PARSEOPTS Minimal name-value parsing.

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