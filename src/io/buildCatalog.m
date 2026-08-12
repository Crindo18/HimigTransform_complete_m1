function catalog = buildCatalog(fileList, Cfg, catalogPath)
%BUILDCATALOG Assemble the catalog table and assign songID, role and split.
%
%   CATALOG = BUILDCATALOG(FILELIST, CFG) builds the blueprint 2.2 table from
%   a scan of data/raw. CATALOG = BUILDCATALOG(FILELIST, CFG, CATALOGPATH)
%   merges against a catalog somewhere other than db/catalog.csv.
%
%   FILELIST is a struct array with fields .relPath (forward-slash, relative
%   to data/raw), .name, .repertoire and .role, as produced by INGESTLIBRARY.
%
%   Three invariants this function exists to protect:
%
%   1. songID is stable. It is the primary key of every downstream artifact -
%      fingerprint filenames, index postings, the query manifest, every
%      results row. A previous catalog is matched on sourcePath and its IDs
%      are carried over; new files take IDs from the high-water mark. Removing
%      a song retires its ID rather than freeing it, so an old results file
%      never silently re-points at a different track.
%
%   2. Human edits survive re-ingest. Filenames are a poor metadata source,
%      so title, artist and year are parsed as a starting point and then
%      overridden by whatever is already in the catalog. Fix a title once, in
%      the CSV, and s01_ingest will not undo it.
%
%   3. The split is assigned at SONG level (blueprint 8.2), and existing
%      assignments are never reshuffled. Splitting at query level leaks tuning
%      data into the reported result; silently reshuffling the split when
%      someone adds a track does the same thing more subtly, because
%      thresholds tuned on the old dev set are now being reported on songs
%      that were part of it. New songs are assigned to bring each stratum
%      toward its target dev fraction, and nothing already assigned moves.
%
%   Stratification is (role x repertoire), so dev holds a representative mix
%   rather than, by chance, all the OPM ballads. Holdout splits 50/50 per
%   blueprint 8.2 (10 of the 20 open-set songs go to dev); in-DB songs use
%   CFG.eval.devSongFrac.
%
%   Milestone: M0.  Blueprint: sections 2.2, 8.2.
%
%   See also INGESTLIBRARY, LOADCATALOG, CATALOGSCHEMA.

if nargin < 3 || isempty(catalogPath)
    catalogPath = fullfile(setupPaths(), 'db', 'catalog.csv');
end
catalogPath = char(catalogPath);

n = numel(fileList);
if n == 0
    error('HimigTransform:NoAudioFound', ...
        ['No audio files found under data/raw. See data/README.md for the ' ...
         'expected layout: data/raw/{american,opm}/ and ' ...
         'data/raw/holdout/{american,opm}/.']);
end

