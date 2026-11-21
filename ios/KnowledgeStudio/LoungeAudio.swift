@preconcurrency import AVFoundation
@preconcurrency import MediaPlayer
import UIKit

@MainActor
final class LoungeAudio: NSObject, AVAudioPlayerDelegate {
    private weak var hub: LoungeHub?
    private var interruption: ObjectIdentifier?
    private var active = false

    init(hub: LoungeHub) {
        self.hub = hub
        super.init()
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        center.addObserver(self, selector: #selector(interrupted(_:)), name: AVAudioSession.interruptionNotification, object: session)
        center.addObserver(self, selector: #selector(routeChanged(_:)), name: AVAudioSession.routeChangeNotification, object: session)
        center.addObserver(self, selector: #selector(servicesReset), name: AVAudioSession.mediaServicesWereResetNotification, object: session)

        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget(self, action: #selector(remotePlay(_:)))
        commands.pauseCommand.addTarget(self, action: #selector(remotePause(_:)))
        commands.togglePlayPauseCommand.addTarget(self, action: #selector(remoteToggle(_:)))
        commands.previousTrackCommand.addTarget(self, action: #selector(remotePrevious(_:)))
        commands.nextTrackCommand.addTarget(self, action: #selector(remoteNext(_:)))
        commands.changePlaybackPositionCommand.addTarget(self, action: #selector(remoteSeek(_:)))
    }

    func activate() throws {
        guard !active else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        active = true
    }

    func deactivate() {
        guard active else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        active = false
    }

    func publish() {
        let center = MPNowPlayingInfoCenter.default()
        let commands = MPRemoteCommandCenter.shared()
        let track = hub?.track
        let hasTrack = track != nil
        let canSkip = (hub?.tracks.count ?? 0) > 1
        commands.playCommand.isEnabled = hasTrack
        commands.pauseCommand.isEnabled = hasTrack
        commands.togglePlayPauseCommand.isEnabled = hasTrack
        commands.changePlaybackPositionCommand.isEnabled = hasTrack
        commands.previousTrackCommand.isEnabled = canSkip
        commands.nextTrackCommand.isEnabled = canSkip
        guard let track, let hub else { center.nowPlayingInfo = nil; return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyPlaybackDuration: hub.player?.duration ?? track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: hub.playhead,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyPlaybackRate: hub.playing ? 1.0 : 0.0,
        ]
        if !track.artist.isEmpty { info[MPMediaItemPropertyArtist] = track.artist }
        if !track.album.isEmpty { info[MPMediaItemPropertyAlbumTitle] = track.album }
        if let artwork = track.artwork, let image = UIImage(data: artwork) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        center.nowPlayingInfo = info
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor [weak self] in self?.hub?.completeTrack(id, success: flag) }
    }

    func userPaused() { interruption = nil }

    @objc nonisolated private func interrupted(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        Task { @MainActor [weak self] in
            guard let self, let hub else { return }
            switch type {
            case .began:
                interruption = hub.playing ? hub.player.map(ObjectIdentifier.init) : nil
                active = false
                hub.pauseMusic(userInitiated: false)
            case .ended:
                let previous = interruption
                interruption = nil
                if let previous, hub.player.map(ObjectIdentifier.init) == previous,
                    AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                    hub.resumeMusic()
                }
            @unknown default: break
            }
        }
    }

    @objc nonisolated private func routeChanged(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable,
            let previous = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription,
            previous.outputs.contains(where: {
                [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio].contains($0.portType)
            }) else { return }
        Task { @MainActor [weak self] in self?.hub?.pauseMusic() }
    }

    @objc nonisolated private func servicesReset() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            active = false
            interruption = nil
            hub?.resetMusic()
        }
    }

    @objc nonisolated private func remotePlay(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        Task { @MainActor [weak self] in self?.hub?.resumeMusic() }
        return .success
    }

    @objc nonisolated private func remotePause(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        Task { @MainActor [weak self] in self?.hub?.pauseMusic() }
        return .success
    }

    @objc nonisolated private func remoteToggle(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        Task { @MainActor [weak self] in self?.hub?.togglePlayback() }
        return .success
    }

    @objc nonisolated private func remotePrevious(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        Task { @MainActor [weak self] in self?.hub?.skip(-1) }
        return .success
    }

    @objc nonisolated private func remoteNext(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        Task { @MainActor [weak self] in self?.hub?.skip(1) }
        return .success
    }

    @objc nonisolated private func remoteSeek(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        guard let seconds = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime, seconds.isFinite else {
            return .commandFailed
        }
        Task { @MainActor [weak self] in self?.hub?.seek(seconds) }
        return .success
    }
}
