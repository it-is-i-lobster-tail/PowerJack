import SwiftUI
import UIKit

struct StudyFullscreenView: View {
    let study: StudyResult
    let title: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zoom = StudyZoomControls()

    var body: some View {
        ExpandedChartPresentation(title: title, close: { dismiss() }) {
            Menu {
                Button("Zoom in", systemImage: "plus.magnifyingglass") { zoom.change(by: 2, animated: !reduceMotion) }
                Button("Zoom out", systemImage: "minus.magnifyingglass") { zoom.change(by: 0.5, animated: !reduceMotion) }
                Button("Reset zoom", systemImage: "arrow.counterclockwise") { zoom.reset(animated: !reduceMotion) }
            } label: {
                Image(systemName: "magnifyingglass")
                    .frame(width: 38, height: 38)
                    .powerJackGlassCircle()
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Zoom")
        } content: {
            VStack(spacing: 0) {
                StudyZoomView(study: study, zoom: zoom)
                    .modifier(ExportableChart())
                StudyReadingGuide(study: study)
            }
        }
    }
}

@MainActor
private final class StudyZoomControls {
    weak var scrollView: UIScrollView?

    func change(by factor: CGFloat, animated: Bool) {
        guard let scroll = scrollView else { return }
        let next = min(scroll.maximumZoomScale, max(scroll.minimumZoomScale, scroll.zoomScale * factor))
        let visible = scroll.bounds
        let center = CGPoint(x: visible.midX / scroll.zoomScale, y: visible.midY / scroll.zoomScale)
        let size = CGSize(width: visible.width / next, height: visible.height / next)
        scroll.zoom(
            to: CGRect(
                x: center.x - size.width / 2, y: center.y - size.height / 2,
                width: size.width, height: size.height), animated: animated)
    }

    func reset(animated: Bool) {
        guard let scroll = scrollView else { return }
        scroll.setZoomScale(scroll.minimumZoomScale, animated: animated)
    }
}

/// The scroll view owns both gestures. Its zoom target is the complete chart in native points,
/// including parts of a wide table or tall set of lift panels that start outside the viewport.
private struct StudyZoomView: UIViewControllerRepresentable {
    let study: StudyResult
    let zoom: StudyZoomControls

    func makeUIViewController(context: Context) -> StudyZoomController {
        let controller = StudyZoomController(study: study, dynamicType: context.environment.dynamicTypeSize)
        zoom.scrollView = controller.scroll
        return controller
    }

    func updateUIViewController(_ controller: StudyZoomController, context: Context) {
        controller.update(study: study, dynamicType: context.environment.dynamicTypeSize)
    }
}

@MainActor
private final class StudyZoomController: UIViewController, UIScrollViewDelegate {
    let scroll = UIScrollView()
    private let host: UIHostingController<StudyFullscreenCanvas>
    private var study: StudyResult
    private var dynamicType: DynamicTypeSize
    private var previousViewport = CGSize.zero
    private var needsMeasurement = true

    init(study: StudyResult, dynamicType: DynamicTypeSize) {
        self.study = study
        self.dynamicType = dynamicType
        host = UIHostingController(
            rootView: StudyFullscreenCanvas(
                study: study, viewport: .zero, dynamicType: dynamicType))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() { view = scroll }

    override func viewDidLoad() {
        super.viewDidLoad()
        scroll.delegate = self
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.accessibilityIdentifier = "data.fullscreen.canvas"

        addChild(host)
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        scroll.addSubview(host.view)
        host.didMove(toParent: self)
    }

    func update(study: StudyResult, dynamicType: DynamicTypeSize) {
        guard self.study != study || self.dynamicType != dynamicType else { return }
        self.study = study
        self.dynamicType = dynamicType
        needsMeasurement = true
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let viewport = scroll.bounds.size
        guard viewport.width > 0, viewport.height > 0, needsMeasurement || viewport != previousViewport else { return }
        needsMeasurement = false

        // Preserve scroll progress on rotation, including the leading edge of a chart first opened in portrait.
        let oldSize = scroll.contentSize
        let previousOffset = scroll.contentOffset
        let viewportChanged = previousViewport != viewport
        let progress = CGPoint(
            x: min(1, max(0, scroll.contentOffset.x / max(1, oldSize.width - previousViewport.width))),
            y: min(1, max(0, scroll.contentOffset.y / max(1, oldSize.height - previousViewport.height))))
        previousViewport = viewport
        let scale = scroll.zoomScale
        scroll.setZoomScale(1, animated: false)

        let canvas = StudyFullscreenCanvas(study: study, viewport: viewport, dynamicType: dynamicType)
        host.rootView = canvas
        let width = canvas.contentWidth
        let measured = host.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        let size = CGSize(width: width, height: max(viewport.height, ceil(measured.height)))
        host.view.frame = CGRect(origin: .zero, size: size)
        scroll.contentSize = size
        scroll.setZoomScale(scale, animated: false)
        let maxX = max(0, scroll.contentSize.width - viewport.width)
        let maxY = max(0, scroll.contentSize.height - viewport.height)
        let x = viewportChanged ? progress.x * maxX : min(maxX, max(0, previousOffset.x))
        let y = viewportChanged ? progress.y * maxY : min(maxY, max(0, previousOffset.y))
        scroll.setContentOffset(CGPoint(x: x, y: y), animated: false)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { host.view }
}

private struct StudyFullscreenCanvas: View {
    let study: StudyResult
    let viewport: CGSize
    let dynamicType: DynamicTypeSize

    @Environment(\.colorScheme) private var scheme
    private let inset: CGFloat = 4

    var contentWidth: CGFloat {
        let plotWidth: CGFloat
        switch study.figure {
        case .table(let table): plotWidth = StudyTableView.contentWidth(columns: table.columns.count)
        case .matrix(let columns, _, _): plotWidth = columns.reduce(116) { $0 + 3 + StudyMatrix.width(for: $1) }
        default: plotWidth = 0
        }
        return max(viewport.width, plotWidth + inset * 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            figure
            VStack(alignment: .leading, spacing: 12) {
                if !study.legendLabels.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 126), alignment: .leading)], alignment: .leading, spacing: 6
                    ) {
                        ForEach(Array(study.legendLabels.enumerated()), id: \.offset) { index, label in
                            HStack(spacing: 6) {
                                Circle().fill(WorkoutChartPalette.color(at: index, scheme: scheme)).frame(
                                    width: 8, height: 8)
                                Text(label).font(.caption)
                            }
                        }
                    }
                }
            }
            .frame(width: max(1, viewport.width - inset * 2), alignment: .leading)
        }
        .padding(inset)
        .frame(width: contentWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .dynamicTypeSize(dynamicType)
    }

    @ViewBuilder private var figure: some View {
        let view = StudyFigureView(study: study, compact: false)
        switch study.figure {
        case .table(let table):
            StudyTableView(table: table, scrollsHorizontally: false).fixedSize(horizontal: false, vertical: true)
        case .liftPanels, .attempts, .matrix:
            view.fixedSize(horizontal: false, vertical: true)
        case .comparison(let points, _):
            view.frame(height: max(chartHeight, CGFloat(Set(points.map(\.category)).count) * 46))
        default:
            view.frame(height: chartHeight)
        }
    }

    private var chartHeight: CGFloat { max(170, viewport.height - (study.legendLabels.isEmpty ? 12 : 56)) }
}
