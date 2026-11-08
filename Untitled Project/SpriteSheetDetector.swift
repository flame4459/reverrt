import UIKit
import Vision

struct DetectedSpriteLabel: Identifiable, Sendable {
    let id: UUID
    let text: String
    /// Pixel coordinates with a top-left origin.
    let rect: CGRect
}

struct DetectedSpriteMatch: Identifiable, Sendable {
    let id: UUID
    let bikeName: String
    let label: DetectedSpriteLabel
    let score: Double
}

struct SpriteSheetDetection: Sendable {
    let matches: [DetectedSpriteMatch]
    let labels: [DetectedSpriteLabel]
}

enum SpritePlacement: Sendable {
    case above
    case below
}

struct PrecomputedBike: Sendable {
    let originalName: String
    let normalized: String
    let manufacturer: String
    let year: String?
    let modelTokens: [String]

    nonisolated init(name: String) {
        self.originalName = name
        let norm = SpriteSheetDetector.normalize(name)
        self.normalized = norm
        let tokens = norm.split(separator: " ").map(String.init)
        self.manufacturer = tokens.first ?? ""
        let extractedYear = tokens.last(where: { $0.count == 4 && $0.first?.isNumber == true })
        self.year = extractedYear
        self.modelTokens = tokens.filter { $0 != extractedYear }
    }
}

enum SpriteSheetDetector {
    nonisolated static func matchingBikeNames(in image: UIImage, catalog: [String]) -> [String] {
        matches(in: image, catalog: catalog).map(\.bikeName)
    }

    nonisolated static func matches(
        in image: UIImage,
        catalog: [String]
    ) -> [DetectedSpriteMatch] {
        detect(in: image, catalog: catalog).matches
    }

    nonisolated static func detect(
        in image: UIImage,
        catalog: [String]
    ) -> SpriteSheetDetection {
        let precomputed = catalog.map { PrecomputedBike(name: $0) }
        return detect(in: image, precomputedCatalog: precomputed)
    }

    nonisolated static func detect(
        in image: UIImage,
        precomputedCatalog: [PrecomputedBike]
    ) -> SpriteSheetDetection {
        guard let cgImage = image.cgImage else {
            return SpriteSheetDetection(matches: [], labels: [])
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]

        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
            return SpriteSheetDetection(matches: [], labels: [])
        }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let labels = request.results?.compactMap { observation -> DetectedSpriteLabel? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return DetectedSpriteLabel(
                id: UUID(),
                text: text,
                rect: pixelRect(for: observation.boundingBox, in: imageSize)
            )
        } ?? []

        let candidateLabels = mergedLabels(from: labels)
        let ranked = candidateLabels.compactMap { label -> DetectedSpriteMatch? in
            guard let result = match(for: label.text, catalog: precomputedCatalog) else { return nil }
            return DetectedSpriteMatch(
                id: UUID(),
                bikeName: result.name,
                label: label,
                score: result.score
            )
        }
        .sorted { $0.score > $1.score }

