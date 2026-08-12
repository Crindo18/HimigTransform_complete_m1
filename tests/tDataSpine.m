function tests = tDataSpine
%TDATASPINE The M0 data spine: level, checksums, capability, schema, resampling.
%
%   Everything downstream is built on these five functions being right, and
%   each of them fails in a way that is invisible later. A checksum that is
%   subtly wrong still looks like a checksum. A resampler that aliases still
%   produces audio. An RMS normaliser that is off by a factor of two still
%   produces a plausible waveform, and the error only surfaces as an SNR axis
%   that is wrong by 6 dB in a figure nobody can debug in week 9.
%
%   Unlike the other test files, this one is fully live from M0 - there is
%   nothing here to assumeFail, because everything it covers is implemented.
%
%   Milestone: M0.  Blueprint: sections 1.2, 2.2, 5, 6.1, 7 (M0).
tests = functiontests(localfunctions);
end

% =======================================================================
% Fixtures
% =======================================================================
function setupOnce(testCase)
setupPaths();
testCase.TestData.Cfg    = defaultConfig();
testCase.TestData.tmpDir = tempname();
mkdir(testCase.TestData.tmpDir);
end

function teardownOnce(testCase)
if isfolder(testCase.TestData.tmpDir)
    rmdir(testCase.TestData.tmpDir, 's');
end
end

% =======================================================================
% rmsNormalize
% =======================================================================
function testRmsNormalizeHitsTargetExactly(testCase)
% CONTRACT: 20*log10(rms(y)) == targetRmsDbfs, for any input level.
rng(1, 'twister');

targets = [-20 -14 -30 -6];
inputs  = {randn(8000, 1), 0.001 * randn(8000, 1), 12 * randn(8000, 1)};

for t = targets
    for k = 1:numel(inputs)
        y      = rmsNormalize(inputs{k}, t);
        outDb  = 20 * log10(sqrt(mean(y .^ 2)));
        verifyEqual(testCase, outDb, t, 'AbsTol', 1e-9, ...
            sprintf('Target %.0f dBFS not reached for input %d.', t, k));
    end
end
end

function testRmsNormalizeReportsTheGainItApplied(testCase)
% CONTRACT: gainDb is the gain actually applied, so ingestLibrary's report
% column means what it says.
rng(2, 'twister');
x = 0.02 * randn(4000, 1);

[y, gainDb] = rmsNormalize(x, -20);

expected = 20 * log10(sqrt(mean(y .^ 2)) / sqrt(mean(x .^ 2)));
verifyEqual(testCase, gainDb, expected, 'AbsTol', 1e-9);
end

function testRmsNormalizeDefaultsToConfigTarget(testCase)
% No magic numbers: the default must come from Cfg, not from a literal.
Cfg = testCase.TestData.Cfg;
rng(3, 'twister');

y     = rmsNormalize(randn(4000, 1));
outDb = 20 * log10(sqrt(mean(y .^ 2)));
verifyEqual(testCase, outDb, Cfg.audio.targetRmsDbfs, 'AbsTol', 1e-9);
end

function testRmsNormalizeSurvivesSilence(testCase)
% CONTRACT: digital silence returns unchanged with 0 dB of gain. The failure
% mode being prevented is 0 * Inf = NaN propagating into the STFT.
[y, gainDb] = rmsNormalize(zeros(1000, 1), -20);

verifyEqual(testCase, y, zeros(1000, 1));
verifyEqual(testCase, gainDb, 0);
verifyTrue(testCase, all(isfinite(y)), 'Silence produced non-finite output.');
end

function testRmsNormalizePreservesShapeAndRejectsNonFinite(testCase)
row = rmsNormalize(randn(1, 500), -20);
verifySize(testCase, row, [1 500], 'Orientation was not preserved.');

bad    = randn(100, 1);
bad(7) = NaN;
verifyError(testCase, @() rmsNormalize(bad, -20), 'HimigTransform:NonFiniteAudio');
end

