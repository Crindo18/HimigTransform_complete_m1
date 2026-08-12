function tf = requireToolbox(name, mode)
%REQUIRETOOLBOX Check for a toolbox and dispatch to a fallback or fail clearly.
%
%   TF = REQUIRETOOLBOX(NAME) returns true when the named toolbox is both
%   licensed and installed. NAME is one of:
%
%       'signal'    Signal Processing Toolbox
%       'audio'     Audio Toolbox
%       'image'     Image Processing Toolbox
%       'stats'     Statistics and Machine Learning Toolbox
%       'parallel'  Parallel Computing Toolbox
%
%   TF = REQUIRETOOLBOX(NAME, 'optional') is the same, and is how a caller
%   with a base-MATLAB fallback asks the question. This is the default.
%
%   TF = REQUIRETOOLBOX(NAME, 'require') errors when the toolbox is absent.
%   The error names the toolbox, what the project needs it for and what the
%   documented fallback is, so the reader knows whether to install something
%   or to call the fallback path directly.
%
%   REQUIRETOOLBOX() with no arguments prints a capability report for all five
%   toolboxes and returns it as a table. Run it once when a new member joins,
%   or at the top of a debugging session that is producing results nobody else
%   can reproduce.
%
%   WHY THIS EXISTS. Blueprint 1.2 makes it a rule that every toolbox call
%   sits behind a wrapper with a base-MATLAB fallback. The failure this
%   prevents is specific and expensive: five people develop separately, one of
%   them has a student licence without the Image Processing Toolbox, nobody
%   notices because that person is writing the evaluation harness, and the
%   first time the code runs end-to-end on their machine is integration week,
%   where it dies on an undefined MEDFILT2 with no indication that a licence
%   is the cause. Asking the question explicitly turns that into a readable
%   sentence at the moment of the call.
%
%   ONLY RESAMPLE IS GENUINELY REQUIRED. Everything else has a fallback that
%   the project actually uses (blueprint 1.2): MOVMEDIAN replaces MEDFILT2,
%   ACCUMARRAY plus HEATMAP replaces CONFUSIONCHART, AUDIORECORDER replaces
%   AUDIODEVICEREADER, and PARFOR degrades to a serial FOR by itself. Even
%   RESAMPLE has one - RESAMPLEAUDIO carries a hand-written windowed-sinc path
%   - so 'require' should be rare in this codebase. If you find yourself
%   reaching for it, ask whether a fallback is really impossible first.
%
%   WHAT "AVAILABLE" MEANS HERE. Licensed and installed are different things
%   and both are checked: LICENSE('test') reports what the licence file
%   permits even for a product that was never installed, and VER reports what
%   is installed even when no licence will check it out. A network licence
%   whose seats are all in use still reports as available, because the
%   checkout only happens on the first real call - that case surfaces as a
%   licence error from RESAMPLE itself, which is already legible.
%
%   Results are cached per session. LICENSE and VER are slow enough to matter
%   when RESAMPLEAUDIO asks once per file across 120 files, and a licence
%   cannot appear or vanish mid-session in any way worth handling.
%
%   Milestone: M0.  Blueprint: section 1.2.
%
%   See also RESAMPLEAUDIO, LICENSE, VER.

persistent cache

TB = toolboxTable();

% ---- No arguments: capability report -----------------------------------
if nargin == 0
    tf = capabilityReport(TB);
    return
end

if nargin < 2 || isempty(mode)
    mode = 'optional';
end

name = lower(char(name));
mode = lower(char(mode));

if ~any(strcmp(mode, {'require', 'optional'}))
    error('HimigTransform:BadMode', ...
        'mode must be ''require'' or ''optional'' (got "%s").', mode);
end

idx = find(strcmp(name, {TB.key}), 1);
if isempty(idx)
    error('HimigTransform:UnknownToolbox', ...
        'Unknown toolbox key "%s". Valid keys: %s.', name, strjoin({TB.key}, ', '));
end
T = TB(idx);

% ---- Probe, once per session per toolbox -------------------------------
if isempty(cache)
    cache = struct();
end

if isfield(cache, name)
    tf = cache.(name);
else
    tf = probeToolbox(T);
    cache.(name) = tf;
end

