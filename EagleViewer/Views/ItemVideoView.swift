//
//  ItemThumbnailView.swift
//  EagleViewer
//
//  Created on 2025/08/24
//

import AVFoundation
import NukeUI
import SwiftUI
import UIKit

struct ItemVideoView: View {
    static func isVideo(item: Item) -> Bool {
        return item.duration != 0
    }

    let item: Item
    let isSelected: Bool
    @Binding var isNoUI: Bool

    @State private var player: AVQueuePlayer?
    @State private var playerLooper: AVPlayerLooper?
    @State private var isLoading = false
    @State private var loadTask: Task<Void, Never>?
    @State private var loadTaskID: UUID?
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @State private var timeObserverToken: Any?
    @State private var isPlayerVisible = false
    @State private var playerCleanupTask: Task<Void, Never>?
    @State private var isThumbnailLoaded = false
    @State private var isPlaying = false
    @State private var wasPlayingBeforeScrub = false
    @State private var wasPlayingBeforeBackground = false

    @EnvironmentObject private var libraryFolderManager: LibraryFolderManager
    @Environment(\.rootSafeAreaInsets) private var rootSafeAreaInsets
    @Environment(\.scenePhase) private var scenePhase

    private var videoURL: URL? {
        guard let currentLibraryURL = libraryFolderManager.currentLibraryURL else {
            return nil
        }

        return currentLibraryURL.appending(path: item.imagePath, directoryHint: .notDirectory)
    }

    private var thumbnailURL: URL? {
        guard let currentLibraryURL = libraryFolderManager.currentLibraryURL else {
            return nil
        }

        return currentLibraryURL.appending(path: item.thumbnailPath, directoryHint: .notDirectory)
    }

    private var sliderRange: ClosedRange<Double> {
        0 ... max(duration, 0.001)
    }

    private var seekBar: some View {
        PhotosStyleSeekBar(
            value: Binding(
                get: { currentTime },
                set: { newValue in
                    let clamped = min(max(newValue, sliderRange.lowerBound), sliderRange.upperBound)
                    currentTime = clamped
                    seek(to: clamped)
                }
            ),
            range: sliderRange,
            isDarkBackground: isNoUI,
            onEditingChanged: handleSliderEditingChanged
        )
    }

    private var seekBarOpacity: Double {
        (isSelected && !isNoUI && duration > 0) ? 1 : 0
    }

    private var playbackControls: some View {
        HStack(alignment: .center, spacing: 16) {
            playbackButton
            seekBar
        }
        .padding(.leading, rootSafeAreaInsets.leading + 20)
        .padding(.trailing, rootSafeAreaInsets.trailing + 20)
        .padding(.bottom, rootSafeAreaInsets.bottom + 40)
    }

    private var playbackButton: some View {
        Button(action: togglePlayback) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
        }
        .contentShape(.circle)
        .glassEffect(.regular.interactive(), in: Circle())
        .disabled(player == nil && !isPlayerVisible)
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let thumbnailURL {
            LazyImage(url: thumbnailURL) { state in
                Group {
                    if let image = state.image {
                        image
                            .resizable()
                            .scaledToFit()
                    } else {
                        fallbackBackground
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    isThumbnailLoaded = state.image != nil
                }
                .onChange(of: state.image != nil) { _, newValue in
                    isThumbnailLoaded = newValue
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        } else {
            fallbackBackground
                .ignoresSafeArea()
                .onAppear {
                    isThumbnailLoaded = false
                }
        }
    }

    private var fallbackBackground: Color {
        isNoUI ? .black : .white
    }

    @ViewBuilder
    private var activeVideoContent: some View {
        ZStack {
            if let player {
                PlayerLayerView(player: player, isDarkBackground: isNoUI)
                    .allowsHitTesting(false)
                    .onAppear {
                        resumePlayback()
                    }
                    .onDisappear {
                        pausePlayback()
                    }
            }

            thumbnailContent
                .overlay {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(1.1)
                    }
                }
                .opacity(isPlayerVisible ? 0 : 1)
                .animation(isThumbnailLoaded ? .easeInOut(duration: 0.2) : nil, value: isPlayerVisible)
        }
    }

    var body: some View {
        ZStack {
            (isNoUI ? Color.black : Color.white)
                .ignoresSafeArea()

            activeVideoContent

            if isSelected {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isNoUI.toggle()
                        }
                    }
            }
        }
        .overlay(alignment: .bottom) {
            playbackControls
                .opacity(seekBarOpacity)
                .animation(.easeInOut(duration: 0.2), value: seekBarOpacity)
                .allowsHitTesting(seekBarOpacity > 0)
        }
        .onAppear {
            if isSelected {
                prepareVideoPlayer()
            } else {
                teardownPlayer()
            }
        }
        .onChange(of: videoURL) { _, _ in
            if isSelected {
                prepareVideoPlayer(forceReload: true)
            } else {
                teardownPlayer()
            }
        }
        .onChange(of: thumbnailURL) { _, _ in
            isThumbnailLoaded = false
        }
        .onChange(of: isSelected) { _, newValue in
            if newValue {
                prepareVideoPlayer(forceReload: true)
            } else {
                teardownPlayer()
            }
        }
        .onDisappear {
            teardownPlayer()
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
    }

