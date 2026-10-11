//
//  FaceIDNotchView.swift
//  DynamicNotch
//

import SwiftUI

struct FaceIDNotchView: View {
    @Environment(\.isNotchlessScreen) private var isNotchlessScreen
    @ObservedObject var service: FaceIDService = .shared
    
    // Animation states
    @State private var frameExpandProgress: CGFloat = 0.7
    @State private var frameOpacity: Double = 0.0
    @State private var faceFeaturesProgress: CGFloat = 0.0
    @State private var faceOpacity: Double = 0.0
    @State private var faceScale: CGFloat = 0.75
    
    @State private var eyeLookOffset: CGFloat = 0.0
    @State private var isBlinking: Bool = false
    @State private var isBreathing: Bool = false
    @State private var scanBeamOffset: CGFloat = -26.0
    
    @State private var checkmarkProgress: CGFloat = 0.0
    @State private var checkmarkScale: CGFloat = 0.6
    @State private var successBounce: CGFloat = 1.0
    @State private var shakeOffset: CGFloat = 0.0
    
    @State private var blinkTimer: Timer?

    private let glyphSize: CGFloat = 86

    var body: some View {
        VStack {
            Spacer()

            ZStack {
                // 1. Рамка видоискателя (4 уголка)
                FaceIDCornerBracketsShape()
                    .stroke(
                        headlineColor,
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: glyphSize, height: glyphSize)
                    .scaleEffect(frameExpandProgress)
                    .opacity(frameOpacity)

                // 2. Черты лица (морфятся при сканировании)
                if !service.state.isSuccess {
                    faceElementsView
                        .opacity(faceOpacity)
                        .scaleEffect(faceScale)
                }

                // 3. Лазерная световая полоса сканирования
                if service.state.isScanning {
                    scanLaserBeam
                }

                // 4. Зеленая галочка при успешной разблокировке
                if service.state.isSuccess {
                    FaceIDCheckmarkShape()
                        .trim(from: 0, to: checkmarkProgress)
                        .stroke(
                            Color.green,
                            style: StrokeStyle(lineWidth: 4.2, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 44, height: 44)
                        .scaleEffect(checkmarkScale)
                }
            }
            .scaleEffect(successBounce * (isBreathing ? 1.03 : 0.97))
            .offset(x: shakeOffset)
            
            Spacer()
        }
        .onAppear {
            startMorphAnimation()
        }
        .onDisappear {
            blinkTimer?.invalidate()
            blinkTimer = nil
        }
        .onChange(of: service.state) { _, newState in
            handleStateChange(newState)
        }
    }

    // MARK: - Face Elements

    private var faceElementsView: some View {
        ZStack {
            // Глаза
            HStack(spacing: 20) {
                Capsule()
                    .fill(headlineColor)
                    .frame(width: 4.5, height: isBlinking ? 2.0 : 11.0)

                Capsule()
                    .fill(headlineColor)
                    .frame(width: 4.5, height: isBlinking ? 2.0 : 11.0)
            }
            .offset(x: eyeLookOffset, y: -6)

            // Нос
            FaceIDNoseShape()
                .trim(from: 0, to: faceFeaturesProgress)
                .stroke(
                    headlineColor,
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                )
                .frame(width: glyphSize, height: glyphSize)

            // Улыбка / Рот
            FaceIDMouthShape()
                .trim(from: 0, to: faceFeaturesProgress)
                .stroke(
                    headlineColor,
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                )
                .frame(width: glyphSize, height: glyphSize)
        }
    }

    // MARK: - Scanning Laser Beam

    private var scanLaserBeam: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        headlineColor.opacity(0.0),
                        headlineColor.opacity(0.65),
                        headlineColor.opacity(0.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: glyphSize * 0.72, height: 2)
            .offset(y: scanBeamOffset)
            .blur(radius: 0.8)
    }

    // MARK: - Animations

    private func startMorphAnimation() {
        // Фаза 1: Плавное раздвигание 4-х уголков рамки
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
            frameExpandProgress = 1.0
            frameOpacity = 1.0
        }

        // Фаза 2: Превращение в лицо (прорисовка черт лица)
        withAnimation(.easeOut(duration: 0.45).delay(0.12)) {
            faceFeaturesProgress = 1.0
            faceOpacity = 1.0
            faceScale = 1.0
        }