if ~tf && strcmp(mode, 'require')
    error('HimigTransform:MissingToolbox', ...
        ['%s is required at this call site and is not available on this machine.\n' ...
         '  Needed for : %s\n' ...
         '  Fallback   : %s\n' ...
         'Blueprint 1.2 lists a fallback for every toolbox. If you cannot install the ' ...
         'toolbox, call the fallback path explicitly rather than working around this check.'], ...
        T.product, T.usedFor, T.fallback);
end

end

% =======================================================================
function tf = probeToolbox(T)
%PROBETOOLBOX Licensed AND present. Both, because either alone lies.

tf = false;

try
    licensed = license('test', T.feature) == 1;
catch
    % An unknown feature name returns 0 rather than throwing on every
    % platform, but do not let a licence-manager hiccup take down the caller.
    licensed = false;
end

if ~licensed
    return
end

installed = false;
try
    installed = ~isempty(ver(T.verDir));
catch
    installed = false;
end

if ~installed
    % VER keys off the installation directory name, which a few site
    % installations rearrange. A direct look for the probe function is the
    % more reliable answer when it disagrees.
    installed = exist(T.probeFcn, 'file') > 0 || exist(T.probeFcn, 'builtin') > 0;
end

tf = licensed && installed;

end

% =======================================================================
function report = capabilityReport(TB)
%CAPABILITYREPORT Print, and return, the availability of all five toolboxes.

n         = numel(TB);
available = false(n, 1);

for k = 1:n
    available(k) = requireToolbox(TB(k).key, 'optional');
end

report = table( ...
    string({TB.key}'), string({TB.product}'), available, ...
    string({TB.usedFor}'), string({TB.fallback}'), ...
    'VariableNames', {'key', 'product', 'available', 'usedFor', 'fallback'});

fprintf('\n--- Toolbox capability (MATLAB %s) ---\n', version('-release'));
for k = 1:n
    if available(k)
        mark = 'yes';
    else
        mark = 'NO ';
    end
    fprintf('  %-9s %-3s  %s\n', TB(k).key, mark, TB(k).product);
    if ~available(k)
        fprintf('  %-9s      falls back to: %s\n', '', TB(k).fallback);
    end
end

if ~available(strcmp({TB.key}, 'signal'))
    fprintf(['\n  NOTE: the Signal Processing Toolbox is the one blueprint 1.2 calls\n' ...
             '  required. resampleAudio still works without it, roughly 10x slower.\n' ...
             '  Ingest of 120 songs will take noticeably longer on this machine.\n']);
end
fprintf('--------------------------------------\n\n');

end

% =======================================================================
function TB = toolboxTable()
%TOOLBOXTABLE The blueprint 1.2 dependency policy, as data.

spec = { ...
%   key         licence feature              ver dir     probe function        product name                                used for                                                fallback
    'signal',   'Signal_Toolbox',            'signal',   'resample',           'Signal Processing Toolbox',                'resample for the anti-aliased 8 kHz downsample',       'the base-MATLAB windowed-sinc path inside resampleAudio'
    'audio',    'Audio_System_Toolbox',      'audio',    'audioDeviceReader',  'Audio Toolbox',                            'live microphone capture in the GUI',                   'audiorecorder, plus dir and a loop instead of audioDatastore'
    'image',    'Image_Toolbox',             'images',   'medfilt2',           'Image Processing Toolbox',                 '2-D local median for adaptive peak picking (Enh 1b)',  'movmedian along frequency then time (separable approximation)'
    'stats',    'Statistics_Toolbox',        'stats',    'confusionmat',       'Statistics and Machine Learning Toolbox',  'confusionmat and confusionchart for the repertoire analysis', 'accumarray plus heatmap, both base MATLAB'
    'parallel', 'Distrib_Computing_Toolbox', 'parallel', 'parpool',            'Parallel Computing Toolbox',               'parfor over enrolment and the evaluation grid',        'parfor degrades to a serial for automatically when unlicensed'
    };

nTb = size(spec, 1);
TB  = struct('key', {}, 'feature', {}, 'verDir', {}, 'probeFcn', {}, ...
             'product', {}, 'usedFor', {}, 'fallback', {});

for k = 1:nTb
    TB(k).key      = spec{k, 1};
    TB(k).feature  = spec{k, 2};
    TB(k).verDir   = spec{k, 3};
    TB(k).probeFcn = spec{k, 4};
    TB(k).product  = spec{k, 5};
    TB(k).usedFor  = spec{k, 6};
    TB(k).fallback = spec{k, 7};
end

TB = reshape(TB, 1, nTb);

end