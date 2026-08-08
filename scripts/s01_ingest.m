%S01_INGEST  Convert data/raw audio to 8 kHz mono and build db/catalog.csv.
%
%   Run once after placing audio in data/raw/{american,opm,holdout}.
%   Idempotent: already-processed, checksum-matching files are skipped.
%
%   Exit check: every processed file is 8 kHz mono; catalog.csv has 120 rows
%   with unique songID and a populated sha256 column.
%
%   Milestone: M0.  Blueprint: section 7.
%
%   STATUS: stub. Run order is s01 -> s08; each script is idempotent.
%
%   Usage:
%       setupPaths;
%       s01_ingest

setupPaths;
rng(defaultConfig().seed, 'twister');

error('HimigTransform:NotImplemented', ...
    's01_ingest is a stub (Milestone M0). See docs/designNotes.md.');
