classdef AppController < handle
%APPCONTROLLER All logic behind the HimigTransform App Designer GUI.
%
%   The .mlapp file is a thin view: it wires widgets to methods on this class
%   and does nothing else. Two reasons this split matters.
%
%   1. .mlapp is a BINARY container. Git cannot merge it. Two group members
%      editing the app in the same week means one of them loses work. Assign a
%      single owner for HimigTransformApp.mlapp; everyone else contributes
%      here and in src/viz, which are plain text and merge normally.
%
%   2. Logic in a plain classdef is testable. Logic inside a .mlapp is not.
%
%   Lifecycle
%       ctrl = AppController(Cfg);
%       ctrl.loadIndex();          % once, at StartupFcn, behind a progress dlg
%       res  = ctrl.identify(sig); % per query
%
%   Milestone: M6.  Blueprint: sections 4.3, 7 (M6).
%
%   STATUS: stub. Properties and method signatures are the contract; bodies
%   are written at M6.
%
%   See also IDENTIFYQUERY, PLOTCONSTELLATION, PLOTOFFSETHISTOGRAM.

    properties (SetAccess = private)
        Cfg              struct        % active configuration
        Idx                            % loaded index (see blueprint 2.4)
        Catalog          table         % songID -> title / artist / repertoire
        Mode             char = 'baseline'   % 'baseline' | 'enhanced'
        LastResult       struct        % most recent identifyQuery output
        IndexLoadSec     double = NaN  % reported separately from match time
    end

    properties (Access = private)
        Recorder                       % audiorecorder (base MATLAB, no Audio
                                       % Toolbox dependency)
    end

    methods
        function obj = AppController(Cfg)
            %APPCONTROLLER Construct a controller for a given configuration.
            error('HimigTransform:NotImplemented', ...
                'AppController is a stub (Milestone M6).');
        end

        function loadIndex(obj, mode)
            %LOADINDEX Load the index for 'baseline' or 'enhanced' once.
            %   Called from StartupFcn behind a uiprogressdlg. Cold start to
            %   first identification must be under 30 s on the demo laptop.
            %   Both modes must be switchable without restarting the app.
            error('HimigTransform:NotImplemented', 'loadIndex is a stub (M6).');
        end

        function sig = loadQueryFile(obj, filePath)
            %LOADQUERYFILE Read a query clip from disk.
            error('HimigTransform:NotImplemented', 'loadQueryFile is a stub (M6).');
        end

        function startRecording(obj, durationSec)
            %STARTRECORDING Capture a live query via audiorecorder.
            %   Microphone permissions fail differently on every OS. Rehearse
            %   on the actual demo machine at M8 and keep the pre-recorded WAV
            %   fallback set within reach (risk R11).
            error('HimigTransform:NotImplemented', 'startRecording is a stub (M6).');
        end

        function sig = stopRecording(obj)
            %STOPRECORDING End capture and return the recorded signal.
            error('HimigTransform:NotImplemented', 'stopRecording is a stub (M6).');
        end

        function res = identify(obj, sig)
            %IDENTIFY Run the active pipeline and cache the result.
            error('HimigTransform:NotImplemented', 'identify is a stub (M6).');
        end

        function setMode(obj, mode)
            %SETMODE Switch between the baseline and enhanced systems.
            error('HimigTransform:NotImplemented', 'setMode is a stub (M6).');
        end

        function T = resultTable(obj)
            %RESULTTABLE Ranked identities with scores, for the GUI table.
            error('HimigTransform:NotImplemented', 'resultTable is a stub (M6).');
        end

        function renderInto(obj, axWave, axSpec, axHist)
            %RENDERINTO Draw waveform, constellation and offset histogram.
            %   Delegates to src/viz so the GUI and the paper share one set of
            %   plotting functions.
            error('HimigTransform:NotImplemented', 'renderInto is a stub (M6).');
        end
    end
end
