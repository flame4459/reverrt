import SwiftUI
import UIKit

/// Pixel-art artwork for the bikes in `BikeCatalog`.
///
/// The art lives in `bikes/` and is exported into `BikeSprites.xcassets` by
/// `Scripts/import_bike_sprites.py`, which also cuts the studio backdrop out of
/// every frame. One asset covers a whole model generation, so this table maps
/// catalog entries to assets rather than the other way round: `CBR929RR
/// Fireblade 2000` and only that entry share `bike-cbr929rr`.
///
/// Bikes without artwork fall back to the SF Symbol treatment, so new entries
/// can land in the catalog before their sprite is finished.
enum BikeSprites {
    private struct Family {
        let asset: String
        let models: [String]
    }

    private static let families: [Family] = [
        Family(asset: "bike-cb1000r", models: [
            "Honda CB1000R 2018",
            "Honda CB1000R 2021",
        ]),
        Family(asset: "bike-cb125r-naked", models: [
            "Honda CB125R 2018",
            "Honda CB125R 2021",
            "Honda CB125R 2024",
        ]),
        Family(asset: "bike-cb300r", models: [
            "Honda CB300R 2018",
            "Honda CB300R 2022",
        ]),
        Family(asset: "bike-cb600f", models: [
            "Honda CB600F Hornet 1998",
            "Honda CB600F Hornet 2000",
            "Honda CB600F Hornet 2007",
        ]),
        Family(asset: "bike-cb900f", models: [
            "Honda CB900F Hornet 2002",
            "Honda CB900F Hornet 2005",
        ]),
        Family(asset: "bike-cbr125r", models: [
            "Honda CBR125R 2004",
            "Honda CBR125R 2007",
            "Honda CBR125R 2011",
            "Honda CBR125R 2018",
        ]),
        Family(asset: "bike-cbr250r", models: [
            "Honda CBR250R 2011",
        ]),
        Family(asset: "bike-cbr300r", models: [
            "Honda CBR300R 2015",
        ]),
        Family(asset: "bike-cbr500r", models: [
            "Honda CBR500R 2013",
            "Honda CBR500R 2016",
            "Honda CBR500R 2019",
            "Honda CBR500R 2022",
        ]),
        Family(asset: "bike-cbr600f2", models: [
            "Honda CBR600F2 1991",
        ]),
        Family(asset: "bike-cbr600f3", models: [
            "Honda CBR600F3 1995",
        ]),
        Family(asset: "bike-cbr600f4", models: [
            "Honda CBR600F4 1999",
        ]),
        Family(asset: "bike-cbr600f4i", models: [
            "Honda CBR600F4i 2001",
        ]),
        Family(asset: "bike-cbr600rr", models: [
            "Honda CBR600RR 2003",
            "Honda CBR600RR 2007",
            "Honda CBR600RR 2013",
            "Honda CBR600RR 2024",
        ]),
        Family(asset: "bike-cbr650f", models: [
            "Honda CBR650F 2014",
            "Honda CBR650F 2017",
        ]),
        Family(asset: "bike-cbr650r", models: [
            "Honda CBR650R 2019",
            "Honda CBR650R 2024",
        ]),
        Family(asset: "bike-cbr900rr", models: [
            "Honda CBR900RR Fireblade 1992",
            "Honda CBR900RR Fireblade 1994",
        ]),
        // The 1996-1999 Fireblade is the 919 cc carby generation; the catalog
        // keeps calling it CBR900RR, the sprite is drawn from the 919.
        Family(asset: "bike-cbr919rr", models: [
            "Honda CBR900RR Fireblade 1996",
            "Honda CBR900RR Fireblade 1998",
        ]),
        Family(asset: "bike-cbr929rr", models: [
            "Honda CBR929RR Fireblade 2000",
        ]),
        Family(asset: "bike-cbr954rr", models: [
            "Honda CBR954RR Fireblade 2002",
        ]),
        Family(asset: "bike-cbr1000rr", models: [
            "Honda CBR1000RR Fireblade 2004",
            "Honda CBR1000RR Fireblade 2008",
            "Honda CBR1000RR Fireblade 2012",
            "Honda CBR1000RR Fireblade 2017",
        ]),
        Family(asset: "bike-cbr1000rr-r", models: [
            "Honda CBR1000RR-R Fireblade 2020",
            "Honda CBR1000RR-R Fireblade 2024",
        ]),
        Family(asset: "bike-cbr1000f", models: [
            "Honda CBR1000F 1987",
        ]),
        Family(asset: "bike-cbr1100xx", models: [
            "Honda CBR1100XX Blackbird 1996",
            "Honda CBR1100XX Blackbird 1999",
            "Honda CBR1100XX Blackbird 2001",
        ]),
        Family(asset: "bike-rc45-rvf750r", models: [
            "Honda RC45 RVF750R 1994",
            "Honda RC45 RVF750R 1996",
        ]),
        Family(asset: "bike-vfr750f", models: [
            "Honda VFR750F 1990",
            "Honda VFR750F 1994",
            "Honda VFR750F 1997",
        ]),
        Family(asset: "bike-vfr800", models: [
            "Honda VFR800 1998",
            "Honda VFR800 2002",
        ]),
        Family(asset: "bike-vfr800f", models: [
            "Honda VFR800F 2014",
            "Honda VFR800F 2018",
        ]),
        Family(asset: "bike-vfr1200f", models: [
            "Honda VFR1200F 2010",
            "Honda VFR1200F 2012",
        ]),
        Family(asset: "bike-vtr1000f", models: [
            "Honda VTR1000F Firestorm 1997",
            "Honda VTR1000F Firestorm 2001",
        ]),
        Family(asset: "bike-vtr1000-sp-1", models: [
            "Honda VTR1000 SP-1 2000",
        ]),
        Family(asset: "bike-vtr1000-sp-2-rc51", models: [
            "Honda VTR1000 SP-2 2002",
        ]),
    ]

