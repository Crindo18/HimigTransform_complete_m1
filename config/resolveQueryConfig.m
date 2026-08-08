function Cfg = resolveQueryConfig(Cfg, durationSec)
%RESOLVEQUERYCONFIG Resolve query-side hashing parameters for one clip.
%
%   CFGQ = RESOLVEQUERYCONFIG(CFG, DURATIONSEC) returns a copy of CFG whose
%   Cfg.hash.fanout and Cfg.hash.dtMax have been set to the values the QUERY
%   side should use for a clip of DURATIONSEC seconds. Enrolment always uses
%   the unresolved CFG.
%
%   Resolution order (blueprint 2.1, 3.4):
%       1. shortQuery.enable AND durationSec < shortQuery.thresholdSec
%              -> Cfg.shortQuery.fanout / Cfg.shortQuery.dtMax
%       2. otherwise, if Cfg.hash.queryFanout / queryDtMax are non-empty
%              -> those values
%       3. otherwise
%              -> inherit Cfg.hash.fanout / Cfg.hash.dtMax
%
%   Cfg.tag is deliberately NOT changed: the tag identifies the index, and the
%   query side does not build one.
%
%   GUARD. A query dtMax larger than the enrolment dtMax produces hashes that
%   can never collide with anything in the index - a silent zero-match bug that
%   is very hard to diagnose from the outside. This function clamps and warns.
%
%   See also DEFAULTCONFIG, ENHANCEDCONFIG, MAKEHASHES.
%
%   Blueprint: sections 3.4, 3.5.

enrolDtMax = Cfg.hash.dtMax;

isShort = Cfg.shortQuery.enable && durationSec < Cfg.shortQuery.thresholdSec;

if isShort
    fanout = Cfg.shortQuery.fanout;
    dtMax  = Cfg.shortQuery.dtMax;
else
    if isempty(Cfg.hash.queryFanout)
        fanout = Cfg.hash.fanout;
    else
        fanout = Cfg.hash.queryFanout;
    end
    if isempty(Cfg.hash.queryDtMax)
        dtMax = Cfg.hash.dtMax;
    else
        dtMax = Cfg.hash.queryDtMax;
    end
end

if dtMax > enrolDtMax
    warning('HimigTransform:QueryZoneTooWide', ...
        ['Query dtMax (%d) exceeds enrolment dtMax (%d); hashes beyond the ' ...
         'enrolment target zone can never match. Clamping to %d.'], ...
        dtMax, enrolDtMax, enrolDtMax);
    dtMax = enrolDtMax;
end

if fanout > Cfg.hash.fanout
    warning('HimigTransform:QueryFanoutTooWide', ...
        ['Query fan-out (%d) exceeds enrolment fan-out (%d); the extra pairs ' ...
         'cost time and cannot match. Check that the index was built from a ' ...
         'config with the wider fan-out.'], fanout, Cfg.hash.fanout);
end

Cfg.hash.fanout = fanout;
Cfg.hash.dtMax  = dtMax;

end
