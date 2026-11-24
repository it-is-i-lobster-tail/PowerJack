import Charts
import SwiftUI

private struct PlotFrameKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

extension View {
    /// Report the axis-free plot area for hit testing in the chart gesture overlay.
    func reportsDataPlotFrame() -> some View {
        chartOverlay { proxy in
            GeometryReader { geometry in
                if let anchor = proxy.plotFrame {
                    let origin = geometry.frame(in: .named("DataPlot")).origin
                    Color.clear.preference(key: PlotFrameKey.self,
                                           value: geometry[anchor].offsetBy(dx: origin.x, dy: origin.y))
                }
            }
        }
    }
}

// The marker measures the live chart in its window, including the current zoom,
// page and scroll position. Capture before presenting the activity sheet.
private final class ChartCapture {
    weak var marker: UIView?

    func image(title: String) -> UIImage? {
        guard let marker, let window = marker.window else { return nil }
        var rect = marker.convert(marker.bounds, to: window).intersection(window.bounds)
        var parent = marker.superview
        while let view = parent {
            if view.clipsToBounds { rect = rect.intersection(view.convert(view.bounds, to: window)) }
            parent = view.superview
        }
        guard !rect.isEmpty, !rect.isNull else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.traitCollection.displayScale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let screen = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: .headline),
            .foregroundColor: UIColor.label.resolvedColor(with: window.traitCollection)
        ]
        let heading = NSAttributedString(string: title, attributes: attributes)
        let height = ceil(heading.boundingRect(with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                                                options: .usesLineFragmentOrigin, context: nil).height)
        let size = CGSize(width: rect.width + 32, height: rect.height + height + 44)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemBackground.resolvedColor(with: window.traitCollection).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            heading.draw(in: CGRect(x: 16, y: 16, width: rect.width, height: height))
            let chart = CGRect(x: 16, y: height + 28, width: rect.width, height: rect.height)
            context.cgContext.clip(to: chart)
            screen.draw(at: CGPoint(x: chart.minX - rect.minX, y: chart.minY - rect.minY))
        }
    }
}

private struct ChartMarker: UIViewRepresentable {
    let capture: ChartCapture
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { capture.marker = view }
}

private struct ChartShare: UIViewControllerRepresentable, Identifiable {
    let id = UUID()
    let image: UIImage
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private extension EnvironmentValues {
    @Entry var expandedCapture: ChartCapture? = nil
}

extension View {
    /// Magnify only the plot. Outside it, the legend and vertical scrolling stay interactive.
    func zoomableExpandedPlot() -> some View { modifier(ExpandedPlotZoom()) }
}

private struct ExpandedPlotZoom: ViewModifier {
    @Environment(\.expandedCapture) var capture
    @State private var scale: CGFloat = 1
    @State private var origin = CGSize.zero
    @State private var initialScale: CGFloat?
    @State private var initialOrigin = CGSize.zero

    func body(content: Content) -> some View {
        if capture == nil { content } else {
            GeometryReader { geometry in
                let size = geometry.size
                content.frame(width: size.width, height: size.height)
                    .scrollDisabled(scale > 1)
                    .scaleEffect(scale)
                    .offset(bounded(origin, size, scale))
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .simultaneousGesture(MagnifyGesture().onChanged { value in
                        if initialScale == nil { initialScale = scale; initialOrigin = origin }
                        let start = initialScale ?? scale
                        let next = min(6, max(1, start * value.magnification))
                        let ratio = next / start
                        let anchor = value.startAnchor
                        origin = bounded(CGSize(width: initialOrigin.width * ratio + (anchor.x - 0.5) * size.width * (1 - ratio),
                                                height: initialOrigin.height * ratio + (anchor.y - 0.5) * size.height * (1 - ratio)), size, next)
                        scale = next
                    }.onEnded { _ in initialScale = nil })
                    .highPriorityGesture(DragGesture(coordinateSpace: .global).onChanged { drag in
                        guard initialScale == nil else { return }
                        if panStart == nil { panStart = bounded(origin, size, scale) }
                        let start = panStart ?? origin
                        origin = bounded(CGSize(width: start.width + drag.translation.width,
                                                height: start.height + drag.translation.height), size, scale)
                    }.onEnded { _ in panStart = nil }, isEnabled: scale > 1)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("Expanded zoom plot")
            }
        }
    }

    @State private var panStart: CGSize?
    private func bounded(_ offset: CGSize, _ size: CGSize, _ scale: CGFloat) -> CGSize {
        let x = size.width * (scale - 1) / 2
        let y = size.height * (scale - 1) / 2
        return CGSize(width: min(x, max(-x, offset.width)), height: min(y, max(-y, offset.height)))
    }
}

private struct ExportableChart: ViewModifier {
    @Environment(\.expandedCapture) var capture
    func body(content: Content) -> some View {
        content.background { if let capture { ChartMarker(capture: capture) } }
    }
}

private struct ExpandedChartPresentation<Accessory: View, Content: View>: View {
    let title: String
    let close: () -> Void
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content
    @GestureState(resetTransaction: Transaction(animation: .easeOut(duration: 0.2))) private var offset: CGFloat = 0

