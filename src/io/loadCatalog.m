function catalog = loadCatalog(Cfg, catalogPath)
%LOADCATALOG Read db/catalog.csv into a typed table.
%
%   CATALOG = LOADCATALOG() reads db/catalog.csv.
%   CATALOG = LOADCATALOG(CFG, CATALOGPATH) reads a catalog from elsewhere -
%   used by the toy-set workflow (s00_makeToySet), which keeps its own
%   catalog so the real one is never polluted with synthetic tracks.
%
%   CSV is a typeless format: WRITETABLE flattens categoricals to text and
%   integers to decimal, and READTABLE guesses on the way back. Guessing goes
%   wrong in ways that are hard to see - an all-empty sha256 column arrives as
%   double NaN, a repertoire column arrives as cellstr and then GROUPSUMMARY
%   silently orders groups differently from run to run. This function restores
%   the declared types from CATALOGSCHEMA every time, so downstream grouping,
%   joining and plotting behave identically no matter who wrote the file.
%
%   Categoricals are given their full category list even when the data does
%   not use every level yet, so an empty holdout set still produces a 'holdout'
%   group rather than vanishing from a summary table.
%
%   Milestone: M0.  Blueprint: section 2.2.
%
%   See also BUILDCATALOG, CATALOGSCHEMA, INGESTLIBRARY.

if nargin < 1 || isempty(Cfg)
    Cfg = defaultConfig(); %#ok<NASGU>  reserved for future schema versioning
end

if nargin < 2 || isempty(catalogPath)
    catalogPath = fullfile(setupPaths(), 'db', 'catalog.csv');
end
catalogPath = char(catalogPath);

if ~isfile(catalogPath)
    error('HimigTransform:NoCatalog', ...
        'No catalog at %s.\nRun s01_ingest first (see data/README.md).', catalogPath);
end

S    = catalogSchema();
opts = detectImportOptions(catalogPath, 'TextType', 'string');

% Force every known column to its declared import type; leave anything the
% group has added by hand alone rather than dropping it.
for k = 1:numel(S)
    if ismember(S(k).name, opts.VariableNames)
        opts = setvartype(opts, S(k).name, S(k).import);
    end
end
strCols = opts.VariableNames(strcmp(opts.VariableTypes, 'string'));
if ~isempty(strCols)
    % Empty CSV cells become "" rather than <missing>, so STRLENGTH and
    % STRCMP behave predictably on a half-filled catalog.
    opts = setvaropts(opts, strCols, 'FillValue', "");
end

catalog = readtable(catalogPath, opts);

missingCols = setdiff({S.name}, catalog.Properties.VariableNames);
if ~isempty(missingCols)
    error('HimigTransform:BadCatalog', ...
        'catalog.csv is missing required column(s): %s\nDelete it and re-run s01_ingest.', ...
        strjoin(missingCols, ', '));
end

% ---- Final types -------------------------------------------------------
for k = 1:numel(S)
    v = catalog.(S(k).name);
    switch S(k).final
        case 'uint16'
            v(isnan(v)) = 0;
            catalog.(S(k).name) = uint16(v);
        case 'categorical'
            v = setcats(categorical(v), S(k).cats);
            if any(isundefined(v))
                logMsg('warn', ...
                    'catalog.csv: column %s has %d value(s) outside {%s}; they are now <undefined>.', ...
                    S(k).name, nnz(isundefined(v)), strjoin(S(k).cats, ', '));
            end
            catalog.(S(k).name) = v;
        case 'string'
            v(ismissing(v)) = "";
            catalog.(S(k).name) = v;
        otherwise
            catalog.(S(k).name) = double(v);
    end
end

% Canonical column order, then sorted by the primary key. Extra columns the
% group has added by hand are kept, after the declared ones.
extraCols = setdiff(catalog.Properties.VariableNames, {S.name}, 'stable');
extraCols = reshape(extraCols, 1, []);
catalog   = catalog(:, [{S.name}, extraCols]);
catalog   = sortrows(catalog, 'songID');

if numel(unique(catalog.songID)) ~= height(catalog)
    error('HimigTransform:DuplicateSongID', ...
        'catalog.csv has duplicate songID values. songID is the primary key and must be unique.');
end

end