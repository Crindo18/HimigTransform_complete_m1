function hash = sha256File(filePath)
%SHA256FILE SHA-256 checksum of a file, as a lowercase hex char row vector.
%
%   HASH = SHA256FILE(FILEPATH) returns the 64-character hexadecimal SHA-256
%   digest of the file's bytes, lowercase, as a CHAR row vector. It is a
%   checksum of the file itself, not of the audio it decodes to: two WAVs
%   holding identical samples but written by different MATLAB versions can
%   differ in their header and will hash differently.
%
%   WHAT THIS IS FOR. The repository never carries audio (blueprint 4.2), so
%   there is nothing in Git that proves five people are working on the same
%   library. db/catalog.csv carries the checksums instead: it is small, it is
%   text, it merges, and re-running s01_ingest re-hashes every processed file
%   and reports any row that has drifted. That turns "my results look
%   different from yours" from a week of debugging into one line of output.
%   It is also what makes the ingest skip logic safe - a processed file is
%   only skipped when its bytes still match what the catalog recorded.
%
%   STREAMED, NOT SLURPED. The file is read in 1 MiB chunks and fed to the
%   digest incrementally. A 300 s DEMAND recording is only about 5 MB, but the
%   original 44.1 kHz stereo sources are tens of megabytes each and there are
%   120 of them; reading each one whole into memory to hash it would work and
%   would also be the kind of thing that falls over on a lab machine at the
%   worst moment.
%
%   JAVA. java.security.MessageDigest is part of the JRE that ships with
%   MATLAB, so this needs no toolbox and no file-exchange dependency, which is
%   the constraint blueprint 1.3 sets. It does need the JVM, so MATLAB started
%   with -nojvm cannot run it; that case is detected and reported rather than
%   producing a confusing Java error.
%
%   Milestone: M0.  Blueprint: sections 2.2, 4.2.
%
%   See also BUILDCATALOG, INGESTLIBRARY, PREPARENOISEBANK.

filePath = char(filePath);

if ~isfile(filePath)
    error('HimigTransform:FileNotFound', ...
        'No such file to checksum: %s', filePath);
end

if ~usejava('jvm')
    error('HimigTransform:NoJvm', ...
        ['sha256File needs the JVM (java.security.MessageDigest) and this MATLAB was ' ...
         'started with -nojvm.\nRestart without that flag. If that is impossible, ' ...
         'ingestLibrary can be run with ''Verify'', false, but the catalog will then ' ...
         'carry no checksums and the group loses its only guarantee of identical audio.']);
end

CHUNK_BYTES = 2 ^ 20;   % 1 MiB per read

fid = fopen(filePath, 'r');
if fid < 0
    error('HimigTransform:FileOpenFailed', ...
        'Could not open %s for reading (permissions, or the file is locked by another program).', ...
        filePath);
end
closeFile = onCleanup(@() fclose(fid));   %#ok<NASGU>  closes on error too

md = java.security.MessageDigest.getInstance('SHA-256');

while true
    buf = fread(fid, CHUNK_BYTES, '*uint8');
    if isempty(buf)
        break
    end
    % The three-argument update() is used deliberately. MATLAB resolves Java
    % overloads by argument shape, and a one-element int8 array is ambiguous
    % between update(byte) and update(byte[]) - which would silently hash one
    % byte of a chunk. Naming the offset and length picks the array overload
    % unambiguously, whatever the final chunk's size turns out to be.
    md.update(typecast(buf, 'int8'), int32(0), int32(numel(buf)));
end

% digest() hands back Java signed bytes; reinterpret them as unsigned before
% formatting, or every byte above 0x7F prints as a negative number.
hash = sprintf('%02x', typecast(md.digest(), 'uint8'));

if numel(hash) ~= 64
    error('HimigTransform:BadDigest', ...
        'SHA-256 digest came back %d characters instead of 64 for %s.', ...
        numel(hash), filePath);
end

end