    private func prepareVideoPlayer(forceReload: Bool = false) {
        guard isSelected else { return }

        if forceReload {
            loadTask?.cancel()
            loadTask = nil
            loadTaskID = nil
            removeTimeObserver(from: player)
            player?.pause()
            beginPlayerFadeOut()
        } else if player != nil || loadTask != nil {
            return
        }

        guard let url = videoURL else {
            isLoading = false
            return
        }

        let needsDownload = needsMaterialization(for: url)
        isLoading = needsDownload

        let taskID = UUID()
        loadTaskID = taskID

        let task = Task {
            do {
                if needsDownload {
                    try await CloudFile.ensureMaterialized(at: url)

                    if Task.isCancelled {
                        await MainActor.run {
                            if loadTaskID == taskID {
                                isLoading = false
                                loadTask = nil
                                loadTaskID = nil
                            }
                        }
                        return
                    }
                }

                let asset = AVURLAsset(url: url)
                let assetDuration = try await asset.load(.duration)
                let playerItem = AVPlayerItem(asset: asset)

                await MainActor.run {
                    guard loadTaskID == taskID else { return }
                    cancelPendingPlayerCleanup()
                    removeTimeObserver(from: player)
                    let queuePlayer = AVQueuePlayer(playerItem: playerItem)
                    player = queuePlayer
                    playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
                    duration = assetDuration.seconds.isFinite ? max(assetDuration.seconds, 0) : 0
                    currentTime = 0
                    installTimeObserver(for: queuePlayer)
                    isLoading = false
                    loadTask = nil
                    loadTaskID = nil
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isPlayerVisible = true
                    }
                    resumePlayback()
                }
            } catch {
                await MainActor.run {
                    if loadTaskID == taskID {
                        isLoading = false
                        loadTask = nil
                        loadTaskID = nil
                    }
                }
            }
        }

