import Accelerate
import Foundation

/// A local Model2Vec encoder. The learned WordPiece vectors are bundled with the
/// phone app. Reading their rows needs neither a network connection nor a model service.
nonisolated struct ExerciseTextEncoder: Sendable {
    static let bundled = Bundle.main.url(forResource: "ExerciseEmbeddings", withExtension: "bin")
        .flatMap { try? ExerciseTextEncoder(url: $0) }

    private let data: Data
    private let vocabulary: [String: Int]
    private let dimensions: Int
    private let vectorOffset: Int

    init(url: URL) throws {
        let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
        guard bytes.count >= 16, bytes.prefix(4) == Data("PJV1".utf8) else { throw CocoaError(.fileReadCorruptFile) }
        let header = bytes.withUnsafeBytes { raw in
            [4, 8, 12].map { Int(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0, as: UInt32.self))) }
        }
        let (rows, width, chars) = (header[0], header[1], header[2])
        let offset = 16 + chars
        guard rows > 0, (1...4096).contains(width), offset <= bytes.count,
              bytes.count - offset == rows * (4 + width),
              let vocab = String(data: bytes[16..<offset], encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        let words = vocab.split(separator: "\n")
        guard words.count == rows else { throw CocoaError(.fileReadCorruptFile) }
        vocabulary = Dictionary(uniqueKeysWithValues: words.enumerated().map { (String($1), $0) })
        dimensions = width
        vectorOffset = offset
        data = bytes
    }

    func vector(for text: String) -> [Float] {
        let folded = text.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
        let words = folded.split { !$0.isLetter && !$0.isNumber }
        var vector = [Float](repeating: 0, count: dimensions)
        var scratch = vector
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for word in words {
                for id in tokenIDs(word) {
                    let index = vectorOffset + id * (4 + dimensions)
                    let scale = Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: index, as: UInt32.self)))
                    let values = raw.baseAddress!.advanced(by: index + 4).assumingMemoryBound(to: Int8.self)
                    vDSP_vflt8(values, 1, &scratch, 1, vDSP_Length(dimensions))
                    vDSP.add(multiplication: (scratch, scale), vector, result: &vector)
                }
            }
        }
        let magnitude = vDSP.sumOfSquares(vector).squareRoot()
        guard magnitude > 0 else { return [] }
        return vDSP.divide(vector, magnitude)
    }

    static func similarity(_ left: [Float], _ right: [Float]) -> Float {
        guard !left.isEmpty, left.count == right.count else { return 0 }
        return vDSP.dot(left, right)
    }

    private func tokenIDs(_ word: Substring) -> [Int] {
        if let whole = vocabulary[String(word)] { return [whole] }
        guard word.count <= 100 else { return [] }
        var ids: [Int] = []
        var start = word.startIndex
        while start < word.endIndex {
            var end = word.endIndex
            while end > start {
                let prefix = start == word.startIndex ? "" : "##"
                if let id = vocabulary[prefix + word[start..<end]] {
                    ids.append(id)
                    break
                }
                end = word.index(before: end)
            }
            guard end > start else { return [] }
            start = end
        }
        return ids
    }
}
