import SwiftUI
internal import AppKit

struct LightweightNowPlayingEqualizerView: NSViewRepresentable {
    let isPlaying: Bool
    let colors: [NSColor]
    let barHeight: CGFloat
    let barWidth: CGFloat
    let cornerRadius: CGFloat?

    init(isPlaying: Bool, colors: [NSColor], barHeight: CGFloat = 16, barWidth: CGFloat = 2, cornerRadius: CGFloat? = nil) {
        self.isPlaying = isPlaying
        self.colors = colors
        self.barHeight = barHeight
        self.barWidth = barWidth
        self.cornerRadius = cornerRadius
    }

    init(isPlaying: Bool, color: NSColor, barHeight: CGFloat = 16, barWidth: CGFloat = 2, cornerRadius: CGFloat? = nil) {
        self.isPlaying = isPlaying
        self.colors = [color]
        self.barHeight = barHeight
        self.barWidth = barWidth
        self.cornerRadius = cornerRadius
    }

    func makeNSView(context: Context) -> LightweightNowPlayingEqualizerNSView {
        let view = LightweightNowPlayingEqualizerNSView()
        view.setBarHeight(barHeight)
        view.setBarWidth(barWidth)
        view.setCornerRadius(cornerRadius)
        view.setColors(colors)
        view.setPlaying(isPlaying)
        return view
    }
    
    func updateNSView(_ nsView: LightweightNowPlayingEqualizerNSView, context: Context) {
        nsView.setBarHeight(barHeight)
        nsView.setBarWidth(barWidth)
        nsView.setCornerRadius(cornerRadius)
        nsView.setColors(colors)
        nsView.setPlaying(isPlaying)
    }
    
    static func dismantleNSView(_ nsView: LightweightNowPlayingEqualizerNSView, coordinator: ()) {
        nsView.stop()
    }
}

final class LightweightNowPlayingEqualizerNSView: NSView {
    private enum Metrics {
        static let barCount = 6
        static let defaultBarWidth: CGFloat = 2
        static let barSpacing: CGFloat = 1.8
        static let defaultHeight: CGFloat = 16
        static let minimumScale: CGFloat = 0.32
        static let baseDuration: TimeInterval = 1.2
        static let transitionDuration: TimeInterval = 0.2
    }
    
    private let gradientLayer = CAGradientLayer()
    private let maskContainerLayer = CALayer()
    private var barLayers: [CALayer] = []
    private var isAnimating = false
    private var isPlaying = false
    private var barColors: [NSColor] = [.white]
    private var barHeight = Metrics.defaultHeight
    private var barWidth = Metrics.defaultBarWidth
    private var customCornerRadius: CGFloat?
    private var windowObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isScreenAsleep = false
    
    override var intrinsicContentSize: NSSize {
        NSSize(width: CGFloat(Metrics.barCount) * barWidth + CGFloat(Metrics.barCount - 1) * Metrics.barSpacing, height: barHeight)
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    deinit {
        removeWorkspaceObservers()
        removeWindowObservers()
        stop()
    }
    
    override func layout() {
        super.layout()
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        maskContainerLayer.frame = bounds
        CATransaction.commit()
        
        layoutBars()
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindowObservers()
        syncAnimationState()
    }
    
    func setPlaying(_ playing: Bool) {
        guard isPlaying != playing else { return }
        
        isPlaying = playing
        syncAnimationState()
    }
    
    func setColor(_ color: NSColor) {
        setColors([color])
    }
    
    func setColors(_ colors: [NSColor]) {
        guard barColors.count != colors.count || zip(barColors, colors).contains(where: { !$0.0.isEqual($0.1) }) else { return }
        barColors = colors
        
        let cgColors: [CGColor]
        if colors.isEmpty {
            cgColors = [NSColor.white.cgColor, NSColor.white.cgColor]
        } else if colors.count == 1 {
            cgColors = [colors[0].cgColor, colors[0].cgColor]
        } else {
            cgColors = colors.map { $0.cgColor }
        }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.colors = cgColors
        CATransaction.commit()
    }
    
    func setBarHeight(_ height: CGFloat) {
        let resolvedHeight = max(height, barWidth)
        guard abs(barHeight - resolvedHeight) > 0.001 else { return }
        
        barHeight = resolvedHeight
        invalidateIntrinsicContentSize()
        layoutBars()
        
        if isAnimating {
            restartWaveAnimations()
        } else if !isPlaying {
            resetBars()
        }
    }
    
    func setCornerRadius(_ radius: CGFloat?) {
        guard customCornerRadius != radius else { return }
        customCornerRadius = radius
        updateBarCornerRadius()
    }
    
    func setBarWidth(_ width: CGFloat) {
        let resolvedWidth = max(width, 1)
        guard abs(barWidth - resolvedWidth) > 0.001 else { return }
        
        barWidth = resolvedWidth
        updateBarCornerRadius()
        invalidateIntrinsicContentSize()
        layoutBars()
        
        if isAnimating {
            restartWaveAnimations()
        } else if !isPlaying {
            resetBars()
        }
    }
    
    private func updateBarCornerRadius() {
        if isPlaying {
            let resolvedRadius = customCornerRadius ?? (barWidth / 2.0)
            barLayers.forEach {
                $0.cornerRadius = resolvedRadius
                $0.cornerCurve = .continuous
            }
        } else {
            let dotRadius = barWidth / 2.0
            barLayers.forEach {
                $0.cornerRadius = dotRadius
                $0.cornerCurve = .circular
            }
        }
    }
    
    func stop(animated: Bool = false) {
        guard isAnimating || isPlaying else {
            resetBars(animated: animated)
            return
        }
        isAnimating = false
        resetBars(animated: animated)
    }
}

private extension LightweightNowPlayingEqualizerNSView {
    private struct BarWaveProfile {
        let durationMultiplier: Double
        let values: [CGFloat]
        