        var names = Set<String>()
        let matches: [DetectedSpriteMatch] = ranked.reduce(into: []) { matches, match in
            if names.insert(match.bikeName).inserted {
                matches.append(match)
            }
        }
        return SpriteSheetDetection(matches: matches, labels: labels)
    }

    nonisolated static func spriteRect(
        for label: DetectedSpriteLabel,
        among labels: [DetectedSpriteLabel],
        imageSize: CGSize,
        placement: SpritePlacement = .above
    ) -> CGRect {
        let current = label.rect
        let sameRow = labels.filter {
            $0.id != label.id && abs($0.rect.midY - current.midY) < max(current.height, $0.rect.height)
        }
        let left = sameRow.filter { $0.rect.midX < current.midX }.map(\.rect.midX).max()
        let right = sameRow.filter { $0.rect.midX > current.midX }.map(\.rect.midX).min()
        let minX = left.map { ($0 + current.midX) / 2 } ?? max(0, current.minX - current.width * 0.25)
        let maxX = right.map { ($0 + current.midX) / 2 } ?? min(imageSize.width, current.maxX + current.width * 0.25)

        let column = labels.filter {
            $0.id != label.id && $0.rect.midX > minX && $0.rect.midX < maxX
        }
        let padding: CGFloat = 4
        let rect: CGRect

        switch placement {
        case .above:
            let top = column.filter { $0.rect.maxY <= current.minY }.map(\.rect.maxY).max() ?? 0
            rect = CGRect(x: minX, y: top, width: max(0, maxX - minX), height: max(0, current.minY - padding - top))
        case .below:
            let bottom = column.filter { $0.rect.minY >= current.maxY }.map(\.rect.minY).min() ?? imageSize.height
            rect = CGRect(x: minX, y: current.maxY + padding, width: max(0, maxX - minX), height: max(0, bottom - current.maxY - padding))
        }

        let intersected = rect
            .intersection(CGRect(origin: .zero, size: imageSize))
            .integral
        guard intersected.width > 0, intersected.height > 0 else { return .zero }
        return intersected
    }

    nonisolated static func cropSprite(from image: UIImage, rect: CGRect) -> UIImage? {
        guard rect.width >= 1,
              rect.height >= 1,
              let cgImage = image.cgImage?.cropping(to: rect) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    nonisolated private static func pixelRect(for box: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: box.minX * size.width,
            y: (1 - box.maxY) * size.height,
            width: box.width * size.width,
            height: box.height * size.height
        )
    }

    nonisolated private static func mergedLabels(from labels: [DetectedSpriteLabel]) -> [DetectedSpriteLabel] {
        var output = labels
        guard labels.count > 1 else { return output }
        // Only pair each label with labels after it, and cap the expansion.
        // The old all-pairs loop produced a quadratic number of combined
        // strings, each of which then ran through the full catalog matcher.
        for index in labels.indices {
            let label = labels[index]
            for neighbor in labels[(index + 1)...] {
                let sameColumn = abs(neighbor.rect.midX - label.rect.midX) < max(label.rect.width, neighbor.rect.width)
                let nearbyLine = abs(neighbor.rect.midY - label.rect.midY) < max(label.rect.height, neighbor.rect.height) * 2.5
                guard sameColumn && nearbyLine else { continue }

                output.append(
                    DetectedSpriteLabel(
                        id: UUID(),
                        text: "\(label.text) \(neighbor.text)",
                        rect: label.rect.union(neighbor.rect)
                    )
                )
                if output.count > labels.count * 3 + 24 { return output }
            }
        }
        return output
    }

    nonisolated private static func match(
        for text: String,
        catalog: [PrecomputedBike]
    ) -> (name: String, score: Double)? {
        let normalizedText = normalize(text)
        let textTokens = normalizedText.split(separator: " ").map(String.init)
        guard normalizedText.count >= 3, !textTokens.isEmpty else { return nil }

        let textYear = textTokens.first(where: { $0.count == 4 && $0.first?.isNumber == true })
        let textModelTokens = textTokens.filter { $0 != textYear }
        guard !textModelTokens.isEmpty else { return nil }

        // Cheap pre-filter: keep only bikes sharing a manufacturer, model
        // token or year. This is what turns a multi-second hang into a few
        // milliseconds when the OCR pass produces hundreds of observations.
        func coarseScore(_ bike: PrecomputedBike) -> Double {
            var score = 0.0
            if bike.manufacturer.count >= 3, textModelTokens.contains(bike.manufacturer) {
                score += 20
            }
            for textToken in textModelTokens where bike.modelTokens.contains(textToken) {
                score += textToken.count >= 4 ? 40 : 12
            }
            let overlap = textModelTokens.filter { token in
                bike.modelTokens.contains { $0.hasPrefix(token) || (token.count >= 4 && token.hasPrefix($0)) }
            }.count
            score += Double(overlap) * 8
            if let textYear, textYear == bike.year { score += 35 }
            if let textYear, let bikeYear = bike.year, textYear != bikeYear {
                score -= 12
                if let a = Int(textYear), let b = Int(bikeYear), abs(a - b) > 2 { score -= 20 }
            }
            return score
        }

        var shortlist = catalog
            .map { (bike: $0, coarse: coarseScore($0)) }
            .filter { $0.coarse > 0 }
            .sorted { $0.coarse > $1.coarse }
            .prefix(48)
            .map(\.bike)
        if shortlist.isEmpty { shortlist = Array(catalog.prefix(48)) }

        func detailedScore(_ bike: PrecomputedBike) -> Double {
            var score = 0.0
            if bike.manufacturer.count >= 3, textModelTokens.contains(bike.manufacturer) {
                score += 20
            } else if let textManufacturer = textTokens.first,
                      levenshtein(textManufacturer, bike.manufacturer) <= 3 {
                score += 8
            }
            for textToken in textModelTokens {
                if bike.modelTokens.contains(textToken) {
                    score += textToken.count >= 4 ? 40 : 12
                    continue
                }
                let distance = bike.modelTokens.map { levenshtein(textToken, $0) }.min() ?? .max
                if distance <= max(1, textToken.count / 3) { score += 10 }
            }
            if let textYear, textYear == bike.year {
                score += 35
            } else if textYear != nil {
                score -= 15
            }
            return score
        }

        let ranked = shortlist
            .map { (bike: $0, score: detailedScore($0)) }
            .sorted { $0.score > $1.score }
            .prefix(12)

        let best = ranked.map { item in
            // The expensive full-string edit distance only runs for the top
            // candidates, not every catalog entry.
            (name: item.bike.originalName,
             score: item.score - Double(levenshtein(normalizedText, item.bike.normalized)) * 0.05)
        }.max { $0.score < $1.score }

        guard let best, best.score >= 25 else { return nil }
        return (best.name, best.score)
    }

    nonisolated static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .split(whereSeparator: { $0 == " " })
            .joined(separator: " ")
    }

    nonisolated static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var row = Array(0...b.count)

        for i in 1...a.count {
            var next = [i]
            for j in 1...b.count {
                next.append(
                    a[i - 1] == b[j - 1]
                        ? row[j - 1]
                        : min(row[j - 1], row[j], next[j - 1]) + 1
                )
            }
            row = next
        }
        return row[b.count]
    }
}
