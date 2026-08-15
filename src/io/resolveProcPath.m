function absPath = resolveProcPath(procPath, procRoot)
%RESOLVEPROCPATH Turn a catalog procPath into an absolute file path.
%
%   ABSPATH = RESOLVEPROCPATH(PROCPATH) resolves one of the catalog's
%   procPath values (for example "mono8k/song_0001.wav") against the project's
%   processed-audio root, normalising the separators for the current platform.
%
%   ABSPATH = RESOLVEPROCPATH(PROCPATH, PROCROOT) resolves against PROCROOT
%   instead. ENROLLDATABASE passes its own root through so the toy workflow
%   can point at a different tree.
%
%   PROCPATH may be char, string or a string array; the return type matches
%   (char in, char out; string array in, string array out).
%
%   WHY THIS EXISTS AS A FUNCTION. catalog.csv stores procPath RELATIVE to
%   data/processed and with forward slashes, so that the same catalog works on
%   every group member's machine and the checksums in it mean something. That
%   makes every consumer responsible for two things: joining the root on, and
%   swapping the separator on Windows. ENROLLDATABASE did both correctly and
%   the M3 evaluation path did neither, so BUILDQUERYMANIFEST died on the
%   first song with "No such audio file: mono8k/song_0001.wav" - a path that
%   only resolves if the current folder happens to be data/processed.
%
%   One helper, called from every consumer, is the fix. If the layout ever
%   changes, it changes here and nowhere else.
%
%   Milestone: M3.  Blueprint: section(s) 2.2, 4.
%
%   See also LOADCATALOG, ENROLLDATABASE, PICKEXCERPTSTART, SYNTHESIZEQUERY.

if nargin < 2 || isempty(procRoot)
    procRoot = fullfile(setupPaths(), 'data', 'processed');
end
procRoot = char(procRoot);

wasChar = ischar(procPath);
p       = string(procPath);

absPath = strings(size(p));
for k = 1:numel(p)
    rel = strrep(char(p(k)), '/', filesep);
    rel = strrep(rel, '\', filesep);
    absPath(k) = string(fullfile(procRoot, rel));
end

if wasChar || isscalar(absPath)
    absPath = char(absPath(1));
end

end
