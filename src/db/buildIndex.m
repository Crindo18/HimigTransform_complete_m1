function Idx = buildIndex(fpCellArray, songIDs, Cfg)
%BUILDINDEX Build the hash index. Dispatches on Cfg.index.backend.
%
%   IDX = BUILDINDEX(FPCELLARRAY, SONGIDS, CFG) builds the index using the
%   backend named by Cfg.index.backend: 'csr' (default, fast) or 'map'
%   (containers.Map, proposal-faithful).
%
%   A thin interface over two interchangeable backends, so the storage
%   decision stays reversible and - more importantly - measurable. Blueprint
%   D3 is explicit that containers.Map is written into the proposal as though
%   it were a design requirement when it is an implementation detail with a
%   real scalability cost at 100 songs. Keeping both behind one interface
%   turns that from a deviation you have to defend into a benchmark table you
%   get to present.
%
%   Both backends must return identical postings for identical input.
%   tIndexBackendParity enforces it at M2.
%
%   Milestone: M1 (dispatcher and 'csr').  'map' arrives at M2.
%   Blueprint: sections 0 (D3), 2.4.
%
%   See also BUILDINDEXCSR, BUILDINDEXMAP, QUERYINDEX.

if nargin < 3 || isempty(Cfg)
    Cfg = defaultConfig();
end

switch lower(Cfg.index.backend)
    case 'csr'
        Idx = buildIndexCsr(fpCellArray, songIDs, Cfg);
    case 'map'
        Idx = buildIndexMap(fpCellArray, songIDs, Cfg);
    otherwise
        error('HimigTransform:UnknownBackend', ...
            'Cfg.index.backend = "%s" is not recognised. Use ''csr'' or ''map''.', ...
            Cfg.index.backend);
end

end