% =======================================================================
% sha256File
% =======================================================================
function testSha256MatchesPublishedVectors(testCase)
% CONTRACT: the digest is a real SHA-256, verified against published vectors
% rather than against itself. A checksum that is merely self-consistent still
% catches drift between members, but only a correct one can be compared with
% anything computed outside MATLAB (sha256sum, certutil, a Zenodo listing).
d = testCase.TestData.tmpDir;

emptyFile = fullfile(d, 'empty.bin');
fid = fopen(emptyFile, 'w'); fclose(fid);
verifyEqual(testCase, sha256File(emptyFile), ...
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', ...
    'Digest of the empty file is wrong.');

abcFile = fullfile(d, 'abc.bin');
fid = fopen(abcFile, 'w'); fwrite(fid, uint8('abc'), 'uint8'); fclose(fid);
verifyEqual(testCase, sha256File(abcFile), ...
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', ...
    'Digest of "abc" is wrong.');
end

function testSha256IsCorrectAcrossAChunkBoundary(testCase)
% CONTRACT: streaming in 1 MiB chunks gives the same answer as hashing whole.
% This file is 2^20 + 3 bytes, so the final read returns 3 bytes and the
% Java overload resolution in sha256File is exercised at the edge.
d = testCase.TestData.tmpDir;
f = fullfile(d, 'chunk.bin');

bytes = uint8(mod(0:(2 ^ 20 + 2), 256));

fid = fopen(f, 'w'); fwrite(fid, bytes, 'uint8'); fclose(fid);

verifyEqual(testCase, sha256File(f), ...
    '7bd9eef8bb7f99e63ea0266fd5e9e82c994c0292e0889d0af96ec099ee46e6b7', ...
    'Digest is wrong across the 1 MiB chunk boundary.');
end

function testSha256IsStableAndDiscriminating(testCase)
d = testCase.TestData.tmpDir;

a = fullfile(d, 'a.bin');
b = fullfile(d, 'b.bin');

fid = fopen(a, 'w'); fwrite(fid, uint8(1:200),  'uint8'); fclose(fid);
fid = fopen(b, 'w'); fwrite(fid, uint8([1:199 201]), 'uint8'); fclose(fid);

verifyEqual(testCase, sha256File(a), sha256File(a), 'Digest is not stable.');
verifyNotEqual(testCase, sha256File(a), sha256File(b), ...
    'A one-byte difference produced the same digest.');
verifyEqual(testCase, numel(sha256File(a)), 64);
end

function testSha256ErrorsOnMissingFile(testCase)
verifyError(testCase, ...
    @() sha256File(fullfile(testCase.TestData.tmpDir, 'nope.bin')), ...
    'HimigTransform:FileNotFound');
end

% =======================================================================
% requireToolbox
% =======================================================================
function testRequireToolboxAnswersEveryDocumentedKey(testCase)
keys = {'signal', 'audio', 'image', 'stats', 'parallel'};

for k = 1:numel(keys)
    tf = requireToolbox(keys{k}, 'optional');
    verifyClass(testCase, tf, 'logical', ...
        sprintf('requireToolbox(''%s'') did not return a logical.', keys{k}));
    verifyTrue(testCase, isscalar(tf));
end
end

function testRequireToolboxRejectsUnknownInput(testCase)
verifyError(testCase, @() requireToolbox('nosuchtoolbox', 'optional'), ...
    'HimigTransform:UnknownToolbox');
verifyError(testCase, @() requireToolbox('signal', 'maybe'), ...
    'HimigTransform:BadMode');
end

function testRequireModeIsConsistentWithOptionalMode(testCase)
% CONTRACT: 'require' errors exactly when 'optional' returns false. If these
% two ever disagree, some call sites silently take a fallback while others
% throw, and the machine-to-machine difference is invisible.
if requireToolbox('signal', 'optional')
    verifyWarningFree(testCase, @() requireToolbox('signal', 'require'));
