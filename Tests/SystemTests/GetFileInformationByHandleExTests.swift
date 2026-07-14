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
    }
  }

  @available(System 99, *)
  @Test func attributeTagInfo() async throws {
    try withTemporaryFile(basename: "attrTagInfo") { fd, _ in
      let info = try fd.fileInformation(FileAttributeTagInfo.self)
      #expect(!info.attributes.contains(.directory))
      // Not a reparse point, so the tag is zero.
      if !info.attributes.contains(.reparsePoint) {
        #expect(info.reparseTag == 0)
      }
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
  @Test func badDescriptorThrows() async throws {
    let fd = FileDescriptor(rawValue: -1)
    #expect(throws: Errno.badFileDescriptor) {
      try fd.fileInformation(FileStandardInfo.self)
    }
  }
}

#endif // os(Windows)
