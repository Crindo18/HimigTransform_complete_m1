function app = HimigTransformApp()
%HIMIGTRANSFORMAPP Live identification GUI for HimigTransform.
%
%   HIMIGTRANSFORMAPP() opens the demonstration interface. It loads a query
%   from disk or records one from the microphone, identifies it against the
%   enrolled database, and shows the waveform, the constellation map, the
%   time-offset histogram, the ranked candidates and the open-set decision -
%   with a live toggle between the baseline and enhanced systems.
%
%   BUILT PROGRAMMATICALLY, NOT IN APP DESIGNER, AND DELIBERATELY.
%
%   A .mlapp is a binary container: Git cannot merge it, two people editing it
%   in the same week means one of them loses work, and nothing inside it can
%   be unit tested or code-reviewed. This file uses the same UI components
%   App Designer emits - uifigure, uigridlayout, uiaxes, uitable, uibutton -
%   so the result is the same MATLAB app, in a form that diffs, merges and
%   reviews like the rest of the project.
%
%   INDEXES ARE LOADED LAZILY AND CACHED. The enhanced index is ~72 MB, so
%   loading both at startup would blow the 30 s cold-start budget. The first
%   switch to a mode pays for that mode; every later switch is instant.
%
%   MICROPHONE CAPTURE IS BEST EFFORT. Permissions fail differently on every
%   OS and the venue machine is never the one you rehearsed on, so recording
%   failures are caught and reported in the status line rather than thrown -
%   and the Load File path always works. Keep a few WAVs from
%   data/demoQueries within reach (risk R11).
%
%   Milestone: M6.  Blueprint: sections 4.3, 7 (M6).
%
%   See also IDENTIFYQUERY, PLOTCONSTELLATION, PLOTOFFSETHISTOGRAM.

projRoot = setupPaths();

S = struct();
S.projRoot   = projRoot;
S.mode       = 'baseline';
S.Cfg        = systemConfig('baseline');
S.indexCache = containers.Map('KeyType', 'char', 'ValueType', 'any');
S.catalog    = [];
S.sig        = [];
S.res        = [];
S.recorder   = [];
S.player     = [];
S.recording  = false;

try
    S.catalog = loadCatalog(S.Cfg);
catch
    S.catalog = [];      % titles fall back to songID
end

% ---- Window -------------------------------------------------------------
S.fig = uifigure('Name', 'HimigTransform - live identification', ...
    'Position', [80 60 1240 800], 'Color', [1 1 1]);

outer = uigridlayout(S.fig, [2 1]);
outer.RowHeight   = {132, '1x'};
outer.ColumnWidth = {'1x'};

% ---- Controls -----------------------------------------------------------
ctl = uipanel(outer, 'Title', 'Query');
ctl.Layout.Row = 1;

g = uigridlayout(ctl, [2 7]);
g.RowHeight   = {32, 44};
g.ColumnWidth = {110, 110, 90, 150, 150, '1x', 210};

S.btnLoad = uibutton(g, 'push', 'Text', 'Load file...', ...
    'ButtonPushedFcn', @(~, ~) onLoad());
S.btnLoad.Layout.Row = 1; S.btnLoad.Layout.Column = 1;

S.btnRec = uibutton(g, 'push', 'Text', 'Record 10 s', ...
    'ButtonPushedFcn', @(~, ~) onRecord());
S.btnRec.Layout.Row = 1; S.btnRec.Layout.Column = 2;

S.btnPlay = uibutton(g, 'push', 'Text', 'Play', 'Enable', 'off', ...
    'ButtonPushedFcn', @(~, ~) onPlay());
S.btnPlay.Layout.Row = 1; S.btnPlay.Layout.Column = 3;

lblMode = uilabel(g, 'Text', 'System:', 'HorizontalAlignment', 'right');
lblMode.Layout.Row = 1; lblMode.Layout.Column = 4;

S.ddMode = uidropdown(g, ...
    'Items', {'baseline', 'enhanced'}, 'Value', 'baseline', ...
    'ValueChangedFcn', @(src, ~) onMode(src.Value));
S.ddMode.Layout.Row = 1; S.ddMode.Layout.Column = 5;

S.btnId = uibutton(g, 'push', 'Text', 'IDENTIFY', 'Enable', 'off', ...
    'FontSize', 15, 'FontWeight', 'bold', ...
    'BackgroundColor', [0.20 0.45 0.75], 'FontColor', [1 1 1], ...
    'ButtonPushedFcn', @(~, ~) onIdentify());
S.btnId.Layout.Row = [1 2]; S.btnId.Layout.Column = 7;

S.lblStatus = uilabel(g, 'Text', 'Load a file or record a clip to begin.', ...
    'FontSize', 12);
S.lblStatus.Layout.Row = 2; S.lblStatus.Layout.Column = [1 5];

S.lampBox = uigridlayout(g, [1 2]);
S.lampBox.Layout.Row = 2; S.lampBox.Layout.Column = 6;
S.lampBox.ColumnWidth = {24, '1x'};
S.lampBox.Padding = [0 0 0 0];