    @State private var capture = ChartCapture()
    @State private var share: ChartShare?
    @State private var captureFailed = false

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(title).font(.title3.bold())
                Spacer()
                accessory()
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        chartButton("Share chart", symbol: "square.and.arrow.up") {
                            if let image = capture.image(title: title) { share = ChartShare(image: image) }
                            else { captureFailed = true }
                        }
                        chartButton("Close", symbol: "xmark", action: close)
                    }
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .global)
                    .updating($offset) { drag, offset, _ in
                        let delta = drag.translation
                        offset = delta.height > abs(delta.width) ? delta.height : 0
                    }
                    .onEnded { drag in
                        let delta = drag.translation
                        guard delta.height > abs(delta.width) else { return }
                        if delta.height >= 90 || drag.predictedEndTranslation.height >= 180 { close() }
                    }
            )
            content().environment(\.expandedCapture, capture)
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .offset(y: offset)
        .presentationBackground(.clear)
        .sheet(item: $share) { item in item }
        .alert("Couldn’t create chart image", isPresented: $captureFailed) {
            Button("OK", role: .cancel) {}
        }
    }
    private func chartButton(_ label: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .frame(width: 38, height: 38)
                .glassEffect(.regular.interactive(), in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

}

/// Shares the chart content and its selection between inline and expanded presentations.
struct FullScreenTrendChart<Content: View>: View {
    let title: String
    let inlineHeight: CGFloat
    @ViewBuilder let content: (CGFloat) -> Content
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button { expanded = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Expand \(title)")
            }
            content(inlineHeight)
        }
        .fullScreenCover(isPresented: $expanded) {
            ExpandedChartPresentation(title: title, close: { expanded = false }, accessory: { EmptyView() }) {
                GeometryReader { geometry in
                    ScrollView {
                        content(max(inlineHeight, geometry.size.height * 0.65))
                            .modifier(ExportableChart())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

/// A chart's horizontal window is a fraction of its full data domain. Both presentations share it.
struct ExpandableDataChart<HeaderAccessory: View, Plot: View, Details: View>: View {
    let title: String
    let height: CGFloat
    let minimumSpan: Double
    let maximumSpan: Double
    let select: ((Double, ClosedRange<Double>) -> Void)?
    let headerAccessory: () -> HeaderAccessory
    let plot: (ClosedRange<Double>) -> Plot

    let details: (ClosedRange<Double>) -> Details
    @Environment(\.verticalSizeClass) private var verticalSize

    init(title: String, height: CGFloat, minimumSpan: Double, maximumSpan: Double = 1,
         select: ((Double, ClosedRange<Double>) -> Void)? = nil,
         @ViewBuilder headerAccessory: @escaping () -> HeaderAccessory = { EmptyView() },
         @ViewBuilder plot: @escaping (ClosedRange<Double>) -> Plot,
         @ViewBuilder details: @escaping (ClosedRange<Double>) -> Details = { _ in EmptyView() }) {
        self.title = title
        self.height = height
        self.minimumSpan = minimumSpan
        self.maximumSpan = maximumSpan
        self.select = select
        self.headerAccessory = headerAccessory
        self.plot = plot
        self.details = details
    }

    @State private var window: ClosedRange<Double>?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if HeaderAccessory.self == EmptyView.self {
                expandButton {
                    HStack {
                        Text(title).font(.headline)
                        Spacer()
                        expandIcon
                    }
                }
            } else {
                HStack {
                    expandButton { Text(title).font(.headline) }
                    Spacer()
                    headerAccessory()
                    expandButton { expandIcon }
                        .accessibilityLabel("Expand \(title)")
                }
            }
            interactivePlot.frame(height: height)
        }
        .fullScreenCover(isPresented: $expanded) {
            ExpandedChartPresentation(title: title, close: { expanded = false }, accessory: headerAccessory) {
                if Details.self == EmptyView.self {
                    interactivePlot.modifier(ExportableChart())
                } else {
                    GeometryReader { geometry in
                        if verticalSize == .compact && geometry.size.width >= 640 {
                            HStack(alignment: .top, spacing: 16) {
                                interactivePlot.modifier(ExportableChart())
                                Divider()
                                ScrollView {
                                    details(visibleWindow)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(width: geometry.size.width * 0.38)
                            }
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 24) {
                                    interactivePlot.modifier(ExportableChart())
                                        .frame(height: min(geometry.size.height, max(240, geometry.size.height * 0.62)))
                                    details(visibleWindow)
                                }
                                .padding(.bottom)
                            }
                        }
                    }
                }
            }
        }
    }

    private var expandIcon: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private func expandButton<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        Button { expanded = true } label: {
            label().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open full screen")
    }

    private var visibleWindow: ClosedRange<Double> {
        guard let window else { return (1 - maximumSpan)...1 }
        let span = min(maximumSpan, max(minimumSpan, window.upperBound - window.lowerBound))
        return ChartGestures.bounded(start: window.lowerBound, span: span)
    }

    @ViewBuilder
    private var interactivePlot: some View {
        if minimumSpan == maximumSpan {
            plot(visibleWindow)
                .zoomableExpandedPlot()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded {
                    if !expanded { expanded = true }
                })
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("Data chart, \(title)")
        } else {
            zoomablePlot
        }
    }

    private var zoomablePlot: some View {
        let visible = visibleWindow
        return plot(visible)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlayPreferenceValue(PlotFrameKey.self) { frame in
                ChartGestures(window: visible, minimumSpan: minimumSpan, maximumSpan: maximumSpan, change: { window = $0 },
                              tap: { point in
                                  if !expanded { expanded = true }
                                  else if frame.width > 0, frame.contains(point) {
                                      select?((point.x - frame.minX) / frame.width, visible)
                                  }
                              })
                    .accessibilityHidden(true)
            }
            .coordinateSpace(name: "DataPlot")
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("Data chart, \(title)")
            .accessibilityAction(named: "Zoom in") { zoom(visible, by: 2) }
            .accessibilityAction(named: "Zoom out") { zoom(visible, by: 0.5) }
            .accessibilityAction(named: "Earlier") { shift(visible, direction: -1) }
            .accessibilityAction(named: "Later") { shift(visible, direction: 1) }
    }

    private func zoom(_ visible: ClosedRange<Double>, by scale: Double) {
        let span = visible.upperBound - visible.lowerBound
        let newSpan = min(maximumSpan, max(minimumSpan, span / scale))
        window = ChartGestures.bounded(start: visible.lowerBound + (span - newSpan) / 2, span: newSpan)
    }

    private func shift(_ visible: ClosedRange<Double>, direction: Double) {
        let span = visible.upperBound - visible.lowerBound
        window = ChartGestures.bounded(start: visible.lowerBound + direction * span * 0.8, span: span)
    }
}

/// Direction locking lets vertical drags reach the page even when a finger starts inside a plot.
private struct ChartGestures: UIViewRepresentable {
    let window: ClosedRange<Double>
    let minimumSpan: Double
    let maximumSpan: Double
    let change: (ClosedRange<Double>) -> Void
    let tap: (CGPoint) -> Void

    static func bounded(start: Double, span: Double) -> ClosedRange<Double> {
        let lower = min(max(0, start), 1 - span)
        return lower...min(1, lower + span)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let handler = context.coordinator
        let pan = UIPanGestureRecognizer(target: handler, action: #selector(handler.pan))
        pan.maximumNumberOfTouches = 1
        pan.delegate = handler
        view.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: handler, action: #selector(handler.pinch))
        view.addGestureRecognizer(pinch)
        let tap = UITapGestureRecognizer(target: handler, action: #selector(handler.tap(_:)))
        tap.require(toFail: pan)
        tap.require(toFail: pinch)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { context.coordinator.owner = self }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var owner: ChartGestures
        private var initial = 0.0...1.0
        private var anchor = 0.5
        init(_ owner: ChartGestures) { self.owner = owner }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            otherGestureRecognizer.view is UIScrollView
        }

        @objc func tap(_ recognizer: UITapGestureRecognizer) { owner.tap(recognizer.location(in: recognizer.view)) }

        @objc func pan(_ pan: UIPanGestureRecognizer) {
            guard let view = pan.view, view.bounds.width > 0 else { return }
            if pan.state == .began { initial = owner.window }
            let span = initial.upperBound - initial.lowerBound
            let delta = pan.translation(in: view).x / view.bounds.width
            owner.change(ChartGestures.bounded(start: initial.lowerBound - delta * span, span: span))
        }

        @objc func pinch(_ pinch: UIPinchGestureRecognizer) {
            guard let view = pinch.view, view.bounds.width > 0 else { return }
            let position = min(1, max(0, pinch.location(in: view).x / view.bounds.width))
            if pinch.state == .began {
                initial = owner.window
                anchor = initial.lowerBound + position * (initial.upperBound - initial.lowerBound)
            }
            guard pinch.state == .began || pinch.state == .changed else { return }
            let span = min(owner.maximumSpan, max(owner.minimumSpan, (initial.upperBound - initial.lowerBound) / pinch.scale))
            owner.change(ChartGestures.bounded(start: anchor - position * span, span: span))
        }
    }
}
