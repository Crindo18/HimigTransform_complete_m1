function results = runTests(varargin)
%RUNTESTS Run the HimigTransform test suite.
%
%   RESULTS = RUNTESTS() runs every test file in tests/ and prints a summary.
%   RESULTS = RUNTESTS('tSTFT') runs a single named test file.
%
%   Green RUNTESTS is the merge gate. No branch lands on main without it.
%
%   Tests for unimplemented modules call assumeFail, which marks them
%   INCOMPLETE rather than FAILED - so the suite is green from M0 onward and a
%   red result always means something actually broke, not something that has
%   not been written yet. As each module is implemented, delete its assumeFail
%   line and the test becomes live.
%
%   The suite is assembled with fromFile rather than fromFolder because the
%   blueprint names test files tSTFT, tHashPack and so on, which do not match
%   MATLAB's default "starts or ends with test" discovery convention.
%
%   See also SETUPPATHS.
%
%   Blueprint: sections 5, 7 (M0).

projRoot = setupPaths();
testDir  = fullfile(projRoot, 'tests');

if nargin > 0
    names = varargin;
else
    listing = dir(fullfile(testDir, 't*.m'));
    names = {listing.name};
end

import matlab.unittest.TestSuite
import matlab.unittest.TestRunner

suite = TestSuite.empty(1, 0);
for k = 1:numel(names)
    [~, base] = fileparts(names{k});
    if strcmp(base, 'runTests')
        continue
    end
    thisFile = fullfile(testDir, [base '.m']);
    if ~isfile(thisFile)
        warning('HimigTransform:MissingTest', 'No such test file: %s', thisFile);
        continue
    end
    try
        suite = [suite, TestSuite.fromFile(thisFile)]; %#ok<AGROW>
    catch err
        warning('HimigTransform:BadTestFile', ...
            'Could not load %s: %s', base, err.message);
    end
end

if isempty(suite)
    error('HimigTransform:NoTests', 'No test files found in %s.', testDir);
end

runner  = TestRunner.withTextOutput();
results = runner.run(suite);

nPass = nnz([results.Passed]);
nFail = nnz([results.Failed]);
nInc  = nnz([results.Incomplete]);

fprintf('\n----------------------------------------------------------\n');
fprintf('HimigTransform: %d passed, %d failed, %d pending (unimplemented)\n', ...
    nPass, nFail, nInc);
fprintf('Total time: %.2f s\n', sum([results.Duration]));
if nFail > 0
    fprintf('MERGE GATE: BLOCKED - fix the failures above.\n');
else
    fprintf('MERGE GATE: OPEN\n');
end
fprintf('----------------------------------------------------------\n');

if nargout == 0
    clear results;
end

end
