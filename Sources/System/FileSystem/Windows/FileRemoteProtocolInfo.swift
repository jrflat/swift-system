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

// MARK: - FileRemoteProtocolInfo

/// Information about the remote protocol serving a file.
///
/// This is a Swift wrapper of the C `FILE_REMOTE_PROTOCOL_INFO` struct,
/// retrieved by ``FileDescriptor/fileInformation(_:)``. Retrieving it for a
/// local file fails.
///
/// - Note: Only available on Windows.
@frozen
@available(System 99, *)
public struct FileRemoteProtocolInfo: RawRepresentable, Sendable {
  /// The raw C `FILE_REMOTE_PROTOCOL_INFO` struct.
  @_alwaysEmitIntoClient
  public var rawValue: FILE_REMOTE_PROTOCOL_INFO

  /// Creates a Swift `FileRemoteProtocolInfo` from the raw C struct.
  @_alwaysEmitIntoClient
  public init(rawValue: FILE_REMOTE_PROTOCOL_INFO) { self.rawValue = rawValue }

  /// The version of the structure the redirector filled in. Some ``flags``
  /// are only reported when this is 2 or greater.
  ///
  /// The corresponding C member is `StructureVersion`.
  @_alwaysEmitIntoClient
  public var structureVersion: UInt16 {
    rawValue.StructureVersion
  }

  /// The size of the structure the redirector filled in, in bytes.
  ///
  /// The corresponding C member is `StructureSize`.
  @_alwaysEmitIntoClient
  public var structureSize: UInt16 {
    rawValue.StructureSize
  }

  /// The remote protocol serving the file.
  ///
  /// The corresponding C member is `Protocol`.
  @_alwaysEmitIntoClient
  public var remoteProtocol: RemoteProtocol {
    RemoteProtocol(rawValue: rawValue.Protocol)
  }

  /// The major version of the remote protocol.
  ///
  /// The corresponding C member is `ProtocolMajorVersion`.
  @_alwaysEmitIntoClient
  public var protocolMajorVersion: UInt16 {
    rawValue.ProtocolMajorVersion
  }

  /// The minor version of the remote protocol.
  ///
  /// The corresponding C member is `ProtocolMinorVersion`.
  @_alwaysEmitIntoClient
  public var protocolMinorVersion: UInt16 {
    rawValue.ProtocolMinorVersion
  }

  /// The revision of the remote protocol.
  ///
  /// The corresponding C member is `ProtocolRevision`.
  @_alwaysEmitIntoClient
  public var protocolRevision: UInt16 {
    rawValue.ProtocolRevision
  }

  /// Flags describing how the remote protocol is being used.
  ///
  /// The corresponding C member is `Flags`.
  @_alwaysEmitIntoClient
  public var flags: Flags {
    Flags(rawValue: rawValue.Flags)
  }

  /// SMB2-specific capability and share information.
  ///
  /// Meaningful only when ``remoteProtocol`` is ``RemoteProtocol/smb`` and
  /// ``protocolMajorVersion`` is 2 or greater.
  ///
  /// The corresponding C member is `ProtocolSpecific.Smb2`.
  @_alwaysEmitIntoClient
  public var smb2: SMB2 {
    let raw = rawValue.ProtocolSpecific.Smb2
    return SMB2(
      serverCapabilities: raw.Server.Capabilities,
      shareCapabilities: raw.Share.Capabilities,
      shareFlags: raw.Share.ShareFlags,
      shareCachingFlags: raw.Share.CachingFlags)
  }

  /// Flags for a ``FileRemoteProtocolInfo`` value.
  @frozen
  public struct Flags: OptionSet, Sendable, Hashable, Codable {
    /// The raw C bitmask.
    @_alwaysEmitIntoClient
    public var rawValue: UInt32

    /// Creates remote-protocol flags from a raw C bitmask.
    @_alwaysEmitIntoClient
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// The remote protocol is using a loopback.
    ///
    /// The corresponding C constant is `REMOTE_PROTOCOL_FLAG_LOOPBACK`.
    @_alwaysEmitIntoClient
    public static var loopback: Flags { Flags(rawValue: 0x0000_0001) }

    /// The remote protocol is using an offline cache.
    ///
    /// The corresponding C constant is `REMOTE_PROTOCOL_FLAG_OFFLINE`.
    @_alwaysEmitIntoClient
    public static var offline: Flags { Flags(rawValue: 0x0000_0002) }

    /// The remote protocol is using a persistent handle.
    ///
    /// The corresponding C constant is
    /// `REMOTE_PROTOCOL_INFO_FLAG_PERSISTENT_HANDLE`.
    @_alwaysEmitIntoClient
    public static var persistentHandle: Flags { Flags(rawValue: 0x0000_0004) }

    /// The remote protocol is using privacy. Reported only when
    /// ``FileRemoteProtocolInfo/structureVersion`` is 2 or greater.
    ///
    /// The corresponding C constant is `REMOTE_PROTOCOL_INFO_FLAG_PRIVACY`.
    @_alwaysEmitIntoClient
    public static var privacy: Flags { Flags(rawValue: 0x0000_0008) }

    /// The remote protocol is signing data. Reported only when
    /// ``FileRemoteProtocolInfo/structureVersion`` is 2 or greater.
    ///
    /// The corresponding C constant is `REMOTE_PROTOCOL_INFO_FLAG_INTEGRITY`.
    @_alwaysEmitIntoClient
    public static var integrity: Flags { Flags(rawValue: 0x0000_0010) }

