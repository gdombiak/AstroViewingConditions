import SharedCode
import SwiftUI
import UIKit

enum TargetImagePresentationAppearance {
    static let viewerUsesBlackBackground = true
    static let viewerOverridesContentColorScheme = false
    static let targetDetailsUsesSystemGroupedBackground = true
    static let viewerAttributionUsesGradient = true
    static let viewerAttributionUsesMaterialPanel = false
}

enum ZoomableImageInteractionPolicy {
    static let minimumZoomScale: CGFloat = 1
    static let maximumZoomScale: CGFloat = 6
    static let doubleTapZoomScale: CGFloat = 3
    static let supportsPanning = true
}

struct TargetImageViewerPresentationState {
    var image: ResolvedTargetImage?

    mutating func present(_ image: ResolvedTargetImage) {
        self.image = image
    }

    mutating func dismiss() {
        image = nil
    }
}

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = ZoomableImageInteractionPolicy.minimumZoomScale
        scrollView.maximumZoomScale = ZoomableImageInteractionPolicy.maximumZoomScale
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .black

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        imageView.addGestureRecognizer(doubleTap)
        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView
        context.coordinator.displayedImage = image
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        guard context.coordinator.displayedImage !== image else { return }
        context.coordinator.displayedImage = image
        context.coordinator.imageView?.image = image
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
        scrollView.setContentOffset(.zero, animated: false)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        var displayedImage: UIImage?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView, let imageView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let targetScale = min(
                    ZoomableImageInteractionPolicy.doubleTapZoomScale,
                    scrollView.maximumZoomScale
                )
                let point = recognizer.location(in: imageView)
                let size = CGSize(
                    width: scrollView.bounds.width / targetScale,
                    height: scrollView.bounds.height / targetScale
                )
                scrollView.zoom(to: CGRect(
                    x: point.x - size.width / 2,
                    y: point.y - size.height / 2,
                    width: size.width,
                    height: size.height
                ), animated: true)
            }
        }
    }
}

struct TargetImageViewer: View {
    @Environment(\.dismiss) private var dismiss
    let resolvedImage: ResolvedTargetImage
    let targetName: String

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                ZoomableImageView(image: resolvedImage.uiImage)
                    .ignoresSafeArea()
                    .accessibilityLabel("Zoomable image of \(targetName)")

                VStack(spacing: 0) {
                    topControls
                        .padding(.top, geometry.safeAreaInsets.top + 8)
                    Spacer(minLength: 0)
                    attributionOverlay
                        .padding(.bottom, geometry.safeAreaInsets.bottom)
                }
                .ignoresSafeArea()
            }
        }
    }

    private var topControls: some View {
        ZStack {
            Text(targetName)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 72)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("targetImageViewerDoneButton")
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 10)
        .background {
            LinearGradient(
                colors: [.black.opacity(0.75), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        }
    }

    private var attributionOverlay: some View {
        TargetImageAttributionView(info: resolvedImage.record, viewerOverlay: true)
            .padding(.horizontal, 20)
            .padding(.top, 42)
            .padding(.bottom, 12)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
            .background {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.88)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
    }
}
