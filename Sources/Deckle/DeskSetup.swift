import Foundation

/// A saved working environment references a paper without copying its recipe.
struct DeskSetup: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var textureID: String
    var intensity: Double
    var grainScale: Double
    var grainStrength: Double
    var matteStrength: Double

    init(id: UUID = UUID(), name: String, textureID: String, intensity: Double,
         grainScale: Double, grainStrength: Double, matteStrength: Double = 0) {
        self.id = id
        self.name = name
        self.textureID = textureID
        self.intensity = intensity
        self.grainScale = grainScale
        self.grainStrength = grainStrength
        self.matteStrength = matteStrength
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, textureID, intensity, grainScale, grainStrength, matteStrength
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        textureID = try container.decode(String.self, forKey: .textureID)
        intensity = try container.decode(Double.self, forKey: .intensity)
        grainScale = try container.decode(Double.self, forKey: .grainScale)
        grainStrength = try container.decode(Double.self, forKey: .grainStrength)
        // Older saved setups did not have a matte control.
        matteStrength = try container.decodeIfPresent(Double.self, forKey: .matteStrength) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(textureID, forKey: .textureID)
        try container.encode(intensity, forKey: .intensity)
        try container.encode(grainScale, forKey: .grainScale)
        try container.encode(grainStrength, forKey: .grainStrength)
        try container.encode(matteStrength, forKey: .matteStrength)
    }

    static let starters: [DeskSetup] = [
        DeskSetup(name: "Read", textureID: "book-cream", intensity: 0.22, grainScale: 1, grainStrength: 1),
        DeskSetup(name: "Write", textureID: "clear-veil", intensity: 0.18, grainScale: 1, grainStrength: 1),
        DeskSetup(name: "Unwind", textureID: "evening-shade", intensity: 0.22, grainScale: 1, grainStrength: 1)
    ]

    var hasValidSettings: Bool {
        intensity.isFinite && (0.05...0.45).contains(intensity)
            && grainScale.isFinite && [0.5, 1, 2, 4].contains(grainScale)
            && grainStrength.isFinite && (0.25...2).contains(grainStrength)
            && matteStrength.isFinite && (0...1).contains(matteStrength)
    }
}
