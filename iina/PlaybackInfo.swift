//
//  PlaybackInfo.swift
//  iina
//
//  Created by lhc on 21/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Foundation

class PlaybackInfo {

  /// Enumeration representing the status of the [mpv](https://mpv.io/manual/stable/) A-B loop command.
  ///
  /// The A-B loop command cycles mpv through these states:
  /// - Cleared (looping disabled)
  /// - A loop point set
  /// - B loop point set (looping enabled)
  enum LoopStatus {
    case cleared
    case aSet
    case bSet
  }

  enum MediaIsAudioStatus {
    case unknown
    case isAudio
    case notAudio
  }

  unowned let player: PlayerCore

  init(_ pc: PlayerCore) {
    player = pc
  }

  // TODO: - Change log level of state changed message to be .verbose once state is confirmed working.

  /// The state the `PlayerCore` is in.
  /// - Note: A computed property is used to prevent inappropriate state changes. When IINA terminates players that are actively
  ///     playing will first be stopped and then shutdown. Once a player has stopped the mpv core will go idle. This happens
  ///     asynchronously and could occur after the quit command has been sent to mpv. Thus we must be sure the state does not
  ///     transition from `.shuttingDown` to `.idle`.
  var state: PlayerState = .idle {
    didSet {
      guard state != oldValue else { return }
      // Once the player is in the shuttingDown state it can only move to the shutDown state. Once
      // in the shutDown state the state can't change.
      guard oldValue != .loading || state != .idle,
            oldValue != .shuttingDown || state == .shutDown, oldValue != .shutDown else {
        player.log("Blocked attempt to change state from \(oldValue) to \(state)")
        state = oldValue
        return
      }
      player.log("State changed from \(oldValue) to \(state)")
      switch state {
      case .idle:
        PlayerCore.checkStatusForSleep()
      case .playing:
        PlayerCore.checkStatusForSleep()
        if player == PlayerCore.lastActive {
          if RemoteCommandController.useSystemMediaControl {
            NowPlayingInfoManager.updateInfo(state: .playing)
          }
          if player.mainWindow.pipStatus == .inPIP {
            player.mainWindow.pip.playing = true
          }
        }
      case .paused:
        PlayerCore.checkStatusForSleep()
        if player == PlayerCore.lastActive {
          if RemoteCommandController.useSystemMediaControl {
            NowPlayingInfoManager.updateInfo(state: .paused)
          }
          if player.mainWindow.pipStatus == .inPIP {
            player.mainWindow.pip.playing = false
          }
        }
      default: return
      }
    }
  }

  var isSeeking: Bool = false

  var currentURL: URL? {
    didSet {
      if let url = currentURL {
        mpvMd5 = Utility.mpvWatchLaterMd5(url.path)
      } else {
        mpvMd5 = nil
      }
    }
  }
  var currentFolder: URL?
  var isNetworkResource: Bool = false
  var mpvMd5: String?

  var videoWidth: Int?
  var videoHeight: Int?

  var displayWidth: Int?
  var displayHeight: Int?

  var rotation: Int = 0

  var videoPosition: VideoTime?
  var videoDuration: VideoTime?

  var cachedWindowScale: Double = 1.0

  func constrainVideoPosition() {
    guard let duration = videoDuration, let position = videoPosition else { return }
    if position.second < 0 { position.second = 0 }
    if position.second > duration.second { position.second = duration.second }
  }

  var isAudio: MediaIsAudioStatus {
    guard !isNetworkResource else { return .notAudio }
    let noVideoTrack = videoTracks.isEmpty
    let noAudioTrack = audioTracks.isEmpty
    if noVideoTrack && noAudioTrack {
      return .unknown
    }
    let allVideoTracksAreAlbumCover = !videoTracks.contains { !$0.isAlbumart }
    return (noVideoTrack || allVideoTracksAreAlbumCover) ? .isAudio : .notAudio
  }

  var justStartedFile: Bool = false
  var justOpenedFile: Bool = false
  var shouldAutoLoadFiles: Bool = false
  var isMatchingSubtitles = false
  var disableOSDForFileLoading: Bool = false

  /** The current applied aspect, used for find current aspect in menu, etc. Maybe not a good approach. */
  var unsureAspect: String = "Default"
  var unsureCrop: String = "None" // TODO: rename this to "selectedCrop"
  var cropFilter: MPVFilter?
  var flipFilter: MPVFilter?
  var mirrorFilter: MPVFilter?
  var audioEqFilter: MPVFilter?
  var delogoFilter: MPVFilter?

  var deinterlace: Bool = false
  var hwdec: String = "no"
  var hwdecEnabled: Bool {
    hwdec != "no"
  }
  var hdrAvailable: Bool = false
  var hdrEnabled: Bool = true

  // video equalizer
  var brightness: Int = 0
  var contrast: Int = 0
  var saturation: Int = 0
  var gamma: Int = 0
  var hue: Int = 0

  var volume: Double = 50

  var isMuted: Bool = false

  var playSpeed: Double = 1

