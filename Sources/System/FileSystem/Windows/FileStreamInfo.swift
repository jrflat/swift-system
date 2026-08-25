//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift System open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift System project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if os(Windows)

import WinSDK

// MARK: - FileStreamInfo

/// One data stream of a file.
///
/// This is the decoded form of a C `FILE_STREAM_INFO` record, retrieved by
/// ``FileDescriptor/dataStreams()``.
///
/// Unlike the fixed-size information structs such as ``FileStandardInfo``, this
/// is not a ``FileInfoByHandle`` wrapper around the C struct: `FILE_STREAM_INFO`
/// ends in a flexible `StreamName` array, so it has no fixed size to wrap and
/// its name has to be copied out to outlive the buffer it arrived in.
///
/// - Note: Only available on Windows.
@frozen
@available(System 99, *)
public struct FileStreamInfo: Sendable {
  /// The name of the stream, including its type.
  ///
  /// Windows reports the name in the form `:name:$type`, so a file's unnamed
  /// data stream is `::$DATA` and an alternate data stream called `meta` is
  /// `:meta:$DATA`.
  ///
  /// The corresponding C member is `StreamName`. Note that a stream name is not
  /// a path component — it contains colons — so it is reported as a `String`
  /// rather than a ``FilePath/Component``. Ill-formed UTF-16 is replaced with
  /// U+FFFD.
  public var name: String

  /// The size of the stream, in bytes.
  ///
  /// The corresponding C member is `StreamSize`.
  public var size: Int64

  /// The number of bytes allocated for the stream on disk.
  ///
  /// The corresponding C member is `StreamAllocationSize`.
  public var allocationSize: Int64

  /// Creates a stream description.
  @_alwaysEmitIntoClient
  public init(name: String, size: Int64, allocationSize: Int64) {
    self.name = name
    self.size = size
    self.allocationSize = allocationSize
  }
}

@available(System 99, *)
extension FileStreamInfo: CustomStringConvertible {
  /// A textual representation of the stream.
  @inline(never)
  public var description: String {
    "FileStreamInfo(name: \(name), size: \(size), allocationSize: \(allocationSize))"
  }
}

// MARK: - FileDescriptor API

@available(System 99, *)
extension FileDescriptor {
  /// Retrieves the data streams of the file referred to by this descriptor.
  ///
  /// Every regular file on NTFS has at least an unnamed data stream, reported as
  /// `::$DATA`; alternate data streams appear alongside it:
  ///
  ///     for stream in try fd.dataStreams() {
  ///       print(stream.name, stream.size)
  ///     }
  ///
  /// - Returns: The file's streams, or an empty array if it has none. A file
  ///   system that does not implement streams reports none rather than failing.
  ///
  /// - Precondition: This descriptor must not refer to a pipe.
  ///
  /// Windows returns every stream in a single call, so unlike
  /// ``directoryEntries(_:bufferSize:)`` there is no cursor to advance: the
  /// buffer is sized, grown, and released internally.
  ///
  /// The corresponding C function is `GetFileInformationByHandleEx` with the
  /// `FileStreamInfo` information class.
  @_alwaysEmitIntoClient
  public func dataStreams() throws(Errno) -> [FileStreamInfo] {
    try _dataStreams().get()
  }

  @usableFromInline
  internal func _dataStreams() -> Result<[FileStreamInfo], Errno> {
    let headerSize = MemoryLayout<FILE_STREAM_INFO>.offset(of: \.StreamName)!

    // `FILE_STREAM_INFO` carries no total-size hint — only per-record name
    // lengths — so a short buffer can only be answered by growing blindly.
    // 4 KiB holds a couple of dozen typical records; the ceiling is a backstop
    // against a file system that reports `ERROR_MORE_DATA` forever.
    let result = _withFileInformationBuffer(
      fileDescriptor: self.rawValue,
      infoClass: FileInfoClass.stream.rawValue,
      initialCapacity: 4096,
      maximumCapacity: 16 << 20,
      alignment: MemoryLayout<FILE_STREAM_INFO>.alignment,
      capacityHint: { _ in 0 }
    ) { buffer -> [FileStreamInfo] in
      var streams: [FileStreamInfo] = []
      var offset: Int? = 0
      while let cursor = offset,
            let entry = _fileInformationEntry(
              in: buffer, at: cursor, headerSize: headerSize) {
        offset = entry.nextOffset
        streams.append(_decodeStreamInfo(entry.bytes, headerSize: headerSize))
      }
      return streams
    }

    switch result {
    case .success(let streams):
      return .success(streams)
    case .failure(let error):
      // A file with no streams at all is reported as end-of-file rather than as
      // an empty chain. That is an absence, not a failure.
      if error.code == ERROR_HANDLE_EOF { return .success([]) }
      return .failure(Errno(windowsError: error.code))
    }
  }
}

/// Decodes one `FILE_STREAM_INFO` record.
///
/// `record` spans the whole record, so the reported `StreamNameLength` is
/// clamped against it before it is used to bound the name.
@available(System 99, *)
@usableFromInline
internal func _decodeStreamInfo(
  _ record: UnsafeRawBufferPointer, headerSize: Int
) -> FileStreamInfo {
  let nameLengthOffset =
    MemoryLayout<FILE_STREAM_INFO>.offset(of: \.StreamNameLength)!
  let sizeOffset = MemoryLayout<FILE_STREAM_INFO>.offset(of: \.StreamSize)!
  let allocationOffset =
    MemoryLayout<FILE_STREAM_INFO>.offset(of: \.StreamAllocationSize)!

  let reportedLength = Int(
    record.loadUnaligned(fromByteOffset: nameLengthOffset, as: DWORD.self))
  let nameLength = _clampedWideLength(
    in: record, offset: headerSize, byteCount: reportedLength)

  // `LARGE_INTEGER` is a union whose `QuadPart` is a 64-bit integer at offset
  // zero, so the member is read directly as `Int64`.
  return FileStreamInfo(
    name: record.baseAddress.map {
      _decodeWideString(
        base: $0.advanced(by: headerSize), byteCount: nameLength)
    } ?? "",
    size: record.loadUnaligned(fromByteOffset: sizeOffset, as: Int64.self),
    allocationSize: record.loadUnaligned(
      fromByteOffset: allocationOffset, as: Int64.self))
}

#endif // os(Windows)
