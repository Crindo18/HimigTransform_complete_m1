function post = queryIndex(Idx, h)
%QUERYINDEX Look up query hashes and return the matching postings.
%
%   POST = QUERYINDEX(IDX, H) returns, for every query hash in H that exists
%   in the index, every posting stored under it:
%
%       post.qIdx    [M x 1] double  which entry of H this posting came from
%       post.songID  [M x 1] uint16
%       post.t1      [M x 1] uint32  anchor frame index in the REFERENCE
%
%   M is the total number of postings, not the number of query hashes: a
%   common hash present in forty songs contributes forty rows. post.qIdx is
%   what lets ALIGNOFFSETS recover the query-side anchor time for each one.
%
%   Both backends MUST return identical postings for the same input -
%   tIndexBackendParity enforces this at M2. Identical means same rows in the
%   same order, which is why BUILDINDEXCSR sorts on three keys.
%
%   FULLY VECTORISED, deliberately. The obvious implementation is a loop over
%   query hashes that concatenates postings as it goes, and it is quadratic
%   for the same reason appending to a containers.Map value is: MATLAB
%   reallocates the growing array every iteration. A 10 s query produces
%   around 2,500 hashes and a busy one can retrieve tens of thousands of
%   postings, so this is on the path that blueprint 6.3 has to time at under
%   one second.
%
%   Milestone: M1.  Blueprint: sections 2.4, 3.5.
%
%   See also BUILDINDEX, ALIGNOFFSETS.

h = uint32(h(:));

switch lower(Idx.backend)
    case 'csr'
        post = queryCsr(Idx, h);
    case 'map'
        post = queryMap(Idx, h);
    otherwise
        error('HimigTransform:UnknownBackend', ...
            'Index backend "%s" is not recognised.', Idx.backend);
end

end

% =======================================================================
function post = queryCsr(Idx, h)

[found, loc] = ismember(h, Idx.hashKeys);

hit = find(found);

if isempty(hit)
    post = emptyPostings();
    return
end

hit    = hit(:);
k      = double(loc(hit));
starts = double(Idx.bucketPtr(k));
lens   = double(Idx.bucketPtr(k + 1)) - starts;

starts = starts(:);
lens   = lens(:);

total = sum(lens);

% Expand every (start, len) run into explicit posting indices without a loop.
% runStart(j) is where run j begins in the output, so subtracting it gives a
% 0-based offset within the run.
%
% EVERY INTERMEDIATE IS FORCED TO A COLUMN. repelem returns a ROW when its
% first argument is 1x1, because a 1x1 array is simultaneously a row and a
% column vector. The subtraction below then broadcasts into a total x total
% matrix instead of subtracting elementwise, and every downstream field comes
% back square. This is invisible for a real query - a 10 s clip retrieves
% thousands of postings across many keys, so every intermediate is a genuine
% column and the arithmetic is correct. It appears ONLY when exactly one query
% hash matches exactly one bucket, which is what a unit test does and what
% nobody notices in an integration run.
cs       = cumsum(lens);
runStart = [1; cs(1:end - 1) + 1];
offs     = (1:total)' - colvec(repelem(runStart, lens));
pIdx     = colvec(repelem(starts, lens)) + offs;

post        = struct();
post.qIdx   = colvec(repelem(hit, lens));
post.songID = colvec(Idx.songID(pIdx));
post.t1     = colvec(Idx.t1(pIdx));

end

% =======================================================================
function post = queryMap(Idx, h)
%QUERYMAP containers.Map lookup.
%
%   Returns byte-identical postings to QUERYCSR, in the same order. That is
%   what makes the backend benchmark a comparison of one system against
%   itself rather than of two different systems - see tIndexBackendParity.
%
%   The loop here is unavoidable: containers.Map has no vectorised multi-key
%   lookup, and that per-key dispatch cost IS the finding the benchmark is
%   meant to expose. Do not "optimise" it into something the CSR backend
%   would not also get; that would flatter the comparison.

keys = num2cell(h);
found = isKey(Idx.map, keys);
hit = find(found);
hit = hit(:);

if isempty(hit)
    post = emptyPostings();
    return
end

% Two passes: size the output, then fill it. Growing arrays inside the loop
% would make this quadratic and would misattribute MATLAB's reallocation cost
% to the containers.Map backend.
lens = zeros(numel(hit), 1);
vals = cell(numel(hit), 1);
for j = 1:numel(hit)
    v = Idx.map(h(hit(j)));
    vals{j} = v;
    lens(j) = size(v, 1);
end

total = sum(lens);

qIdx   = zeros(total, 1);
songID = zeros(total, 1, 'uint16');
t1     = zeros(total, 1, 'uint32');

at = 0;
for j = 1:numel(hit)
    m = lens(j);
    if m == 0
        continue
    end
    v = vals{j};
    qIdx(at + 1 : at + m)   = hit(j);
    songID(at + 1 : at + m) = uint16(v(:, 1));
    t1(at + 1 : at + m)     = uint32(v(:, 2));
    at = at + m;
end

post        = struct();
post.qIdx   = qIdx;
post.songID = songID;
post.t1     = t1;

end

% =======================================================================
function v = colvec(v)
%COLVEC Force a vector to a column, whatever orientation it arrived in.

v = v(:);

end

% =======================================================================
function post = emptyPostings()

post        = struct();
post.qIdx   = zeros(0, 1);
post.songID = zeros(0, 1, 'uint16');
post.t1     = zeros(0, 1, 'uint32');

end