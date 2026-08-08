function tests = tSelfMatch
%TSELFMATCH A song must identify itself. The smoke test for the whole pipeline.
%
%   If this fails, nothing downstream is worth debugging. It is the M1 exit
%   criterion and it should stay in the suite forever, because it catches
%   almost every asymmetry between the enrolment and query paths.
%
%   Milestone: M1.  Blueprint: sections 5, 7 (M1).
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
setupPaths();
testCase.TestData.Cfg = baselineConfig();
end

function testCleanExcerptMatchesItself(testCase)
% CONTRACT: a clean 10 s excerpt of an enrolled song returns that song as
% pred1 with margin > 3, on the 5-song toy database.
testCase.assumeFail('Pending: identifyQuery not implemented (M1).');
end

function testUnenrolledSongIsNotConfidentlyMatched(testCase)
% CONTRACT: a holdout song produces a low normScore and a margin near 1.
testCase.assumeFail('Pending: identifyQuery not implemented (M1).');
end