    /// Catalog model name -> asset name.
    ///
    /// The hand-finished families above win; everything else comes from the
    /// generated map produced by `Scripts/install_sprites.py`, so a new sprite
    /// only has to be installed, never hand-listed here.
    static let modelArtwork: [String: String] = {
        var map = Dictionary(
            families.flatMap { family in family.models.map { ($0, family.asset) } },
            uniquingKeysWith: { first, _ in first }
        )
        for (model, asset) in BikeSpriteMap.entries where map[model] == nil {
            map[model] = asset
        }
        return map
    }()

    /// Distinct sprite files on disk (a family can cover several model years).
    static var artworkCount: Int { Set(modelArtwork.values).count }

    /// Catalog entries that have artwork.
    static var coveredModelCount: Int { modelArtwork.count }

    static func artworkName(for bikeName: String) -> String? {
        modelArtwork[bikeName]
    }

    static func image(for bikeName: String) -> UIImage? {
        guard let name = artworkName(for: bikeName) else { return nil }
        return UIImage(named: name)
    }

    static func hasArtwork(for bikeName: String) -> Bool {
        image(for: bikeName) != nil
    }
}

// MARK: - Views

/// The bike on its own, with the bike icon standing in until a sprite exists.
struct BikeArtworkView: View {
    let bikeName: String
    var width: CGFloat = 64
    var height: CGFloat = 40
    var accessibilityHidden = true

    var body: some View {
        Group {
            if let image = BikeSprites.image(for: bikeName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "motorcycle")
                    .font(.system(size: height * 0.52, weight: .regular))
                    .foregroundStyle(MapUI.textTertiary.opacity(0.55))
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(accessibilityHidden)
    }
}

/// Showroom-style hero card for the currently selected bike.
struct BikeShowcase: View {
    let bikeName: String

    private var entry: BikeModel? { BikeCatalog.entry(named: bikeName) }

    private var manufacturer: String {
        entry?.manufacturer ?? bikeName.split(separator: " ").first.map(String.init) ?? bikeName
    }

    private var designation: String {
        entry?.designation ?? bikeName.split(separator: " ").dropFirst().joined(separator: " ")
    }

    private var eyebrow: String {
        guard let entry else { return manufacturer.uppercased() }
        return "\(manufacturer.uppercased())  ·  \(entry.category.title.uppercased())"
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(MapUI.surfaceHigh)

            RadialGradient(
                colors: [MapUI.cyan.opacity(0.30), .clear],
                center: .init(x: 0.72, y: 0.22),
                startRadius: 2,
                endRadius: 230
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            if let image = BikeSprites.image(for: bikeName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 12)
                    .padding(.top, 30)
                    .padding(.bottom, 46)
                    .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 10)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "motorcycle")
                        .font(.system(size: 54, weight: .thin))
                        .foregroundStyle(MapUI.textTertiary)
                    Text("Artwork coming soon")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(MapUI.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 40)
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(eyebrow)
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(MapUI.cyan)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(designation)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(MapUI.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .frame(height: 208)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(MapUI.lineStrong, lineWidth: 0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bikeName) artwork")
    }
}
