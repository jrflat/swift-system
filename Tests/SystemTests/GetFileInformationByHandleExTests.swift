/*
 This source file is part of the Swift System open source project

 Copyright (c) 2026 Apple Inc. and the Swift System project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
*/

#if os(Windows)

import Testing

#if SYSTEM_PACKAGE
@testable import SystemPackage
#else
@testable import System
#endif

import WinSDK
import ucrt

@Suite("GetFileInformationByHandleEx")
private struct GetFileInformationByHandleExTests {

  @available(System 99, *)
  private func withTemporaryFile(
    basename: FilePath.Component,
    leaf: String = "test.txt",
    contents: String = "Hello, world!",
    _ body: (FileDescriptor, FilePath) throws -> Void
  ) throws {
    try withTemporaryFilePath(basename: basename) { dir in
      let path = dir.appending(leaf)
      let fd = try FileDescriptor.open(
        path, .readWrite,
        options: [.create, .truncate],
        permissions: .ownerReadWrite)
      defer { try? fd.close() }
      try fd.writeAll(contents.utf8)
      try body(fd, path)
    }
  }

  @available(System 99, *)
  private func createFile(
    at path: FilePath, contents: String = "Hello, world!"
  ) throws {
    let fd = try FileDescriptor.open(
      path, .readWrite,
      options: [.create, .truncate],
      permissions: .ownerReadWrite)
    defer { try? fd.close() }
    try fd.writeAll(contents.utf8)
  }

  /// Opens a descriptor for a directory and passes it to `body`.
  ///
  /// `FileDescriptor.open` cannot do this on Windows: `CreateFileW` needs
  /// `FILE_FLAG_BACKUP_SEMANTICS` to open a directory and `OpenOptions` has no
  /// way to ask for it, since `OpenOptions.directory` is `#if !os(Windows)`.
  /// The handle is opened directly until that gap is filled.
  @available(System 99, *)
  private func withDirectoryDescriptor(
    at path: FilePath,
    _ body: (FileDescriptor) throws -> Void
  ) throws {
    let handle: HANDLE? = path.withPlatformString { wide in
      // Qualified with `WinSDK.`: the package's own overlay declares DWORD
      // versions of these names, and `@testable import` makes both visible.
      CreateFileW(
        wide,
        DWORD(WinSDK.GENERIC_READ),
        DWORD(WinSDK.FILE_SHARE_READ)
          | DWORD(WinSDK.FILE_SHARE_WRITE)
          | DWORD(WinSDK.FILE_SHARE_DELETE),
        nil,
        DWORD(WinSDK.OPEN_EXISTING),
        DWORD(WinSDK.FILE_FLAG_BACKUP_SEMANTICS),
        nil)
    }
    let raw = intptr_t(bitPattern: handle)
    try #require(raw != -1, "could not open directory \(path)")

    let descriptor = FileDescriptor(
      rawValue: _open_osfhandle(raw, ucrt._O_RDONLY))
    guard descriptor.rawValue >= 0 else {
      CloseHandle(handle)
      Issue.record("could not wrap directory handle for \(path)")
      return
    }
    defer { try? descriptor.close() }
    try body(descriptor)
  }

  /// Creates an alternate data stream on `path`, so a stream listing has more
  /// than one record for the chain walk to cross.
  @available(System 99, *)
  private func createAlternateDataStream(
    at path: FilePath, named name: String, contents: String
  ) throws {
    let streamPath = path.string + ":" + name
    let handle: HANDLE? = streamPath.withCString(encodedAs: UTF16.self) { wide in
      CreateFileW(
        wide,
        DWORD(WinSDK.GENERIC_WRITE),
        DWORD(WinSDK.FILE_SHARE_READ),
        nil,
        DWORD(WinSDK.CREATE_ALWAYS),
        0,
        nil)
    }
    try #require(
      intptr_t(bitPattern: handle) != -1,
      "could not create stream \(streamPath)")
    defer { CloseHandle(handle) }

