function projRoot = setupPaths()
%SETUPPATHS Put HimigTransform on the MATLAB path and ensure working folders exist.
%
%   PROJROOT = SETUPPATHS() adds config/, src/** , scripts/ and tests/ to the
%   MATLAB search path and creates the gitignored working folders (db/,
%   results/raw, data/processed, data/noise) if they are missing. It returns
%   the absolute path to the project root.
%
%   Run this once per MATLAB session, from anywhere:
%       run('/path/to/HimigTransform/setupPaths.m')
%   or, if you have already cd'd into the project:
%       setupPaths;
%
%   The function is idempotent - calling it repeatedly is harmless.
%
%   See also DEFAULTCONFIG, RUNTESTS.
%
%   Blueprint: section 4.

projRoot = fileparts(mfilename('fullpath'));

% ---- Path -------------------------------------------------------------
% genpath skips folders beginning with '.', '@' or '+', so .git is excluded.
pathFolders = { ...
    projRoot, ...
    fullfile(projRoot, 'config'), ...
    genpath(fullfile(projRoot, 'src')), ...
    fullfile(projRoot, 'scripts'), ...
    fullfile(projRoot, 'tests')};

for k = 1:numel(pathFolders)
    p = pathFolders{k};
    if ~isempty(p)
        addpath(p);
    end
end

% ---- Working folders (gitignored, so they may not exist on a fresh clone)
workFolders = { ...
    fullfile(projRoot, 'data', 'raw', 'american'), ...
    fullfile(projRoot, 'data', 'raw', 'opm'), ...
    fullfile(projRoot, 'data', 'raw', 'holdout'), ...
    fullfile(projRoot, 'data', 'processed', 'mono8k'), ...
    fullfile(projRoot, 'data', 'noise'), ...
    fullfile(projRoot, 'db', 'fingerprints'), ...
    fullfile(projRoot, 'results', 'raw'), ...
    fullfile(projRoot, 'results', 'figures'), ...
    fullfile(projRoot, 'results', 'tables')};

for k = 1:numel(workFolders)
    if ~isfolder(workFolders{k})
        mkdir(workFolders{k});
    end
end

if nargout == 0
    fprintf('HimigTransform ready.  Root: %s\n', projRoot);
    fprintf('MATLAB %s.  Next: runTests\n', version('-release'));
    clear projRoot;
end

end