% Deterministic ordering, so two members scanning the same library assign the
% same IDs to the same files regardless of filesystem enumeration order.
relPaths = string({fileList.relPath}');
[relPaths, ord] = sort(relPaths);
fileList = fileList(ord);

% ---- Columns from the scan --------------------------------------------
songID      = zeros(n, 1, 'uint16');
title       = strings(n, 1);
artist      = strings(n, 1);
repertoire  = strings(n, 1);
role        = strings(n, 1);
splitStr    = strings(n, 1);
year        = zeros(n, 1, 'uint16');
procPath    = strings(n, 1);
durationSec = zeros(n, 1);
sha256      = strings(n, 1);

splitStr(:) = missing;

for i = 1:n
    repertoire(i) = string(fileList(i).repertoire);
    role(i)       = string(fileList(i).role);
    [title(i), artist(i), year(i)] = parseFileName(fileList(i).name);
end

% ---- Merge against the previous catalog --------------------------------
prior = table.empty(0, 0);
if isfile(catalogPath)
    prior = loadCatalog(Cfg, catalogPath);
end

if ~isempty(prior)
    [known, loc] = ismember(relPaths, prior.sourcePath);
    idx = find(known)';

    for i = idx
        p = prior(loc(i), :);

        songID(i) = p.songID;

        if strlength(p.title)  > 0, title(i)  = p.title;  end
        if strlength(p.artist) > 0, artist(i) = p.artist; end
        if p.year > 0,              year(i)   = p.year;   end

        if ~isundefined(p.split)
            splitStr(i) = string(p.split);
        end

        % Carried over so the processing loop can decide whether work is
        % needed; INGESTLIBRARY refreshes or clears them.
        procPath(i)    = p.procPath;
        durationSec(i) = p.durationSec;
        sha256(i)      = p.sha256;

        % repertoire and role are NOT carried over. The folder layout is
        % authoritative: moving a file from american/ to holdout/ is how you
        % change its role, and that must take effect.
        if string(p.repertoire) ~= repertoire(i) || string(p.role) ~= role(i)
            logMsg('warn', ...
                'songID %d moved: %s/%s -> %s/%s (folder layout wins).', ...
                p.songID, string(p.role), string(p.repertoire), role(i), repertoire(i));
        end
    end

    gone = ~ismember(prior.sourcePath, relPaths);
    if any(gone)
        logMsg('warn', ...
            ['%d song(s) in the catalog no longer have a source file; their rows ' ...
             'are dropped and their songIDs are retired, not reused.'], nnz(gone));
        for k = find(gone)'
            logMsg('warn', '  retired songID %d: %s', prior.songID(k), prior.sourcePath(k));
        end
    end
end

% ---- New songIDs from the high-water mark ------------------------------
nextID = 1;
if ~isempty(prior)
    nextID = double(max(prior.songID)) + 1;
end

isNew = songID == 0;
if any(isNew)
    newIdx = find(isNew);
    lastID = nextID + numel(newIdx) - 1;
    if lastID > double(intmax('uint16'))
        error('HimigTransform:SongIDOverflow', ...
            'songID is uint16 and would exceed %d. Widen the schema if the library really is this large.', ...
            intmax('uint16'));
    end
    songID(newIdx) = uint16(nextID:lastID);
    logMsg('info', 'Assigned %d new songID(s), %d..%d.', numel(newIdx), nextID, lastID);
end

% ---- Split assignment (song level, additive, seeded) --------------------
rng(Cfg.seed, 'twister');

strata = { ...
    'db',      'american'; ...
    'db',      'opm';      ...
    'holdout', 'american'; ...
    'holdout', 'opm'};

for s = 1:size(strata, 1)
    sel = find(role == strata{s, 1} & repertoire == strata{s, 2});
    if isempty(sel)
        continue
    end

    if strcmp(strata{s, 1}, 'holdout')
        frac = 0.5;                    % blueprint 8.2: 10 of the 20 holdout songs
    else
        frac = Cfg.eval.devSongFrac;
    end

    nDev    = round(frac * numel(sel));
    already = ~ismissing(splitStr(sel));
    haveDev = nnz(splitStr(sel) == "dev");

    unassigned = sel(~already);
    if isempty(unassigned)
        continue
    end

    % Sort by songID before permuting: the permutation must depend only on the
    % seed and the stratum, not on scan order.
    [~, o]     = sort(songID(unassigned));
    unassigned = unassigned(o);

    need = max(0, nDev - haveDev);
    perm = randperm(numel(unassigned));
    pick = unassigned(perm(1:min(need, numel(unassigned))));

    splitStr(unassigned) = "test";
    splitStr(pick)       = "dev";
end

% ---- Assemble ----------------------------------------------------------
S = catalogSchema();

catalog = table( ...
    songID, ...
    title, ...
    artist, ...
    setcats(categorical(repertoire), {'american', 'opm'}), ...
    setcats(categorical(role),       {'db', 'holdout'}), ...
    setcats(categorical(splitStr),   {'dev', 'test'}), ...
    year, ...
    relPaths, ...
    procPath, ...
    durationSec, ...
    sha256, ...
    'VariableNames', {S.name});

catalog = sortrows(catalog, 'songID');

if numel(unique(catalog.songID)) ~= height(catalog)
    error('HimigTransform:DuplicateSongID', 'songID collision while building the catalog.');
end

end

% =======================================================================
function [titleStr, artistStr, yearVal] = parseFileName(name)
%PARSEFILENAME Best-effort metadata from "Artist - Title (1998).mp3".
%
%   Deliberately conservative. Anything it gets wrong is fixed once by editing
%   catalog.csv, and BUILDCATALOG will not overwrite the fix.

[~, base] = fileparts(char(name));
base = strtrim(base);

% Leading track number, but only when followed by punctuation ("01. ", "03 - ").
% A bare "99 Luftballons" is left alone - stripping on whitespace alone eats
% real titles.
base = strtrim(regexprep(base, '^\s*\d{1,3}\s*[-._)\]]\s*', ''));

yearVal = uint16(0);
tok = regexp(base, '[\(\[]\s*((?:19|20)\d{2})\s*[\)\]]', 'tokens', 'once');
if ~isempty(tok)
    yearVal = uint16(str2double(tok{1}));
    base    = strtrim(regexprep(base, '[\(\[]\s*(?:19|20)\d{2}\s*[\)\]]', ''));
end

k = strfind(base, ' - ');
if ~isempty(k)
    artistStr = string(strtrim(base(1:k(1) - 1)));
    titleStr  = string(strtrim(base(k(1) + 3:end)));
else
    artistStr = "unknown";
    titleStr  = string(base);
end

if strlength(titleStr) == 0
    titleStr = "untitled";
end
if strlength(artistStr) == 0
    artistStr = "unknown";
end

end