  var audioDelay: Double = 0
  var subDelay: Double = 0

  // cache related
  var pausedForCache: Bool = false
  var cacheUsed: Int = 0
  var cacheSpeed: Int = 0
  var cacheTime: Int = 0
  var bufferingState: Int = 0

  var audioTracks: [MPVTrack] = []
  var videoTracks: [MPVTrack] = []
  @Atomic var subTracks: [MPVTrack] = []

  var abLoopStatus: LoopStatus = .cleared

  /** Selected track IDs. Use these (instead of `isSelected` of a track) to check if selected */
  @Atomic var aid: Int?
  @Atomic var sid: Int?
  @Atomic var vid: Int?
  @Atomic var secondSid: Int?

  var isSubVisible = true
  var isSecondSubVisible = true

  var subEncoding: String?

  var haveDownloadedSub: Bool = false

  func trackList(_ type: MPVTrack.TrackType) -> [MPVTrack] {
    switch type {
    case .video: return videoTracks
    case .audio: return audioTracks
    case .sub, .secondSub: return subTracks
    }
  }

  func trackId(_ type: MPVTrack.TrackType) -> Int? {
    switch type {
    case .video: return vid
    case .audio: return aid
    case .sub: return sid
    case .secondSub: return secondSid
    }
  }

  func currentTrack(_ type: MPVTrack.TrackType) -> MPVTrack? {
    let id: Int?, list: [MPVTrack]
    switch type {
    case .video:
      id = vid
      list = videoTracks
    case .audio:
      id = aid
      list = audioTracks
    case .sub:
      id = sid
      list = subTracks
    case .secondSub:
      id = secondSid
      list = subTracks
    }
    if let id = id {
      return list.first { $0.id == id }
    } else {
      return nil
    }
  }

  var playlist: [MPVPlaylistItem] = []
  var chapters: [MPVChapter] = []
  var chapter = 0

  @Atomic var matchedSubs: [String: [URL]] = [:]

  func getMatchedSubs(_ file: String) -> [URL]? { $matchedSubs.withLock { $0[file] } }

  var currentSubsInfo: [FileInfo] = []
  var currentVideosInfo: [FileInfo] = []

  // The cache is read by the main thread and updated by a background thread therefore all use
  // must be through the class methods that properly coordinate thread access.
  private var cachedVideoDurationAndProgress: [String: (duration: Double?, progress: Double?)] = [:]
  private var cachedMetadata: [String: (title: String?, album: String?, artist: String?)] = [:]

  // Queue dedicated to providing serialized access to class data shared between threads.
  // Data is accessed by the main thread, therefore the QOS for the queue must not be too low
  // to avoid blocking the main thread for an extended period of time.
  private let lockQueue = DispatchQueue(label: "IINAPlaybackInfoLock", qos: .userInitiated)

  func calculateTotalDuration() -> Double? {
    lockQueue.sync {
      var totalDuration: Double? = 0
      for p in playlist {
        if let duration = cachedVideoDurationAndProgress[p.filename]?.duration {
          totalDuration! += duration > 0 ? duration : 0
        } else {
          // Cache is missing an entry, can't provide a total.
          return nil
        }
      }
      return totalDuration
    }
  }

  func calculateTotalDuration(_ indexes: IndexSet) -> Double {
    lockQueue.sync {
      indexes
        .compactMap { cachedVideoDurationAndProgress[playlist[$0].filename]?.duration }
        .compactMap { $0 > 0 ? $0 : 0 }
        .reduce(0, +)
    }
  }

  func getCachedVideoDurationAndProgress(_ file: String) -> (duration: Double?, progress: Double?)? {
    lockQueue.sync {
      cachedVideoDurationAndProgress[file]
    }
  }

  func setCachedVideoDuration(_ file: String, _ duration: Double) {
    lockQueue.sync {
      cachedVideoDurationAndProgress[file]?.duration = duration
    }
  }

  func setCachedVideoDurationAndProgress(_ file: String, _ value: (duration: Double?, progress: Double?)) {
    lockQueue.sync {
      cachedVideoDurationAndProgress[file] = value
    }
  }

  func getCachedMetadata(_ file: String) -> (title: String?, album: String?, artist: String?)? {
    lockQueue.sync {
      cachedMetadata[file]
    }
  }

  func setCachedMetadata(_ file: String, _ value: (title: String?, album: String?, artist: String?)) {
    lockQueue.sync {
      cachedMetadata[file] = value
    }
  }

  @Atomic var thumbnailsReady = false
  @Atomic var thumbnailsProgress: Double = 0
  @Atomic var thumbnails: [FFThumbnail] = []

  func getThumbnail(forSecond sec: Double) -> FFThumbnail? {
    $thumbnails.withLock {
      guard !$0.isEmpty else { return nil }
      var tb = $0.last!
      for i in 0..<$0.count {
        if $0[i].realTime >= sec {
          tb = $0[(i == 0 ? i : i - 1)]
          break
        }
      }
      return tb
    }
  }
}