        var keyTimes: [NSNumber] {
            let count = values.count
            guard count > 1 else { return [0.0, 1.0] }
            return (0..<count).map {
                NSNumber(value: Double($0) / Double(count - 1))
            }
        }
    }
    
    private static let barProfiles: [BarWaveProfile] = [
        // Bar 0: duration = 0.32 * 1.15 ≈ 0.368s
        BarWaveProfile(
            durationMultiplier: 1.15,
            values: [0.10, 0.85, 0.25, 0.98, 0.15, 0.70, 0.10]
        ),
        // Bar 1: duration = 0.32 * 0.88 ≈ 0.282s
        BarWaveProfile(
            durationMultiplier: 0.88,
            values: [0.30, 0.95, 0.12, 0.65, 0.40, 1.00, 0.30]
        ),
        // Bar 2: duration = 0.32 * 1.28 ≈ 0.410s
        BarWaveProfile(
            durationMultiplier: 1.28,
            values: [0.08, 0.75, 0.35, 1.00, 0.20, 0.60, 0.40, 0.90, 0.08]
        ),
        // Bar 3: duration = 0.32 * 0.98 ≈ 0.314s
        BarWaveProfile(
            durationMultiplier: 0.98,
            values: [0.22, 0.98, 0.18, 0.70, 0.35, 0.85, 0.22]
        ),
        // Bar 4: duration = 0.32 * 0.78 ≈ 0.250s
        BarWaveProfile(
            durationMultiplier: 0.78,
            values: [0.15, 0.80, 0.10, 0.95, 0.30, 0.65, 0.15]
        ),
        // Bar 5: duration = 0.32 * 1.08 ≈ 0.346s
        BarWaveProfile(
            durationMultiplier: 1.08,
            values: [0.12, 0.65, 0.38, 0.92, 0.10, 0.80, 0.45, 0.98, 0.12]
        )
    ]
    
    func setup() {
        wantsLayer = true
        layer?.masksToBounds = false
        
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(gradientLayer)
        
        maskContainerLayer.frame = bounds
        gradientLayer.mask = maskContainerLayer
        
        createBars()
        configureWorkspaceObservers()
    }
    
    func createBars() {
        guard barLayers.isEmpty else { return }
        
        for _ in 0..<Metrics.barCount {
            let barLayer = CALayer()
            barLayer.backgroundColor = NSColor.white.cgColor
            barLayer.masksToBounds = true
            barLayer.allowsGroupOpacity = false
            barLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            maskContainerLayer.addSublayer(barLayer)
            barLayers.append(barLayer)
        }
        
        updateBarCornerRadius()
        layoutBars()
    }
    
    func layoutBars() {
        guard !barLayers.isEmpty else { return }
        
        let totalWidth = intrinsicContentSize.width
        let originX = max((bounds.width - totalWidth) / 2, 0)
        let centerY = bounds.midY
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        if isPlaying {
            let resolvedRadius = customCornerRadius ?? (barWidth / 2.0)
            for (index, barLayer) in barLayers.enumerated() {
                let x = originX + CGFloat(index) * (barWidth + Metrics.barSpacing)
                barLayer.bounds = CGRect(
                    x: 0,
                    y: 0,
                    width: barWidth,
                    height: barHeight
                )
                barLayer.position = CGPoint(x: x + barWidth / 2, y: centerY)
                barLayer.cornerRadius = resolvedRadius
                barLayer.cornerCurve = .continuous
                if !isAnimating {
                    barLayer.transform = CATransform3DIdentity
                }
            }
        } else {
            let dotSize = barWidth
            for (index, barLayer) in barLayers.enumerated() {
                let x = originX + CGFloat(index) * (barWidth + Metrics.barSpacing)
                barLayer.bounds = CGRect(
                    x: 0,
                    y: 0,
                    width: dotSize,
                    height: dotSize
                )
                barLayer.position = CGPoint(x: x + barWidth / 2, y: centerY)
                barLayer.cornerRadius = dotSize / 2.0
                barLayer.cornerCurve = .circular
                barLayer.transform = CATransform3DIdentity
            }
        }
        
        CATransaction.commit()
    }
    
    func syncAnimationState() {
        guard isInVisibleWindow, isPlaying else {
            stop(animated: true)
            return
        }
        
        start()
    }
    
