//
//  ScanAnimationView.swift
//  DynamicNotch
//
//  Adapted from jonnyoo/glance (Glance Face ID animation).
//  Plays Apple's official Face ID scan animation video and holds its final frame.
//  Supports dynamic GPU tinting via CIColorMonochrome so any custom color can be used.
//

import SwiftUI
import AVFoundation
internal import AppKit
import CoreImage

enum ScanMedia: Equatable {
    case idle
    case success
    case failure
    
    var videoResourceName: String? {
        switch self {
        case .idle: return nil
        case .success: return "unlockanimation"
        case .failure: return "unsuccessfulunlockanimation"
        }
    }
}

struct ScanAnimationView: NSViewRepresentable {
    let media: ScanMedia
    var tintColor: Color? = nil
    
    func makeNSView(context: Context) -> ScanAnimationHostView {
        let view = ScanAnimationHostView()
        view.apply(media: media, tintColor: tintColor != nil ? NSColor(tintColor!) : nil)
        return view
    }
    
    func updateNSView(_ nsView: ScanAnimationHostView, context: Context) {
        nsView.apply(media: media, tintColor: tintColor != nil ? NSColor(tintColor!) : nil)
    }
}

final class ScanAnimationHostView: NSView {
    private var player: AVPlayer?
    private let playerLayer = AVPlayerLayer()
    private let stillImageLayer = CALayer()
    private var currentMedia: ScanMedia?
    private var currentTintColor: NSColor?
    private var readyObservation: NSKeyValueObservation?
    private var fallbackRevealWorkItem: DispatchWorkItem?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        
        stillImageLayer.contentsGravity = .resizeAspect
        if let still = Self.loadStillFromBundle() {
            stillImageLayer.contents = still
        }
        layer?.addSublayer(stillImageLayer)
        
        playerLayer.videoGravity = .resizeAspect
        playerLayer.isHidden = true
        layer?.addSublayer(playerLayer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        teardownPlayer()
    }
    
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        stillImageLayer.frame = bounds
        CATransaction.commit()
    }
    
    func apply(media: ScanMedia, tintColor: NSColor?) {
        let mediaChanged = (media != currentMedia)
        let tintChanged = (tintColor != currentTintColor)
        
        if tintChanged {
            currentTintColor = tintColor
            applyTint(tintColor)
        }
        
        guard mediaChanged else { return }
        currentMedia = media
        readyObservation = nil
        fallbackRevealWorkItem?.cancel()
        
        guard let resource = media.videoResourceName else {
            teardownPlayer()
            playerLayer.isHidden = true
            stillImageLayer.isHidden = false
            return
        }
        
        guard let url = Self.loadVideoURL(resource: resource) else {
            teardownPlayer()
            playerLayer.isHidden = true
            stillImageLayer.isHidden = false
            return
        }
        
        teardownPlayer()
        let newPlayer = AVPlayer(url: url)
        newPlayer.isMuted = true
        newPlayer.actionAtItemEnd = .none
        
        playerLayer.player = newPlayer
        player = newPlayer
        
        let reveal: () -> Void = { [weak self] in
            guard let self else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.playerLayer.isHidden = false
            self.stillImageLayer.isHidden = true
            CATransaction.commit()
        }
        
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] _, change in
            guard change.newValue == true else { return }
            DispatchQueue.main.async {
                self?.fallbackRevealWorkItem?.cancel()
                reveal()
                self?.readyObservation = nil
            }
        }
        
        let fallback = DispatchWorkItem { reveal() }
        fallbackRevealWorkItem = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: fallback)
        
        newPlayer.seek(to: .zero)
        newPlayer.play()
    }
    
    private func applyTint(_ tintColor: NSColor?) {
        guard let tintColor = tintColor,
              let srgb = tintColor.usingColorSpace(.sRGB),
              let filter = CIFilter(name: "CIColorMonochrome") else {
            stillImageLayer.filters = nil
            playerLayer.filters = nil
            return
        }
        
        let ciColor = CIColor(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent, alpha: 1.0)
        filter.setValue(ciColor, forKey: "inputColor")
        filter.setValue(1.0, forKey: "inputIntensity")
        
        stillImageLayer.filters = [filter]
        playerLayer.filters = [filter]
    }
    
    private func teardownPlayer() {
        readyObservation = nil
        fallbackRevealWorkItem?.cancel()
        player?.pause()
        player = nil
        playerLayer.player = nil
    }
    
    private static func loadStillFromBundle() -> NSImage? {
        let subdirectories = [nil, "FaceID", "Resources", "Resources/FaceID"]
        for subdirectory in subdirectories {
            if let url = Bundle.main.url(
                forResource: "unlockstatic",
                withExtension: "png",
                subdirectory: subdirectory
            ) {
                return NSImage(contentsOf: url)
            }
        }
        return nil
    }
    
    private static func loadVideoURL(resource: String) -> URL? {
        let subdirectories = [nil, "FaceID", "Resources", "Resources/FaceID"]
        for subdirectory in subdirectories {
            if let url = Bundle.main.url(
                forResource: resource,
                withExtension: "mp4",
                subdirectory: subdirectory
            ) {
                return url
            }
        }
        return nil
    }
}