else
    verifyError(testCase, @() requireToolbox('signal', 'require'), ...
        'HimigTransform:MissingToolbox');
end
end

% =======================================================================
% catalogSchema
% =======================================================================
function testCatalogSchemaDeclaresBlueprintColumns(testCase)
% CONTRACT: the columns and their order are blueprint 2.2, exactly. Order
% matters because buildCatalog assembles the table with {S.name}.
S = catalogSchema();

expected = {'songID', 'title', 'artist', 'repertoire', 'role', 'split', ...
            'year', 'sourcePath', 'procPath', 'durationSec', 'sha256'};

verifyEqual(testCase, {S.name}, expected, ...
    'catalog columns or their order drifted from blueprint 2.2.');

verifyEqual(testCase, S(strcmp({S.name}, 'repertoire')).cats, {'american', 'opm'});
verifyEqual(testCase, S(strcmp({S.name}, 'role')).cats,       {'db', 'holdout'});
verifyEqual(testCase, S(strcmp({S.name}, 'split')).cats,      {'dev', 'test'});

% Integer columns import as double on purpose, so an empty CSV cell arrives
% as NaN and can be told apart from a genuine zero.
verifyEqual(testCase, S(strcmp({S.name}, 'songID')).import, 'double');
verifyEqual(testCase, S(strcmp({S.name}, 'songID')).final,  'uint16');
end

function testCatalogSurvivesACsvRoundTrip(testCase)
% CONTRACT: write with writetable, read with loadCatalog, get the types back.
% This is the failure loadCatalog exists to prevent: an all-empty sha256
% column returning as double NaN, categoricals returning as cellstr.
Cfg = testCase.TestData.Cfg;
p   = fullfile(testCase.TestData.tmpDir, 'catalogRoundTrip.csv');

fileList = struct( ...
    'relPath',    {'american/A - One (1999).wav', 'opm/B - Two.wav', ...
                   'holdout/opm/C - Three (2015).wav'}, ...
    'name',       {'A - One (1999).wav', 'B - Two.wav', 'C - Three (2015).wav'}, ...
    'repertoire', {'american', 'opm', 'opm'}, ...
    'role',       {'db', 'db', 'holdout'});

built = buildCatalog(fileList, Cfg, p);
writetable(built, p);
readBack = loadCatalog(Cfg, p);

verifyEqual(testCase, height(readBack), 3);
verifyClass(testCase, readBack.songID,     'uint16');
verifyClass(testCase, readBack.repertoire, 'categorical');
verifyClass(testCase, readBack.role,       'categorical');
verifyClass(testCase, readBack.sha256,     'string', ...
    'An all-empty sha256 column came back as the wrong type.');
verifyEqual(testCase, readBack.songID, built.songID);
verifyEqual(testCase, categories(readBack.role), {'db'; 'holdout'}, ...
    'Category list was not restored from the schema.');

% Metadata parsing. Rows are located by content rather than by position:
% buildCatalog sorts by sourcePath before assigning IDs, so hard-coding a row
% number here would make the test fail the first time someone edits a fixture
% filename, for a reason unrelated to what is being tested.
one = readBack(readBack.sourcePath == "american/A - One (1999).wav", :);
verifyEqual(testCase, height(one), 1);
verifyEqual(testCase, one.artist, "A");
verifyEqual(testCase, one.title,  "One");
verifyEqual(testCase, one.year,   uint16(1999));

two = readBack(readBack.sourcePath == "opm/B - Two.wav", :);
verifyEqual(testCase, two.artist, "B");
verifyEqual(testCase, two.year,   uint16(0), 'A missing year should be 0, not NaN.');

% The folder layout is authoritative for role and repertoire.
held = readBack(contains(readBack.sourcePath, "holdout"), :);
verifyEqual(testCase, height(held), 1);
verifyEqual(testCase, string(held.role),       "holdout");
verifyEqual(testCase, string(held.repertoire), "opm");
end