    /// The remote protocol is using mutual authentication through Kerberos.
    /// Reported only when ``FileRemoteProtocolInfo/structureVersion`` is 2 or
    /// greater.
    ///
    /// The corresponding C constant is `REMOTE_PROTOCOL_INFO_FLAG_MUTUAL_AUTH`.
    @_alwaysEmitIntoClient
    public static var mutualAuthentication: Flags { Flags(rawValue: 0x0000_0020) }
  }

  /// SMB2-specific information from a ``FileRemoteProtocolInfo`` value.
  ///
  /// The bit meanings of these fields are defined by the SMB2 protocol
  /// specification (MS-SMB2) rather than by any Windows API reference:
  /// ``shareCapabilities`` carries SMB2 `SHARE_CAP_*` bits, ``shareFlags``
  /// carries `SHAREFLAG_*` bits, and ``serverCapabilities`` carries the
  /// negotiate-response capability bits.
  @frozen
  public struct SMB2: Sendable, Hashable, Codable {
    /// The server's capability bits.
    ///
    /// The corresponding C member is
    /// `ProtocolSpecific.Smb2.Server.Capabilities`.
    @_alwaysEmitIntoClient
    public var serverCapabilities: UInt32

    /// The share's capability bits.
    ///
    /// The corresponding C member is
    /// `ProtocolSpecific.Smb2.Share.Capabilities`.
    @_alwaysEmitIntoClient
    public var shareCapabilities: UInt32

    /// The share's flags.
    ///
    /// The corresponding C member is `ProtocolSpecific.Smb2.Share.ShareFlags`.
    @_alwaysEmitIntoClient
    public var shareFlags: UInt32

    /// The share's caching flags.
    ///
    /// The corresponding C member is
    /// `ProtocolSpecific.Smb2.Share.CachingFlags`.
    @_alwaysEmitIntoClient
    public var shareCachingFlags: UInt32

    /// Creates SMB2 information from its constituent bitmasks.
    @_alwaysEmitIntoClient
    public init(
      serverCapabilities: UInt32,
      shareCapabilities: UInt32,
      shareFlags: UInt32,
      shareCachingFlags: UInt32
    ) {
      self.serverCapabilities = serverCapabilities
      self.shareCapabilities = shareCapabilities
      self.shareFlags = shareFlags
      self.shareCachingFlags = shareCachingFlags
    }
  }
}

// MARK: - RemoteProtocol

/// A network protocol that can serve a remote file.
///
/// These correspond to the `WNNC_NET_*` constants and appear in
/// ``FileRemoteProtocolInfo/remoteProtocol``. Windows defines a large number
/// of these, most for providers that no longer ship; the values named below
/// are those still in use. Any other value passes through ``rawValue``.
///
/// - Note: Only available on Windows.
@frozen
@available(System 99, *)
public struct RemoteProtocol: RawRepresentable, Sendable, Hashable, Codable {
  /// The raw C `ULONG` value.
  @_alwaysEmitIntoClient
  public var rawValue: UInt32

  /// Creates a strongly-typed remote protocol from a raw C value.
  @_alwaysEmitIntoClient
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// Server Message Block, in any version.
  ///
  /// The corresponding C constants are `WNNC_NET_SMB` and `WNNC_NET_LANMAN`,
  /// which share this value.
  @_alwaysEmitIntoClient
  public static var smb: RemoteProtocol { RemoteProtocol(rawValue: 0x0002_0000) }

  /// NetWare Core Protocol.
  ///
  /// The corresponding C constant is `WNNC_NET_NETWARE`.
  @_alwaysEmitIntoClient
  public static var netware: RemoteProtocol { RemoteProtocol(rawValue: 0x0003_0000) }

  /// Client-side caching, i.e. Offline Files.
  ///
  /// The corresponding C constant is `WNNC_NET_CSC`.
  @_alwaysEmitIntoClient
  public static var clientSideCaching: RemoteProtocol { RemoteProtocol(rawValue: 0x0026_0000) }

  /// WebDAV.
  ///
  /// The corresponding C constant is `WNNC_NET_DAV`.
  @_alwaysEmitIntoClient
  public static var webDAV: RemoteProtocol { RemoteProtocol(rawValue: 0x002E_0000) }

  /// Terminal Services client drive redirection.
  ///
  /// The corresponding C constant is `WNNC_NET_TERMSRV`.
  @_alwaysEmitIntoClient
  public static var terminalServices: RemoteProtocol { RemoteProtocol(rawValue: 0x0036_0000) }

  /// OpenAFS.
  ///
  /// The corresponding C constant is `WNNC_NET_OPENAFS`.
  @_alwaysEmitIntoClient
  public static var openAFS: RemoteProtocol { RemoteProtocol(rawValue: 0x0039_0000) }

  /// Distributed File System.
  ///
  /// The corresponding C constant is `WNNC_NET_DFS`.
  @_alwaysEmitIntoClient
  public static var dfs: RemoteProtocol { RemoteProtocol(rawValue: 0x003B_0000) }

  /// VMware shared folders.
  ///
  /// The corresponding C constant is `WNNC_NET_VMWARE`.
  @_alwaysEmitIntoClient
  public static var vmware: RemoteProtocol { RemoteProtocol(rawValue: 0x003F_0000) }

  /// The Microsoft Network File System client.
  ///
  /// The corresponding C constant is `WNNC_NET_MS_NFS`.
  @_alwaysEmitIntoClient
  public static var nfs: RemoteProtocol { RemoteProtocol(rawValue: 0x0042_0000) }

  /// Google Drive.
  ///
  /// The corresponding C constant is `WNNC_NET_GOOGLE`.
  @_alwaysEmitIntoClient
  public static var google: RemoteProtocol { RemoteProtocol(rawValue: 0x0043_0000) }
}

#endif // os(Windows)
