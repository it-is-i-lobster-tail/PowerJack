//
//  Flowchart.swift
//  PowerJack
//
//  The pieces of the FAQ's flowcharts. Stack them in a VStack with no spacing: steps and questions
//  join with arrows down a line at the left, and each answer to a question branches off to the right.
//

import SwiftUI

/// Where the line down the left runs, and where branches start. Nonisolated, for the shapes.
private nonisolated enum FlowMetrics {
    /// Through the middle of a step's number.
    static let spine: CGFloat = 22
    static let branchInset: CGFloat = 44
    /// How far down a branch its arrow points in.
    static let elbow: CGFloat = 26
    static let arrowHead: CGFloat = 5
    static var line: StrokeStyle { StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round) }
}

/// Which way a branch moves training.
enum FlowTone {
    case stepUp
    case hold
    case easeOff
    case info

    var systemImage: String {
        switch self {
        case .stepUp: "arrow.up.circle.fill"
        case .hold: "equal.circle.fill"
        case .easeOff: "arrow.down.circle.fill"
        case .info: "arrow.right.circle.fill"
        }
    }

    // Okabe-Ito bluish green and orange, like VolumeTier's, so the two stay apart with color blindness.
    var color: Color {
        switch self {
        case .stepUp: Color(red: 0, green: 0.62, blue: 0.45)
        case .hold: .gray
        case .easeOff: Color(red: 0.9, green: 0.62, blue: 0)
        case .info: .blue
        }
    }
}

/// Something the lifter or PowerJack does, numbered when it's part of a sequence.
struct FlowStep: View {
    var number: Int? = nil
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: number.map { "\($0).circle.fill" } ?? "circle.fill")
                .imageScale(number == nil ? .small : .medium)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: LayoutMetrics.cardCornerRadius))
        .accessibilityElement(children: .combine)
    }
}

/// Leads down to the next piece, with the answer it follows when it comes after a question.
struct FlowArrow: View {
    var label: String? = nil

    var body: some View {
        // An HStack rather than a Group, so the arrow still has a frame to draw in without a label.
        HStack {
            if let label {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .padding(.leading, FlowMetrics.branchInset)
        .background(alignment: .leading) {
            DownArrow()
                .stroke(.tertiary, style: FlowMetrics.line)
                .frame(width: FlowMetrics.spine * 2)
                .padding(.vertical, 3)
        }
    }
}

/// A question that splits the flow, in the pointed box flowcharts use for one.
struct FlowQuestion: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.bold))
            if let detail {
                Text(detail)
                    .font(.caption)
                    .opacity(0.8)
            }
        }
        // The answer's own background, so the text reads as cut out of the box.
        .foregroundStyle(Color(.secondarySystemGroupedBackground))
        .padding(.vertical, 10)
        .padding(.horizontal, 24)
        .background(.primary, in: DecisionShape())
        .accessibilityElement(children: .combine)
    }
}

/// One answer to the question above it, and what happens then. The line down the left runs on past it
/// to the next piece, or stops here when `isLast`.
struct FlowOutcome: View {
    let tone: FlowTone
    let when: String
    let title: String
    var detail: String? = nil
    var isLast = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: tone.systemImage)
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(when)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(tone.color.opacity(VisualOpacity.subtle), in: .rect(cornerRadius: LayoutMetrics.cardCornerRadius))
        .accessibilityElement(children: .combine)
        .padding(.top, LayoutMetrics.compactSpacing)
        .padding(.leading, FlowMetrics.branchInset)
        .background {
            BranchLine(isLast: isLast)
                .stroke(.tertiary, style: FlowMetrics.line)
        }
    }
}

// Shapes draw off the main actor, so they're nonisolated.
private nonisolated struct DownArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let head = FlowMetrics.arrowHead
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.midX - head, y: rect.maxY - head))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX + head, y: rect.maxY - head))
        return path
    }
}

/// The spine through a branch's row, and an elbow off it pointing in at the branch.
private nonisolated struct BranchLine: Shape {
    let isLast: Bool

    func path(in rect: CGRect) -> Path {
        let head = FlowMetrics.arrowHead
        let x = rect.minX + FlowMetrics.spine
        let y = rect.minY + FlowMetrics.elbow
        let end = rect.minX + FlowMetrics.branchInset - 4
        var path = Path()
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x, y: isLast ? y : rect.maxY))
        path.move(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: end, y: y))
        path.move(to: CGPoint(x: end - head, y: y - head))
        path.addLine(to: CGPoint(x: end, y: y))
        path.addLine(to: CGPoint(x: end - head, y: y + head))
        return path
    }
}

/// A box with pointed ends.
private nonisolated struct DecisionShape: Shape {
    func path(in rect: CGRect) -> Path {
        let point = min(rect.height / 2, 14)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + point, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - point, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - point, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + point, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