        loadTask = task
    }

    private func teardownPlayer() {
        loadTask?.cancel()
        loadTask = nil
        loadTaskID = nil
        isLoading = false
        removeTimeObserver(from: player)
        pausePlayback()
        beginPlayerFadeOut()
    }

    private func beginPlayerFadeOut() {
        cancelPendingPlayerCleanup()
        let shouldAnimate = isPlayerVisible || player != nil
        isScrubbing = false
        isPlaying = false
        wasPlayingBeforeBackground = false

        if shouldAnimate {
            withAnimation(.easeInOut(duration: 0.18)) {
                isPlayerVisible = false
            }
            schedulePlayerCleanup()
        } else {
            isPlayerVisible = false
            completePlayerCleanup()
        }
    }

    private func schedulePlayerCleanup() {
        cancelPendingPlayerCleanup()

        playerCleanupTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                completePlayerCleanup()
            }
        }
    }

    private func cancelPendingPlayerCleanup() {
        playerCleanupTask?.cancel()
        playerCleanupTask = nil
    }

    private func completePlayerCleanup() {
        playerCleanupTask = nil
        playerLooper = nil
        player = nil
        currentTime = 0
        duration = 0
    }

    private func togglePlayback() {
        if isPlaying {
            pausePlayback()
        } else {
            resumePlayback()
        }
    }

    private func pausePlayback() {
        guard let player else {
            isPlaying = false
            return
        }

        player.pause()
        isPlaying = false
    }

    private func resumePlayback() {
        guard let player else {
            isPlaying = false
            return
        }

        player.play()
        isPlaying = true
        wasPlayingBeforeBackground = false
    }

    private func needsMaterialization(for url: URL) -> Bool {
        if !FileManager.default.fileExists(atPath: url.path) {
            return true
        }

        let (isUbiq, isCurrent) = (try? CloudFile.ubiquitousQuickState(url)) ?? (false, false)
        return isUbiq && !isCurrent
    }

    private func handleSliderEditingChanged(_ isEditing: Bool) {
        isScrubbing = isEditing

        if isEditing {
            wasPlayingBeforeScrub = isPlaying
            pausePlayback()
        } else {
            seek(to: currentTime)
            if wasPlayingBeforeScrub {
                resumePlayback()
            }
            wasPlayingBeforeScrub = false
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            wasPlayingBeforeBackground = isPlaying
            pausePlayback()
        case .active:
            if isSelected, wasPlayingBeforeBackground {
                resumePlayback()
            }
            wasPlayingBeforeBackground = false
        default:
            break
        }
    }

    private func seek(to seconds: Double) {
        guard let player else { return }

        let time = CMTime(seconds: seconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func installTimeObserver(for player: AVQueuePlayer) {
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard !isScrubbing else { return }

            let seconds = time.seconds
            if seconds.isFinite {
                currentTime = min(max(seconds, sliderRange.lowerBound), sliderRange.upperBound)
            }
        }
    }

    private func removeTimeObserver(from player: AVQueuePlayer?) {
        guard let player, let token = timeObserverToken else { return }
        player.removeTimeObserver(token)
        timeObserverToken = nil
    }
}

private struct PhotosStyleSeekBar: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let isDarkBackground: Bool
    let onEditingChanged: (Bool) -> Void

    @State private var isDragging = false

    private let idleHeight: CGFloat = 6
    private let activeHeight: CGFloat = 12

    private var normalizedValue: Double {
        let lower = range.lowerBound
        let upper = range.upperBound
        let span = upper - lower
        guard span > 0 else { return 0 }
        let clampedValue = min(max(value, lower), upper)
        return (clampedValue - lower) / span
    }

    private var currentHeight: CGFloat { isDragging ? activeHeight : idleHeight }

    private var baseTrackColor: Color {
        if isDarkBackground {
            return Color.white.opacity(0.22)
        }
        return Color.black.opacity(0.15)
    }

    private var innerTrackColor: Color {
        if isDarkBackground {
            return Color.white.opacity(0.08)
        }
        return Color.black.opacity(0.05)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let progressWidth = max(CGFloat(normalizedValue) * width, currentHeight)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(baseTrackColor)

                Capsule()
                    .fill(innerTrackColor)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: progressWidth)
            }
            .frame(height: currentHeight)
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let newValue = mappedValue(for: gesture.location.x, width: width)
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        value = newValue
                    }
                    .onEnded { gesture in
                        let newValue = mappedValue(for: gesture.location.x, width: width)
                        value = newValue
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 44)
        .animation(.easeInOut(duration: 0.16), value: isDragging)
    }

    private func mappedValue(for locationX: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return value }
        let clampedX = min(max(locationX, 0), width)
        let ratio = Double(clampedX / width)
        let lower = range.lowerBound
        let upper = range.upperBound
        let span = upper - lower
        guard span > 0 else { return lower }
        return lower + (ratio * span)
    }
}

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVQueuePlayer
    let isDarkBackground: Bool

    func makeUIView(context: Context) -> PlayerLayerContainerView {
        let view = PlayerLayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.applyBackgroundColor(isDarkBackground: isDarkBackground)
        return view
    }

    func updateUIView(_ uiView: PlayerLayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        uiView.applyBackgroundColor(isDarkBackground: isDarkBackground)
    }
}

private final class PlayerLayerContainerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            fatalError("Unexpected layer type for PlayerLayerContainerView")
        }
        return layer
    }

    func applyBackgroundColor(isDarkBackground: Bool) {
        let color: UIColor = isDarkBackground ? .black : .white
        backgroundColor = color
        playerLayer.backgroundColor = color.cgColor
    }
}
