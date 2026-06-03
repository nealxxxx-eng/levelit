import SwiftUI
import AVFoundation
import LevelItShared

struct ScanView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraManager()
    @State private var isAnalyzing = false
    @State private var cameraPermissionDenied = false
    @State private var analysisError: String?
    @State private var capturedThumbnail: UIImage?
    @State private var showAnalysisCard = false
    @State private var shutterFlash = false
    @State private var scanLineActive = false
    @State private var analysisStep = "正在识别食物"

    var onResult: (FoodAnalysisResult) -> Void

    var body: some View {
        ZStack {
            if cameraPermissionDenied {
                permissionDeniedView
            } else {
                cameraView
            }
        }
        .alert("识别失败", isPresented: .init(
            get: { analysisError != nil },
            set: { if !$0 { analysisError = nil } }
        )) {
            Button("重试") { Task { await captureAndAnalyze() } }
            Button("手动选择") {
                camera.stop()
                dismiss()
            }
        } message: {
            Text(analysisError ?? "")
        }
        .navigationTitle("磨平镜头")
        .navigationBarTitleDisplayMode(.inline)
        .task { await checkPermission() }
        .onDisappear { camera.stop() }
    }

    // MARK: - Camera View

    private var cameraView: some View {
        GeometryReader { proxy in
            let lensHeight = max(330, min(proxy.size.height * 0.58, 520))

            VStack(spacing: DS.Spacing.md) {
                scanHeader
                lensFrame(height: lensHeight)
                captureControls
                uploadNotice
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(cameraBackground)
    }

    private var cameraBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.08, blue: 0.05),
                    Color(red: 0.22, green: 0.10, blue: 0.04),
                    Color(red: 0.04, green: 0.04, blue: 0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.orange.opacity(0.22))
                .frame(width: 260, height: 260)
                .blur(radius: 42)
                .offset(x: -130, y: -180)

            Circle()
                .fill(Color.yellow.opacity(0.13))
                .frame(width: 220, height: 220)
                .blur(radius: 48)
                .offset(x: 150, y: 260)
        }
    }

    private var scanHeader: some View {
        HStack(spacing: DS.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(.white.opacity(0.14))
                    .frame(width: 52, height: 52)
                Image(systemName: "camera.aperture")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("把食物放上能量秤")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text("拍下加餐、饮料或正餐，稍后会自动接入今日磨平")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(2)
            }

            Spacer()
        }
    }

    private func lensFrame(height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.black)

            CameraPreview(session: camera.session)
                .opacity(showAnalysisCard ? 0.72 : 1)

            if !camera.isReady {
                Color.black
                VStack(spacing: DS.Spacing.sm) {
                    ProgressView()
                        .tint(.white)
                    Text("正在打开镜头")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }

            lensGuides

            if shutterFlash {
                Color.white
                    .opacity(0.78)
                    .transition(.opacity)
            }

            if let thumb = capturedThumbnail, showAnalysisCard {
                analysisCard(photo: thumb)
                    .padding(.horizontal, DS.Spacing.lg)
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.55), .orange.opacity(0.65), .white.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        }
        .shadow(color: Color.orange.opacity(0.22), radius: 28, y: 18)
        .scaleEffect(shutterFlash ? 0.985 : 1)
    }

    private var lensGuides: some View {
        ZStack {
            VStack {
                HStack {
                    guideCorner(rotation: 0)
                    Spacer()
                    guideCorner(rotation: 90)
                }
                Spacer()
                HStack {
                    guideCorner(rotation: -90)
                    Spacer()
                    guideCorner(rotation: 180)
                }
            }
            .padding(22)

            VStack(spacing: DS.Spacing.sm) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text(isAnalyzing ? "AI 正在分析这口能量" : "尽量让食物位于光圈中心")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.34))
                .clipShape(Capsule())

                Spacer()

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [7, 9]))
                    .frame(width: 230, height: 150)

                Spacer()
            }
            .padding(.vertical, 18)
        }
        .allowsHitTesting(false)
    }

    private func guideCorner(rotation: Double) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: 3,
            bottomTrailingRadius: 3,
            topTrailingRadius: 3,
            style: .continuous
        )
        .trim(from: 0, to: 0.36)
        .stroke(.white.opacity(0.86), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        .frame(width: 52, height: 52)
        .rotationEffect(.degrees(rotation))
    }

    private func analysisCard(photo: UIImage) -> some View {
        VStack(spacing: DS.Spacing.md) {
            ZStack {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                LinearGradient(
                    colors: [.clear, .black.opacity(0.58)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.88), .orange.opacity(0.45), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 4)
                    .blur(radius: 0.5)
                    .offset(y: scanLineActive ? 58 : -58)

                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "sparkles")
                        Text("AI 能量读取中")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.42))
                    .clipShape(Capsule())
                    .padding(.bottom, 12)
                }
            }

            VStack(spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    ProgressView()
                        .tint(.orange)
                    Text(analysisStep)
                        .font(.headline.weight(.semibold))
                }
                .foregroundStyle(.primary)

                HStack(spacing: DS.Spacing.sm) {
                    analysisStepPill("识别食物")
                    analysisStepPill("估算热量")
                    analysisStepPill("磨平方案")
                }
            }
        }
        .padding(DS.Spacing.md)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.32), lineWidth: 1)
        }
    }

    private func analysisStepPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.06))
            .clipShape(Capsule())
    }

    private var captureControls: some View {
        HStack(spacing: DS.Spacing.xl) {
            Button {
                camera.stop()
                dismiss()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.bold))
                    Text("取消")
                        .font(.caption)
                }
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 72)
            }

            Spacer()

            Button {
                Task { await captureAndAnalyze() }
            } label: {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.28), lineWidth: 5)
                        .frame(width: 86, height: 86)
                    Circle()
                        .fill(.white)
                        .frame(width: 70, height: 70)
                    Circle()
                        .fill(Color.orange.opacity(isAnalyzing ? 0.35 : 0.9))
                        .frame(width: 52, height: 52)
                    if isAnalyzing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .disabled(isAnalyzing || !camera.isReady)
            .scaleEffect(isAnalyzing ? 0.94 : 1)

            Spacer()

            Button {
                camera.stop()
                dismiss()
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2")
                        .font(.headline.weight(.bold))
                    Text("手选")
                        .font(.caption)
                }
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 72)
            }
        }
    }

    private var uploadNotice: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.orange)
            Text("照片会用于 AI 热量分析，可能按隐私政策保存用于后续改进")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
    }

    // MARK: - Permission Denied

    private var permissionDeniedView: some View {
        VStack(spacing: DS.Spacing.lg) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("需要相机权限才能拍照")
                .font(.headline)

            Button("前往设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)

            Button("手动选一个") {
                dismiss()
            }
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Logic

    private func checkPermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                camera.setup()
            } else {
                cameraPermissionDenied = true
            }
        case .denied, .restricted:
            cameraPermissionDenied = true
        case .authorized:
            camera.setup()
        @unknown default:
            break
        }
    }

    private func captureAndAnalyze() async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        analysisError = nil
        analysisStep = "正在捕捉画面"
        scanLineActive = false

        // 拍照
        guard let photo = await camera.takePhoto() else {
            isAnalyzing = false
            analysisError = "拍照失败，请重试"
            return
        }

        // 保持相机预览稳定，只把照片收纳成分析卡，避免全屏裁切变化造成画面侧移。
        capturedThumbnail = photo
        analysisStep = "正在询问 AI 估算热量"
        withAnimation(.easeOut(duration: 0.08)) { shutterFlash = true }
        try? await Task.sleep(for: .milliseconds(90))
        withAnimation(.easeIn(duration: 0.18)) { shutterFlash = false }
        withAnimation(.spring(response: 0.46, dampingFraction: 0.82)) {
            showAnalysisCard = true
        }
        withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: false)) {
            scanLineActive = true
        }

        // AI 识别
        do {
            let aiResult = try await FoodAnalysisService.analyze(image: photo)
            analysisStep = "磨平方案已生成"
            let result = FoodAnalysisResult(
                foodName: aiResult.foodName,
                foodEmoji: aiResult.foodEmoji,
                estimatedCalories: aiResult.estimatedCalories,
                imageData: photo.jpegData(compressionQuality: 0.8)
            )
            try? await Task.sleep(for: .milliseconds(420))
            isAnalyzing = false

            camera.stop()
            onResult(result)
        } catch {
            isAnalyzing = false
            capturedThumbnail = nil
            showAnalysisCard = false
            scanLineActive = false
            analysisError = error.localizedDescription
        }
    }
}