        // Фаза 3: Дыхание рамки и движение глаз (поиск лица)
        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true).delay(0.2)) {
            isBreathing = true
            eyeLookOffset = 2.6
        }

        // Световой луч сканирования
        withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true).delay(0.25)) {
            scanBeamOffset = 26.0
        }

        // Периодическое моргание глаз
        scheduleBlinking()
    }

    private func scheduleBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 2.2, repeats: true) { _ in
            Task { @MainActor in
                guard !service.state.isSuccess && !service.state.isFailed else { return }
                withAnimation(.easeInOut(duration: 0.12)) {
                    isBlinking = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isBlinking = false
                    }
                }
            }
        }
    }

    private func handleStateChange(_ state: FaceIDState) {
        if state.isSuccess {
            blinkTimer?.invalidate()
            blinkTimer = nil

            // 1. Лицо плавно растворяется и сжимается
            withAnimation(.easeInOut(duration: 0.2)) {
                faceOpacity = 0.0
                faceScale = 0.6
                isBreathing = false
            }

            // 2. Динамически вырисовывается галочка с пружинящим отскоком
            withAnimation(.spring(response: 0.38, dampingFraction: 0.65).delay(0.08)) {
                checkmarkProgress = 1.0
                checkmarkScale = 1.0
                successBounce = 1.08
            }

            // 3. Возврат к нормальному размеру
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                withAnimation(.easeOut(duration: 0.2)) {
                    successBounce = 1.0
                }
            }
        } else if state.isFailed {
            blinkTimer?.invalidate()
            blinkTimer = nil
            isBreathing = false

            // Эффект покачивания (shake) при ошибке
            triggerShakeAnimation()
        }
    }

    private func triggerShakeAnimation() {
        let offsets: [CGFloat] = [-8, 8, -6, 6, -3, 3, 0]
        for (index, offset) in offsets.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.06) {
                withAnimation(.easeInOut(duration: 0.06)) {
                    self.shakeOffset = offset
                }
            }
        }
    }

    private var headlineColor: Color {
        switch service.state {
        case .searching, .scanning, .success:
            return .green
        case .failed:
            return .red
        default:
            return .green
        }
    }
}

// MARK: - Shapes

/// 4 закругленных уголка видоискателя Face ID
struct FaceIDCornerBracketsShape: Shape {
    var cornerLengthRatio: CGFloat = 0.22
    var cornerRadiusRatio: CGFloat = 0.18

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let l = w * cornerLengthRatio
        let r = w * cornerRadiusRatio

        // Верхний левый
        path.move(to: CGPoint(x: 0, y: l))
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: l, y: 0))

        // Верхний правый
        path.move(to: CGPoint(x: w - l, y: 0))
        path.addLine(to: CGPoint(x: w - r, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: r), control: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: w, y: l))

        // Нижний правый
        path.move(to: CGPoint(x: w, y: h - l))
        path.addLine(to: CGPoint(x: w, y: h - r))
        path.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: w - l, y: h))

        // Нижний левый
        path.move(to: CGPoint(x: l, y: h))
        path.addLine(to: CGPoint(x: r, y: h))
        path.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: 0, y: h - l))

        return path
    }
}

/// Нос как в оригинальном глифе Face ID
struct FaceIDNoseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        let topY = rect.height * 0.43
        let bottomY = rect.height * 0.60
        let hookX = midX + rect.width * 0.08

        path.move(to: CGPoint(x: midX, y: topY))
        path.addLine(to: CGPoint(x: midX, y: bottomY))
        path.addLine(to: CGPoint(x: hookX, y: bottomY))
        return path
    }
}

/// Улыбка / Рот как в оригинальном глифе Face ID
struct FaceIDMouthShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let startX = rect.width * 0.31
        let endX = rect.width * 0.69
        let y = rect.height * 0.73
        let controlY = rect.height * 0.85

        path.move(to: CGPoint(x: startX, y: y))
        path.addQuadCurve(
            to: CGPoint(x: endX, y: y),
            control: CGPoint(x: rect.midX, y: controlY)
        )
        return path
    }
}

/// Вырисовывающаяся галочка успеха Face ID
struct FaceIDCheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: w * 0.16, y: h * 0.52))
        path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.78))
        path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.22))
        return path
    }
}
