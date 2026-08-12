function S = catalogSchema()
%CATALOGSCHEMA Declared column types for db/catalog.csv (blueprint 2.2).
%
%   S = CATALOGSCHEMA() returns a struct array, one element per column, in the
%   canonical column order. Fields:
%
%       name          column name in the table and in the CSV header
%       import        type handed to SETVARTYPE when READTABLE parses the CSV
%       final         type the column is coerced to after import:
%                       'uint16' | 'categorical' | 'string' | 'double'
%       cats          allowed categories ({} unless final is 'categorical')
%       description   what the column means - this file is the data dictionary
%
%   WHY A SCHEMA FILE AT ALL. CSV is a typeless format. WRITETABLE flattens
%   categoricals to bare text and integers to decimal; READTABLE then guesses
%   on the way back, and it guesses differently depending on what the data
%   happens to contain. An all-empty sha256 column comes back as double NaN.
%   A repertoire column comes back as cellstr, and GROUPSUMMARY then orders
%   groups by whatever it found rather than by a declared category list, so
%   two members produce differently-ordered result tables from identical data.
%   Declaring the types in one place and re-applying them on every read makes
%   the catalog behave like a typed table even though it lives in a CSV.
%
%   The import type and the final type differ on purpose for the integer
%   columns. They are imported as double so an empty cell arrives as NaN,
%   which LOADCATALOG maps to 0; importing straight to uint16 would silently
%   turn an empty cell into 0 with no way to tell the two apart.
%
%   CHANGING THIS FILE IS A SCHEMA MIGRATION. songID is the primary key of
%   every downstream artifact - fingerprint filenames, index postings, the
%   query manifest, every results row. Adding a column is safe (LOADCATALOG
%   preserves columns it does not know about). Renaming, reordering or
%   retyping one is not: delete db/catalog.csv and re-run s01_ingest, and
%   accept that every songID may change.
%
%   Milestone: M0.  Blueprint: section 2.2.
%
%   See also BUILDCATALOG, LOADCATALOG, INGESTLIBRARY.

%   name          import      final          categories                description
spec = { ...
    'songID',     'double',   'uint16',      {},                       'Primary key, 1..N. Never reused, never renumbered.'
    'title',      'string',   'string',      {},                       'Track title. Parsed from the filename, then hand-editable.'
    'artist',     'string',   'string',      {},                       'Performer. "unknown" when the filename carries no artist.'
    'repertoire', 'string',   'categorical', {'american', 'opm'},      'Which repertoire the track belongs to. Read from the folder layout.'
    'role',       'string',   'categorical', {'db', 'holdout'},        'db = one of the 100 enrolled songs; holdout = one of the 20 open-set songs.'
    'split',      'string',   'categorical', {'dev', 'test'},          'Song-level tuning split (blueprint 8.2). Never assigned per query.'
    'year',       'double',   'uint16',      {},                       'Release year, 0 when unknown. Supports the "several decades" claim.'
    'sourcePath', 'string',   'string',      {},                       'Original file, forward-slash relative to data/raw/.'
    'procPath',   'string',   'string',      {},                       'Processed 8 kHz mono WAV, relative to data/processed/.'
    'durationSec','double',   'double',      {},                       'Duration of the PROCESSED file, in seconds.'
    'sha256',     'string',   'string',      {},                       'Checksum of the processed file. The reproducibility anchor.'
    };

nCol = size(spec, 1);

% Built by indexed assignment rather than by STRUCT(): passing a cell to
% STRUCT makes a struct array of the cell's size, which is not what is wanted
% for the empty-category entries.
S = struct('name', {}, 'import', {}, 'final', {}, 'cats', {}, 'description', {});

for k = 1:nCol
    S(k).name        = spec{k, 1};
    S(k).import      = spec{k, 2};
    S(k).final       = spec{k, 3};
    S(k).cats        = spec{k, 4};
    S(k).description = spec{k, 5};
end

S = reshape(S, 1, nCol);

end