    let bytes = Array(contents.utf8)
    var written: DWORD = 0
    bytes.withUnsafeBytes { raw in
      // `withUnsafeBytes` rather than `withUnsafeBufferPointer`: its
      // `baseAddress` is already the `UnsafeRawPointer?` that `LPCVOID` wants.
      _ = WriteFile(handle, raw.baseAddress, DWORD(raw.count), &written, nil)
    }
    #expect(written == DWORD(bytes.count))
  }

  @available(System 99, *)
  @Test func standardInfo() async throws {
    let contents = "Hello, world!"
    try withTemporaryFile(basename: "standardInfo", contents: contents) { fd, _ in
      let info = try fd.fileInformation(FileStandardInfo.self)
      #expect(info.endOfFile == Int64(contents.utf8.count))
      #expect(info.linkCount == 1)
      #expect(!info.isDirectory)
      #expect(!info.isDeletePending)
      #expect(info.allocationSize >= info.endOfFile)
    }
  }

  @available(System 99, *)
  @Test func basicInfo() async throws {
    try withTemporaryFile(basename: "basicInfo") { fd, _ in
      let info = try fd.fileInformation(FileBasicInfo.self)
      // A regular file must not carry the directory attribute.
      #expect(!info.attributes.contains(.directory))
      // Timestamps are non-zero for a just-created file.
      #expect(info.creationTime.rawValue > 0)
      #expect(info.lastWriteTime.rawValue > 0)
      // Round-trip the raw timestamp through LARGE_INTEGER.
      #expect(info.creationTime.largeInteger.QuadPart == info.creationTime.rawValue)
      // A just-created file postdates the Unix epoch.
      #expect(info.creationTime.secondsSinceUnixEpoch > 0)
    }
  }

  @available(System 99, *)
  @Test func attributeTagInfo() async throws {
    try withTemporaryFile(basename: "attrTagInfo") { fd, _ in
      let info = try fd.fileInformation(FileAttributeTagInfo.self)
      #expect(!info.attributes.contains(.directory))
      // Not a reparse point, so there is no tag to report.
      #expect(info.reparseTag == nil)
    }
  }

  @available(System 99, *)
  @Test func idInfo() async throws {
    try withTemporaryFile(basename: "idInfo") { fd, _ in
      let a = try fd.fileInformation(FileIDInfo.self)
      let b = try fd.fileInformation(FileIDInfo.self)
      // Two reads of the same handle yield the same identity.
      #expect(a.volumeSerialNumber == b.volumeSerialNumber)
      #expect(a.fileID == b.fileID)
      #expect(a.fileID.description.count == 32)
    }
  }

  @available(System 99, *)
  @Test func storageAndAlignmentInfo() async throws {
    try withTemporaryFile(basename: "storageInfo") { fd, _ in
      let storage = try fd.fileInformation(FileStorageInfo.self)
      #expect(storage.logicalBytesPerSector > 0)

      let alignment = try fd.fileInformation(FileAlignmentInfo.self)
      // AlignmentRequirement is a mask (one less than a power of two), so it's
      // fine for it to be zero (no requirement).
      #expect((alignment.alignmentRequirement & (alignment.alignmentRequirement + 1)) == 0)
      #expect(alignment.alignment == Int(alignment.alignmentRequirement) + 1)
    }
  }

  @available(System 99, *)
  @Test func compressionInfo() async throws {
    let contents = "Hello, world!"
    try withTemporaryFile(basename: "compressionInfo", contents: contents) { fd, _ in
      let info = try fd.fileInformation(FileCompressionInfo.self)
      // Files are not compressed by default, and NTFS only implements LZNT1.
      #expect(
        info.compressionFormat == CompressionFormat.none
          || info.compressionFormat == .lznt1)
      #expect(info.compressedFileSize >= 0)
    }
  }

  @available(System 99, *)
  @Test func remoteProtocolInfoOnLocalFileFails() async throws {
    try withTemporaryFile(basename: "remoteProtocol") { fd, _ in
      // The class only applies to remote files; a local file is rejected.
      #expect(throws: (any Error).self) {
        try fd.fileInformation(FileRemoteProtocolInfo.self)
      }
    }
  }

  @available(System 99, *)
  @Test func caseSensitiveInfoOnFileFails() async throws {
    try withTemporaryFile(basename: "caseSensitive") { fd, _ in
      // The class describes a directory; a file handle is rejected.
      #expect(throws: (any Error).self) {
        try fd.fileInformation(FileCaseSensitiveInfo.self)
      }
    }
  }

  @available(System 99, *)
  @Test func fileName() async throws {
    try withTemporaryFile(basename: "fileName", leaf: "myfile.txt") { fd, _ in
      let name = try fd.fileName()
      // The returned path omits the drive letter but ends with our file.
      #expect(
        name.lastComponent?.string == "myfile.txt",
        "unexpected file name: \(name)")
    }
  }

  @available(System 99, *)
  @Test func normalizedFileName() async throws {
    try withTemporaryFile(basename: "normalizedName", leaf: "myfile.txt") { fd, _ in
      let name = try fd.fileName(normalized: true)
      #expect(
        name.lastComponent?.string == "myfile.txt",
        "unexpected normalized file name: \(name)")
    }
  }

  @available(System 99, *)
  @Test func fileNameGrowsBuffer() async throws {
    // A 250-character leaf (within the 255-char filename limit) plus the
    // temporary-directory component pushes the volume-relative path past the
    // initial MAX_PATH buffer guess, exercising the ERROR_MORE_DATA grow-and-
    // retry path in `_fileName`.
    let longLeaf = String(repeating: "a", count: 250)
    try withTemporaryFile(basename: "growBuffer", leaf: longLeaf) { fd, _ in
      let name = try fd.fileName()
      #expect(
        name.lastComponent?.string == longLeaf,
        "unexpected file name: \(name)")
      #expect(name.string.utf16.count > Int(MAX_PATH))
    }
  }

  @available(System 99, *)
  @Test func genericInferredFromContext() async throws {
    try withTemporaryFile(basename: "inferred") { fd, _ in
      // The result type drives which info class is fetched.
      let info: FileStandardInfo = try fd.fileInformation()
      #expect(!info.isDirectory)
    }
  }

  @available(System 99, *)
  @Test func unsafeFileInformationMatchesTypedResult() async throws {
    let contents = "Hello, world!"
    try withTemporaryFile(basename: "unsafeInfo", contents: contents) { fd, _ in
      let size = try fd.withUnsafeFileInformation(.standard) { buffer in
        FileStandardInfo(
          rawValue: buffer.loadUnaligned(as: FILE_STANDARD_INFO.self)
        ).endOfFile
      }
      #expect(size == Int64(contents.utf8.count))
    }
  }

  @available(System 99, *)
  @Test func unsafeFileInformationGrowsBuffer() async throws {
    try withTemporaryFile(basename: "unsafeGrow", leaf: "myfile.txt") { fd, _ in
      // A 4-byte first attempt cannot hold the name, so this only succeeds if
      // the grow-and-retry loop runs. The caller no longer has to size the
      // buffer, which is the point of the closure form.
      let length = try fd.withUnsafeFileInformation(
        .name, minimumCapacity: 4
      ) { buffer in
        Int(buffer.loadUnaligned(as: DWORD.self))
      }
      let expected = try fd.fileName()
      #expect(length == expected.string.utf16.count * 2)
    }
  }

  @available(System 99, *)
  @Test func unsafeFileInformationRespectsMaximumCapacity() async throws {
    try withTemporaryFile(basename: "unsafeCapped") { fd, _ in
      // Capped below what the name needs, the loop gives up rather than growing
      // forever, surfacing ERROR_MORE_DATA as ERANGE.
      #expect(throws: Errno.outOfRange) {
        try fd.withUnsafeFileInformation(
          .name, minimumCapacity: 4, maximumCapacity: 8
        ) { _ in }
      }
    }
  }

  @available(System 99, *)
  @Test func unsafeFileInformationPropagatesBodyError() async throws {
    struct Sentinel: Error {}
    try withTemporaryFile(basename: "unsafeThrows") { fd, _ in
      #expect(throws: Sentinel.self) {
        try fd.withUnsafeFileInformation(.standard) { _ in throw Sentinel() }
      }
    }
  }

  @available(System 99, *)
  @Test func badDescriptorThrows() async throws {
    let fd = FileDescriptor(rawValue: -1)
    #expect(throws: Errno.badFileDescriptor) {
      try fd.fileInformation(FileStandardInfo.self)
    }
  }

  @available(System 99, *)
  @Test func infoClassDescriptions() async throws {
    #expect(FileInfoClass.basic.description == "basic")
    #expect(FileInfoClass.normalizedName.description == "normalizedName")
    #expect(FileInfoClass.idExtendedDirectoryRestart.description
              == "idExtendedDirectoryRestart")
  }

  @available(System 99, *)
  @Test func attributeDescriptions() async throws {
    let attributes: FileAttributes = [.readOnly, .device, .virtual]
    let description = attributes.description
    #expect(description.contains(".readOnly"))
    #expect(description.contains(".device"))
    #expect(description.contains(".virtual"))
  }

  // MARK: - Data streams

  @available(System 99, *)
  @Test func dataStreamsReportsDefaultStream() async throws {
    let contents = "Hello, world!"
    try withTemporaryFile(basename: "streams", contents: contents) { fd, _ in
      let streams = try fd.dataStreams()
      let unnamed = try #require(
        streams.first { $0.name == "::$DATA" },
        "expected a default data stream, got \(streams)")
      #expect(unnamed.size == Int64(contents.utf8.count))
      #expect(unnamed.allocationSize >= unnamed.size)
    }
  }

  @available(System 99, *)
  @Test func dataStreamsWalksWholeChain() async throws {
    let contents = "Hello, world!"
    let alternate = "alternate contents"
    try withTemporaryFile(
      basename: "adsStreams", contents: contents
    ) { fd, path in
      try createAlternateDataStream(
        at: path, named: "meta", contents: alternate)

      // Two records means the walk has to follow a NextEntryOffset to reach the
      // second, which is what the raw-buffer form left to the caller.
      let streams = try fd.dataStreams()
      #expect(streams.count == 2, "unexpected streams: \(streams)")

      let unnamed = try #require(streams.first { $0.name == "::$DATA" })
      #expect(unnamed.size == Int64(contents.utf8.count))

      let named = try #require(streams.first { $0.name == ":meta:$DATA" })
      #expect(named.size == Int64(alternate.utf8.count))
    }
  }

  @available(System 99, *)
  @Test func dataStreamsOnDirectoryIsEmpty() async throws {
    try withTemporaryFilePath(basename: "dirStreams") { dir in
      try withDirectoryDescriptor(at: dir) { fd in
        // A directory has no data streams. Windows says so with
        // ERROR_HANDLE_EOF, which is an absence rather than a failure.
        let streams = try fd.dataStreams()
        #expect(streams.isEmpty)
      }
    }
  }

  // MARK: - Directory enumeration

  @available(System 99, *)
  @Test func directoryEntriesListsContents() async throws {
    try withTemporaryFilePath(basename: "dirEntries") { dir in
      let leaves = ["a.txt", "b.txt", "c.txt"]
      for leaf in leaves {
        try createFile(at: dir.appending(leaf))
      }

      try withDirectoryDescriptor(at: dir) { fd in
        var names: [String] = []
        var special: [String] = []
        try fd.withDirectoryEntries(FileFullDirectoryEntry.self) { entries in
          while let entry = try entries.next() {
            if entry.isSpecialDirectoryEntry {
              special.append(entry.name.string)
            } else {
              names.append(entry.name.string)
            }
          }
        }
        #expect(names.sorted() == leaves)
        // Windows always reports these two, and `kind` is what tells them apart.
        #expect(special.sorted() == [".", ".."])
      }
    }
  }

  @available(System 99, *)
  @Test func directoryEntriesReportCommonFields() async throws {
    let contents = "Hello, world!"
    try withTemporaryFilePath(basename: "dirFields") { dir in
      let leaf = "target.txt"
      try createFile(at: dir.appending(leaf), contents: contents)
      try createFile(at: dir.appending("other.txt"))

      try withDirectoryDescriptor(at: dir) { fd in
        var found: FileFullDirectoryEntry?
        try fd.withDirectoryEntries(FileFullDirectoryEntry.self) { entries in
          while let entry = try entries.next() {
            if entry.name.string == leaf { found = entry }
          }
        }
        let entry = try #require(found, "did not find \(leaf)")
        // Each of these lands at a different offset in the record, so together
        // they check that the decode is reading the right members.
        #expect(entry.size == Int64(contents.utf8.count))
        #expect(entry.allocationSize >= entry.size)
        #expect(!entry.isDirectory)
        #expect(!entry.attributes.contains(.directory))
        #expect(entry.creationTime.rawValue > 0)
        #expect(entry.lastWriteTime.rawValue > 0)
        #expect(entry.creationTime.secondsSinceUnixEpoch > 0)
      }
    }
  }

  @available(System 99, *)
  @Test func idExtendedDirectoryEntryMatchesIDInfo() async throws {
    let contents = "Hello, world!"
    try withTemporaryFilePath(basename: "extdEntries") { dir in
      let leaf = "target.txt"
      let path = dir.appending(leaf)

      let fd = try FileDescriptor.open(
        path, .readWrite,
        options: [.create, .truncate],
        permissions: .ownerReadWrite)
      try fd.writeAll(contents.utf8)
      let expected = try fd.fileInformation(FileIDInfo.self)
      try fd.close()

      try withDirectoryDescriptor(at: dir) { directory in
        var found: FileIDExtendedDirectoryEntry?
        try directory.withDirectoryEntries(
          FileIDExtendedDirectoryEntry.self
        ) { entries in
          while let entry = try entries.next() {
            if entry.name.string == leaf { found = entry }
          }
        }
        let entry = try #require(found, "did not find \(leaf)")
        // Cross-checked against the same identifier fetched through a different
        // information class, which pins down the FileId member's offset.
        #expect(entry.fileID == expected.fileID)
        #expect(entry.size == Int64(contents.utf8.count))
        #expect(entry.reparseTag == nil)
      }
    }
  }

  @available(System 99, *)
  @Test func idBothDirectoryEntryReportsIdentifier() async throws {
    let contents = "Hello, world!"
    try withTemporaryFilePath(basename: "bothEntries") { dir in
      let leaf = "target.txt"
      try createFile(at: dir.appending(leaf), contents: contents)

      try withDirectoryDescriptor(at: dir) { fd in
        var found: FileIDBothDirectoryEntry?
        try fd.withDirectoryEntries(FileIDBothDirectoryEntry.self) { entries in
          while let entry = try entries.next() {
            if entry.name.string == leaf { found = entry }
          }
        }
        let entry = try #require(found, "did not find \(leaf)")
        #expect(entry.size == Int64(contents.utf8.count))
        // The 64-bit identifier follows the fixed-width ShortName array, so a
        // plausible value here is evidence that field was skipped correctly.
        #expect(entry.fileID != 0)
        // Short names may be disabled on the volume, so only the shape of a
        // reported one can be checked.
        if let shortName = entry.shortName {
          #expect(!shortName.isEmpty)
          #expect(shortName.utf16.count <= 12)
        }
      }
    }
  }

  @available(System 99, *)
  @Test func directoryEntriesRestartReplaysListing() async throws {
    try withTemporaryFilePath(basename: "dirRestart") { dir in
      for leaf in ["a.txt", "b.txt", "c.txt"] {
        try createFile(at: dir.appending(leaf))
      }

      try withDirectoryDescriptor(at: dir) { fd in
        func drain(
          _ entries: inout DirectoryEntries<FileFullDirectoryEntry>
        ) throws -> [String] {
          var names: [String] = []
          while let entry = try entries.next() {
            names.append(entry.name.string)
          }
          return names
        }

        try fd.withDirectoryEntries(FileFullDirectoryEntry.self) { entries in
          let first = try drain(&entries)
          #expect(first.count == 5)

          // Exhausted: the cursor stays at the end until it is restarted.
          let past = try entries.next()
          #expect(past == nil)

          entries.restart()
          let second = try drain(&entries)
          #expect(second.sorted() == first.sorted())
        }
      }
    }
  }

  @available(System 99, *)
  @Test func directoryEntriesSpanMultipleBatches() async throws {
    try withTemporaryFilePath(basename: "dirBatches") { dir in
      // `bufferSize` is floored at `minimumBufferSize` (about 64 KiB, so that a
      // maximum-length name can always be delivered), so a small buffer cannot
      // be requested to force a refill. Overflow it with entries instead: a
      // record is its 68-byte fixed part plus the name, so 500 names of 60
      // characters need roughly 96 KiB and cannot arrive in one batch. The
      // cursor therefore has to resume rather than restart part way through.
      let prefix = String(repeating: "n", count: 50)
      let leaves = (0..<500).map { "\(prefix)\($0).txt" }
      for leaf in leaves {
        try createFile(at: dir.appending(leaf), contents: "x")
      }

      try withDirectoryDescriptor(at: dir) { fd in
        var names: [String] = []
        try fd.withDirectoryEntries(FileFullDirectoryEntry.self) { entries in
          while let entry = try entries.next() {
            guard !entry.isSpecialDirectoryEntry else { continue }
            names.append(entry.name.string)
          }
        }
        // Every entry exactly once: no batch boundary dropped or repeated one.
        #expect(names.sorted() == leaves.sorted())
      }
    }
  }

  @available(System 99, *)
  @Test func directoryEntriesOnFileFails() async throws {
    try withTemporaryFile(basename: "notADirectory") { fd, _ in
      // The directory classes need a directory handle.
      #expect(throws: (any Error).self) {
        try fd.withDirectoryEntries(FileFullDirectoryEntry.self) { entries in
          _ = try entries.next()
        }
      }
    }
  }

  @available(System 99, *)
  @Test func directoryEntriesGenericOverEntryType() async throws {
    try withTemporaryFilePath(basename: "dirGeneric") { dir in
      try createFile(at: dir.appending("a.txt"))

      func names<Entry: FileDirectoryEntry>(
        in directory: FileDescriptor, as type: Entry.Type
      ) throws -> [String] {
        try directory.withDirectoryEntries(type) { entries in
          var result: [String] = []
          while let entry = try entries.next() {
            guard !entry.isSpecialDirectoryEntry else { continue }
            result.append(entry.name.string)
          }
          return result
        }
      }

      try withDirectoryDescriptor(at: dir) { fd in
        // The three classes disagree about extras but agree about the common
        // members, which is what the protocol lets callers rely on.
        let full = try names(in: fd, as: FileFullDirectoryEntry.self)
        let both = try names(in: fd, as: FileIDBothDirectoryEntry.self)
        let extended = try names(in: fd, as: FileIDExtendedDirectoryEntry.self)
        #expect(full == ["a.txt"])
        #expect(both == ["a.txt"])
        #expect(extended == ["a.txt"])
      }
    }
  }

  @available(System 99, *)
  @Test func directoryEntriesBufferSizeHasFloor() async throws {
    // A buffer too small for one maximum-length record could not deliver it at
    // all, so the requested size is raised rather than honoured.
    #expect(FileFullDirectoryEntry.minimumBufferSize > 32767 * 2)
    #expect(
      FileIDExtendedDirectoryEntry.minimumBufferSize
        > FileFullDirectoryEntry.minimumBufferSize)
  }
}

#endif // os(Windows)