S.lamp = uilamp(S.lampBox, 'Color', [0.85 0.85 0.85]);
S.lamp.Layout.Row = 1; S.lamp.Layout.Column = 1;

S.lblVerdict = uilabel(S.lampBox, 'Text', '', 'FontWeight', 'bold');
S.lblVerdict.Layout.Row = 1; S.lblVerdict.Layout.Column = 2;

% ---- Plots and results --------------------------------------------------
body = uigridlayout(outer, [2 2]);
body.Layout.Row   = 2;
body.RowHeight    = {'1x', '1.15x'};
body.ColumnWidth  = {'1.4x', '1x'};

S.axWave = uiaxes(body);
S.axWave.Layout.Row = 1; S.axWave.Layout.Column = 1;
title(S.axWave, 'Waveform');
xlabel(S.axWave, 'Time (s)'); ylabel(S.axWave, 'Amplitude');

S.axHist = uiaxes(body);
S.axHist.Layout.Row = 1; S.axHist.Layout.Column = 2;
title(S.axHist, 'Time-offset histogram');

S.axSpec = uiaxes(body);
S.axSpec.Layout.Row = 2; S.axSpec.Layout.Column = 1;
title(S.axSpec, 'Spectrogram + constellation');

resPanel = uipanel(body, 'Title', 'Ranked candidates');
resPanel.Layout.Row = 2; resPanel.Layout.Column = 2;

rg = uigridlayout(resPanel, [2 1]);
rg.RowHeight = {'1x', 120};

S.tbl = uitable(rg, ...
    'ColumnName', {'rank', 'songID', 'title', 'artist', 'score'}, ...
    'ColumnWidth', {45, 60, 170, 130, 55}, ...
    'Data', cell(0, 5));
S.tbl.Layout.Row = 1;

S.txtDetail = uitextarea(rg, 'Editable', 'off', 'Value', {''});
S.txtDetail.Layout.Row = 2;

setStatus('Ready. Index loads on first identification.');

if nargout > 0
    app = S.fig;
end

% =====================================================================
% Callbacks
% =====================================================================

    function onLoad()
        startDir = fullfile(S.projRoot, 'data', 'demoQueries');
        if ~isfolder(startDir)
            startDir = S.projRoot;
        end

        [f, p] = uigetfile({'*.wav;*.mp3;*.flac;*.m4a', 'Audio files'}, ...
            'Select a query clip', startDir);
        figure(S.fig);                      % uigetfile steals focus
        if isequal(f, 0)
            return
        end

        try
            [x, fsIn] = audioread(fullfile(p, f));
        catch err
            setStatus(sprintf('Could not read %s: %s', f, err.message));
            return
        end

        x = double(x(:, 1));
        if fsIn ~= S.Cfg.audio.fs
            x = resampleAudio(x, fsIn, S.Cfg.audio.fs);
        end

        acceptSignal(x, sprintf('Loaded %s (%.1f s)', f, numel(x) / S.Cfg.audio.fs));
    end

    function onRecord()
        if S.recording
            stopRecording();
            return
        end

        try
            S.recorder = audiorecorder(S.Cfg.audio.fs, 16, 1);
            record(S.recorder);
        catch err
            setStatus(['Microphone unavailable: ' err.message ...
                       '  Use Load file instead.']);
            return
        end

        S.recording  = true;
        S.btnRec.Text = 'Stop';
        setStatus('Recording... press Stop, or wait 10 s.');

        t = timer('StartDelay', 10, 'TimerFcn', @(tm, ~) autoStop(tm));
        start(t);
    end

    function autoStop(tm)
        stop(tm); delete(tm);
        if S.recording
            stopRecording();
        end
    end

    function stopRecording()
        try
            stop(S.recorder);
            x = double(getaudiodata(S.recorder));
        catch err
            S.recording = false;
            S.btnRec.Text = 'Record 10 s';
            setStatus(['Recording failed: ' err.message]);
            return
        end

        S.recording   = false;
        S.btnRec.Text = 'Record 10 s';

        acceptSignal(x, sprintf('Recorded %.1f s', numel(x) / S.Cfg.audio.fs));
    end

    function onPlay()
        if isempty(S.sig)
            return
        end
        try
            S.player = audioplayer(0.9 * S.sig / max(abs(S.sig)), S.Cfg.audio.fs);
            play(S.player);
        catch err
            setStatus(['Playback unavailable: ' err.message]);
        end
    end

    function onMode(newMode)
        S.mode = newMode;
        S.Cfg  = systemConfig(newMode);
        setStatus(sprintf('System: %s (%s)', newMode, S.Cfg.tag));
        clearVerdict();
    end

    function onIdentify()
        if isempty(S.sig)
            return
        end

        minSamples = S.Cfg.stft.winLen;
        if numel(S.sig) < minSamples
            setStatus(sprintf('Clip is too short - need at least %.2f s.', ...
                minSamples / S.Cfg.audio.fs));
            return
        end

        dlg = uiprogressdlg(S.fig, 'Title', 'Identifying', ...
            'Message', sprintf('Loading the %s index...', S.mode), ...
            'Indeterminate', true);
        cleanup = onCleanup(@() close(dlg));

        try
            Idx = getIndex(S.mode);
        catch err
            setStatus(['Index unavailable: ' err.message]);
            return
        end

        dlg.Message = 'Matching...';

        try
            res = identifyQuery(S.sig, Idx, S.Cfg);
        catch err
            setStatus(['Identification failed: ' err.message]);
            return
        end

        S.res = res;
        showResult(res, Idx);
    end