% =======================================================================
% resampleAudio
% =======================================================================
function testResampleLengthAndPassthroughContracts(testCase)
% CONTRACT: output length is ceil(n*fsOut/fsIn) on BOTH paths, so the two are
% drop-in interchangeable; equal rates return the input untouched.
rng(4, 'twister');
x = randn(44100, 1);

expected = ceil(numel(x) * 8000 / 44100);
verifyEqual(testCase, numel(resampleAudio(x, 44100, 8000, 'fallback')), expected);

if requireToolbox('signal', 'optional')
    verifyEqual(testCase, numel(resampleAudio(x, 44100, 8000, 'toolbox')), expected, ...
        'The two resampling paths return different lengths.');
end

verifyEqual(testCase, resampleAudio(x, 8000, 8000), x, ...
    'Equal rates did not pass through unchanged.');
end

function testResampleActuallyAntiAliases(testCase)
% CONTRACT: content above the output Nyquist is filtered out, NOT folded back.
% A 6 kHz tone at 16 kHz would alias to 2 kHz if the filter were missing -
% and 2 kHz sits in the middle of the band the fingerprint cares about, so
% this would show up as phantom constellation peaks in every song.
fsIn  = 16000;
t     = (0:fsIn * 2 - 1)' / fsIn;
tone  = sin(2 * pi * 6000 * t);

for method = {'fallback', 'toolbox'}
    if strcmp(method{1}, 'toolbox') && ~requireToolbox('signal', 'optional')
        continue
    end
    y = resampleAudio(tone, fsIn, 8000, method{1});
    % Ignore the filter's edge transients.
    core = y(200:end - 200);
    verifyLessThan(testCase, sqrt(mean(core .^ 2)), 0.10, ...
        sprintf('%s path let a 6 kHz tone through to 8 kHz output.', method{1}));
end
end

function testResamplePreservesAnInBandTone(testCase)
% CONTRACT: a 300 Hz tone survives 44.1 kHz -> 8 kHz at the right frequency
% and the right level. Frequency is checked from the spectrum rather than by
% eyeballing the waveform.
fsIn = 44100;
t    = (0:fsIn * 2 - 1)' / fsIn;
tone = 0.5 * sin(2 * pi * 300 * t);

y    = resampleAudio(tone, fsIn, 8000, 'fallback');
core = y(200:end - 200);

verifyEqual(testCase, sqrt(mean(core .^ 2)), 0.5 / sqrt(2), 'RelTol', 0.02, ...
    'Level changed through the resampler.');

nfft   = 2 ^ nextpow2(numel(core));
mag    = abs(fft(core, nfft));
mag    = mag(1:nfft / 2 + 1);
[~, i] = max(mag);
peakHz = (i - 1) * 8000 / nfft;

verifyEqual(testCase, peakHz, 300, 'AbsTol', 8000 / nfft, ...
    'Dominant frequency moved through the resampler.');
end

function testResampleBackendsAgree(testCase)
% CONTRACT: the base-MATLAB fallback is a real substitute, not an
% approximation that quietly changes the spectrum. The two use different
% filter designs, so they will not match to machine precision - what matters
% is that a member without the toolbox gets the same fingerprints.
assumeTrue(testCase, requireToolbox('signal', 'optional'), ...
    'Signal Processing Toolbox absent - nothing to compare the fallback against.');

rng(5, 'twister');
fsIn = 44100;
t    = (0:fsIn - 1)' / fsIn;
x    = 0.3 * sin(2 * pi * 440 * t) + 0.2 * sin(2 * pi * 1200 * t) ...
     + 0.01 * randn(fsIn, 1);

yTb = resampleAudio(x, fsIn, 8000, 'toolbox');
yFb = resampleAudio(x, fsIn, 8000, 'fallback');

verifyEqual(testCase, numel(yFb), numel(yTb));

