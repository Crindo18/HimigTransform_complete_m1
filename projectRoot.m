function root = projectRoot()
%PROJECTROOT Absolute path to the HimigTransform root. Cheap and memoised.
%
%   ROOT = PROJECTROOT() returns the project root without touching the MATLAB
%   search path and without creating any folders.
%
%   USE THIS, NOT SETUPPATHS(), ANYWHERE ON A HOT PATH.
%
%   SETUPPATHS does real work on every call: ADDPATH over GENPATH of src/,
%   plus nine ISFOLDER checks and any MKDIR they trigger. ADDPATH also
%   invalidates MATLAB's function lookup cache, so the cost is not just the
%   call - it is every function resolution afterwards.
%
%   That is fine once per session, which is what it was written for. It is not
%   fine per query. SYNTHESIZEQUERY reached it twice per call (once directly
%   for the noise path, once through RESOLVEPROCPATH), so a 17,280-query
%   evaluation made roughly 35,000 ADDPATH calls and spent almost all of its
%   wall clock there: the M3 subset run measured 0.373 s per query against a
%   median match time of 0.0069 s.
%
%   The result is cached in a PERSISTENT after the first call. The root cannot
%   move during a session - it is derived from this file's own location - so
%   there is nothing to invalidate.
%
%   Milestone: M3.  Blueprint: section 6.3.
%
%   See also SETUPPATHS.

persistent cachedRoot

if isempty(cachedRoot)
    cachedRoot = fileparts(mfilename('fullpath'));
end

root = cachedRoot;

end