% =====================================================================
% Helpers
% =====================================================================

    function acceptSignal(x, msg)
        S.sig = x(:);

        S.btnId.Enable   = 'on';
        S.btnPlay.Enable = 'on';

        t = (0:numel(S.sig) - 1) / S.Cfg.audio.fs;
        cla(S.axWave, 'reset');
        plot(S.axWave, t, S.sig, 'Color', [0.25 0.45 0.75]);
        xlim(S.axWave, [0 max(t(end), eps)]);
        xlabel(S.axWave, 'Time (s)'); ylabel(S.axWave, 'Amplitude');
        title(S.axWave, 'Waveform');

        cla(S.axSpec, 'reset'); title(S.axSpec, 'Spectrogram + constellation');
        cla(S.axHist, 'reset'); title(S.axHist, 'Time-offset histogram');
        S.tbl.Data = cell(0, 5);
        S.txtDetail.Value = {''};
        clearVerdict();

        setStatus(msg);
    end

    function Idx = getIndex(mode)
        Cfg = systemConfig(mode);

        if isKey(S.indexCache, Cfg.tag)
            Idx = S.indexCache(Cfg.tag);
            return
        end

        p = fullfile(S.projRoot, 'db', sprintf('index_%s.mat', Cfg.tag));
        if ~isfile(p)
            error('No index for "%s" at %s. Run s03_enroll for that system.', ...
                mode, p);
        end

        D   = load(p);
        Idx = D.Idx;
        S.indexCache(Cfg.tag) = Idx;
    end

    function showResult(res, Idx)
        Cfgq = resolveQueryConfig(S.Cfg, numel(S.sig) / S.Cfg.audio.fs);
        Smag = abs(computeSTFT(preprocessSignal(S.sig, S.Cfg.audio.fs, Cfgq), Cfgq));

        plotConstellation(Smag, res.peaks, S.Cfg, S.axSpec);
        plotOffsetHistogram(res, S.Cfg, S.axHist);

        rows = {};
        ranks = [res.pred1, res.pred2];
        scores = [res.score1, res.score2];
        for k = 1:2
            if ranks(k) < 1
                continue
            end
            [ttl, art] = songName(ranks(k));
            rows(end + 1, :) = {k, ranks(k), ttl, art, scores(k)}; %#ok<AGROW>
        end
        S.tbl.Data = rows;

        S.txtDetail.Value = { ...
            sprintf('normScore   %.4f   (tau %.4f)', res.normScore, S.Cfg.match.tau), ...
            sprintf('margin      %.2f     (rho %.2f)', res.margin, S.Cfg.match.rho), ...
            sprintf('query hashes %d over %.1f s', res.nQueryHashes, res.durationSec), ...
            sprintf('candidates   %d of %d enrolled', res.nCandidateSongs, ...
                    Idx.stats.nSongsEnrolled), ...
            sprintf('match time   %.1f ms  (fingerprint %.1f ms)', ...
                    1000 * res.tMatchSec, 1000 * res.tHashSec)};

        accepted = res.accepted;
        if isnan(accepted)
            accepted = res.normScore >= S.Cfg.match.tau && res.margin >= S.Cfg.match.rho;
        end

        if accepted
            [ttl, art] = songName(res.pred1);
            S.lamp.Color = [0.20 0.75 0.35];
            S.lblVerdict.Text = sprintf('MATCH - %s', ttl);
            setStatus(sprintf('%s - %s   (%s system, %.0f ms)', ...
                ttl, art, S.mode, 1000 * res.tTotalSec));
        else
            S.lamp.Color = [0.85 0.30 0.25];
            S.lblVerdict.Text = 'NO MATCH';
            setStatus(sprintf(['Below threshold - reported as no match. ' ...
                'Best guess was songID %d at normScore %.4f.'], ...
                res.pred1, res.normScore));
        end
    end

    function [ttl, art] = songName(id)
        ttl = sprintf('songID %d', id);
        art = '';
        if isempty(S.catalog) || id < 1
            return
        end
        row = S.catalog(S.catalog.songID == id, :);
        if isempty(row)
            return
        end
        ttl = char(row.title(1));
        art = char(row.artist(1));
    end

    function clearVerdict()
        S.lamp.Color      = [0.85 0.85 0.85];
        S.lblVerdict.Text = '';
    end

    function setStatus(msg)
        S.lblStatus.Text = msg;
        drawnow limitrate;
    end

end