% Interior only: the two filters have different group delay and different
% edge behaviour, and neither matters to a fingerprint.
a = yTb(200:end - 200);
b = yFb(200:end - 200);

relErr = sqrt(mean((a - b) .^ 2)) / sqrt(mean(a .^ 2));
verifyLessThan(testCase, relErr, 0.05, ...
    'The two resampling paths disagree by more than 5% RMS.');
end

% =======================================================================
% loadAudio
% =======================================================================
function testLoadAudioEnforcesTheIngestContract(testCase)
% CONTRACT: whatever goes in, a mono double column at Cfg.audio.fs comes out,
% and info reports the SOURCE properties - which is what the ingest report
% needs in order to be worth reading.
Cfg = testCase.TestData.Cfg;
f   = fullfile(testCase.TestData.tmpDir, 'stereo441.wav');

rng(6, 'twister');
fsIn   = 44100;
t      = (0:fsIn * 3 - 1)' / fsIn;
stereo = [0.3 * sin(2 * pi * 440 * t), 0.3 * sin(2 * pi * 660 * t)];
audiowrite(f, stereo, fsIn, 'BitsPerSample', 16);

[x, fs, info] = loadAudio(f, Cfg);

verifyEqual(testCase, fs, Cfg.audio.fs);
verifyEqual(testCase, size(x, 2), 1, 'Output is not mono.');
verifyClass(testCase, x, 'double');
verifyTrue(testCase, iscolumn(x), 'Output is not a column vector.');
verifyEqual(testCase, info.fsIn, fsIn);
verifyEqual(testCase, info.nChannelsIn, 2);
verifyEqual(testCase, info.durationSec, 3, 'AbsTol', 0.01);

% Level must be untouched by the reader: normalisation belongs to
% rmsNormalize, and info.rmsDbfs has to report the true source level.
verifyEqual(testCase, info.rmsDbfs, 20 * log10(sqrt(mean(x .^ 2))), 'AbsTol', 1e-9);
verifyLessThan(testCase, info.rmsDbfs, -5, ...
    'Reader appears to have normalised the level.');

verifyError(testCase, @() loadAudio(fullfile(testCase.TestData.tmpDir, 'nope.wav'), Cfg), ...
    'HimigTransform:FileNotFound');
end

% =======================================================================
% Project plumbing
% =======================================================================
function testSetupPathsIsIdempotentAndMakesWorkingFolders(testCase)
% M8's fresh-clone rehearsal depends on this: a clone carries no gitignored
% folder, so setupPaths has to create them rather than assume them.
root = setupPaths();
verifyTrue(testCase, isfolder(root));

verifyWarningFree(testCase, @() setupPaths());

for f = {'data', 'db', 'results'}
    verifyTrue(testCase, isfolder(fullfile(root, f{1})), ...
        sprintf('setupPaths did not create %s/.', f{1}));
end

verifyTrue(testCase, isfolder(fullfile(root, 'data', 'processed', 'mono8k')));
verifyTrue(testCase, isfolder(fullfile(root, 'data', 'noise')));
verifyTrue(testCase, isfolder(fullfile(root, 'db', 'fingerprints')));
end

function testNoProjectFileShadowsAToolboxFunction(testCase)
% Blueprint 4.1: a file called stft.m or hamming.m in src/ shadows the
% toolbox function for the entire session, which would break tSTFT - the very
% test meant to catch STFT bugs - in a way that looks like a DSP failure.
root      = setupPaths();
forbidden = {'stft', 'spectrogram', 'resample', 'hamming', 'sinc', ...
             'medfilt2', 'movmedian', 'confusionmat', 'accumarray'};

listing = dir(fullfile(root, 'src', '**', '*.m'));
names   = erase({listing.name}, '.m');

clash = intersect(lower(names), forbidden);
verifyEmpty(testCase, clash, ...
    sprintf('These files under src/ shadow toolbox functions: %s', strjoin(clash, ', ')));
end