    func start() {
        guard !isAnimating else { return }
        isAnimating = true
        
        let resolvedRadius = customCornerRadius ?? (barWidth / 2.0)
        let minScale = minimumPlayingScale
        
        CATransaction.begin()
        CATransaction.setAnimationDuration(Metrics.transitionDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        
        for (index, barLayer) in barLayers.enumerated() {
            barLayer.bounds = CGRect(x: 0, y: 0, width: barWidth, height: barHeight)
            barLayer.cornerRadius = resolvedRadius
            barLayer.cornerCurve = .continuous
            barLayer.transform = CATransform3DIdentity
            
            let animation = makeWaveAnimation(forBarIndex: index, minScale: minScale, layer: barLayer)
            barLayer.add(animation, forKey: "dynamicNotch.scaleY")
        }
        
        CATransaction.commit()
    }
    
    func restartWaveAnimations() {
        guard isAnimating else { return }
        let minScale = minimumPlayingScale
        for (index, barLayer) in barLayers.enumerated() {
            let animation = makeWaveAnimation(forBarIndex: index, minScale: minScale, layer: barLayer)
            barLayer.add(animation, forKey: "dynamicNotch.scaleY")
        }
    }
    
    func resetBars(animated: Bool = false) {
        let dotSize = barWidth
        let dotRadius = dotSize / 2.0
        
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(Metrics.transitionDuration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        
        for barLayer in barLayers {
            let currentScale: CGFloat
            if animated, let presentation = barLayer.presentation() {
                currentScale = (presentation.value(forKeyPath: "transform.scale.y") as? CGFloat) ?? 1.0
            } else {
                currentScale = 1.0
            }
            
            barLayer.removeAnimation(forKey: "dynamicNotch.scaleY")
            
            if animated && abs(currentScale - 1.0) > 0.01 {
                let shrinkAnim = CABasicAnimation(keyPath: "transform.scale.y")
                shrinkAnim.fromValue = currentScale
                shrinkAnim.toValue = 1.0
                shrinkAnim.duration = Metrics.transitionDuration
                shrinkAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                barLayer.add(shrinkAnim, forKey: "dynamicNotch.scaleY")
            }
            
            barLayer.transform = CATransform3DIdentity
            barLayer.bounds = CGRect(x: 0, y: 0, width: dotSize, height: dotSize)
            barLayer.cornerRadius = dotRadius
            barLayer.cornerCurve = .circular
        }
        
        CATransaction.commit()
    }
    
    func makeWaveAnimation(forBarIndex index: Int, minScale: CGFloat, layer: CALayer) -> CAKeyframeAnimation {
        let profile = Self.barProfiles[index % Self.barProfiles.count]
        let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
        let scaleRange = max(1.0 - minScale, 0.05)
        
        animation.values = profile.values.map { norm in
            let scale = minScale + scaleRange * norm
            return NSNumber(value: Double(scale))
        }
        animation.keyTimes = profile.keyTimes
        animation.calculationMode = .cubic
        animation.duration = Metrics.baseDuration * profile.durationMultiplier
        animation.repeatCount = .greatestFiniteMagnitude
        animation.isRemovedOnCompletion = false
        
        let currentTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        animation.beginTime = currentTime - Double(index) * 0.07
        
        if #available(macOS 13.0, *) {
            let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            animation.preferredFrameRateRange = CAFrameRateRange(
                minimum: 30,
                maximum: isLowPower ? 60 : 120,
                preferred: isLowPower ? 30 : 60
            )
        }
        
        return animation
    }
    
    var pausedScale: CGFloat {
        min(max(barWidth / max(barHeight, 1), 0.001), 1)
    }
    
    var minimumPlayingScale: CGFloat {
        let minHeightScale = (barWidth * 1.5) / max(barHeight, 1)
        return min(max(Metrics.minimumScale, minHeightScale), 0.95)
    }
    
    var isInVisibleWindow: Bool {
        guard !isScreenAsleep else { return false }
        guard let window, window.isVisible else { return false }
        return window.occlusionState.contains(.visible)
    }
    
    func configureWindowObservers() {
        removeWindowObservers()
        
        guard let window else { return }
        
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.willCloseNotification
        ]
        
        windowObservers = names.map { name in
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.syncAnimationState()
            }
        }
    }
    
    func removeWindowObservers() {
        let center = NotificationCenter.default
        windowObservers.forEach(center.removeObserver)
        windowObservers.removeAll()
    }
    
    func configureWorkspaceObservers() {
        removeWorkspaceObservers()
        
        let wsCenter = NSWorkspace.shared.notificationCenter
        let sleepObs = wsCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isScreenAsleep = true
            self?.syncAnimationState()
        }
        let wakeObs = wsCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isScreenAsleep = false
            self?.syncAnimationState()
        }
        let powerObs = NotificationCenter.default.addObserver(forName: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.restartWaveAnimations()
        }
        
        workspaceObservers = [sleepObs, wakeObs, powerObs]
    }
    
    func removeWorkspaceObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { obs in
            wsCenter.removeObserver(obs)
            NotificationCenter.default.removeObserver(obs)
        }
        workspaceObservers.removeAll()
    }
}
