import SwiftUI
import UIKit

struct BikeModel: Identifiable, Hashable {
    let name: String

    var id: String { name }

    var manufacturer: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}

enum BikeCatalog {
    static let defaultBike = "Honda CBR125R 2004"

    static let all: [BikeModel] = """
Honda CBR125R 2004
Honda CBR125R 2007
Honda CBR125R 2011
Honda CBR125R 2018
Honda CBR150R 2002
Honda CBR150R 2010
Honda CBR150R 2016
Honda CBR150R 2021
Honda CBR250R 1986
Honda CBR250R 2011
Honda CBR250RR 1990
Honda CBR250RR 2017
Honda CBR250RR 2020
Honda CBR300R 2015
Honda CBR400F 1983
Honda CBR400RR 1988
Honda CBR400RR 1990
Honda CBR400R 2013
Honda CBR500R 2013
Honda CBR500R 2016
Honda CBR500R 2019
Honda CBR500R 2022
Honda CBR600F Hurricane 1987
Honda CBR600F2 1991
Honda CBR600F3 1995
Honda CBR600F4 1999
Honda CBR600F4i 2001
Honda CBR600RR 2003
Honda CBR600RR 2007
Honda CBR600RR 2013
Honda CBR600RR 2024
Honda CBR650F 2014
Honda CBR650F 2017
Honda CBR650R 2019
Honda CBR650R 2024
Honda CBR750F 1987
Honda CBR900RR Fireblade 1992
Honda CBR900RR Fireblade 1994
Honda CBR900RR Fireblade 1996
Honda CBR900RR Fireblade 1998
Honda CBR929RR Fireblade 2000
Honda CBR954RR Fireblade 2002
Honda CBR1000RR Fireblade 2004
Honda CBR1000RR Fireblade 2008
Honda CBR1000RR Fireblade 2012
Honda CBR1000RR Fireblade 2017
Honda CBR1000RR-R Fireblade 2020
Honda CBR1000RR-R Fireblade 2024
Honda VTR1000 SP-1 2000
Honda VTR1000 SP-2 2002
Honda CBR1000F 1987
Honda CBR1100XX Blackbird 1996
Honda CBR1100XX Blackbird 1999
Honda CBR1100XX Blackbird 2001
Yamaha FZR250 1986
Yamaha FZR250R 1989
Yamaha FZR400 1986
Yamaha FZR400RR 1990
Yamaha FZR600 1989
Yamaha FZR1000 1987
Yamaha YZF600R Thundercat 1996
Yamaha YZF-R125 2008
Yamaha YZF-R125 2014
Yamaha YZF-R125 2019
Yamaha YZF-R15 2008
Yamaha YZF-R15 2011
Yamaha YZF-R15 2017
Yamaha YZF-R15 2021
Yamaha YZF-R25 2014
Yamaha YZF-R25 2019
Yamaha YZF-R3 2015
Yamaha YZF-R3 2019
Yamaha YZF-R3 2025
Yamaha YZF-R6 1999
Yamaha YZF-R6 2001
Yamaha YZF-R6 2003
Yamaha YZF-R6 2006
Yamaha YZF-R6 2008
Yamaha YZF-R6 2017
Yamaha YZF-R7 2022
Yamaha YZF-R9 2025
Yamaha YZF-R1 1998
Yamaha YZF-R1 2000
Yamaha YZF-R1 2002
Yamaha YZF-R1 2004
Yamaha YZF-R1 2007
Yamaha YZF-R1 2009
Yamaha YZF-R1 2015
Yamaha YZF-R1 2020
Yamaha YZF-R1M 2015
Yamaha FZR1000 1989
Kawasaki GPZ250R 1985
Kawasaki GPZ400R 1985
Kawasaki GPZ600R 1985
Kawasaki GPZ900R 1984
Kawasaki Ninja 250 1986
Kawasaki Ninja 250 2008
Kawasaki Ninja 250 2013
Kawasaki Ninja 250 2018
Kawasaki Ninja 300 2013
Kawasaki Ninja 400 2018
Kawasaki Ninja 500 2024
Kawasaki Ninja ZX-4R 2023
Kawasaki Ninja ZX-4RR 2023
Kawasaki Ninja 650 2006
Kawasaki Ninja 650 2012
Kawasaki Ninja 650 2017
Kawasaki Ninja 650 2020
Kawasaki Ninja ZX-6R 1995
Kawasaki Ninja ZX-6R 1998
Kawasaki Ninja ZX-6R 2003
Kawasaki Ninja ZX-6R 2005
Kawasaki Ninja ZX-6R 2007
Kawasaki Ninja ZX-6R 2009
Kawasaki Ninja ZX-6R 2013
Kawasaki Ninja ZX-6R 2019
Kawasaki Ninja ZX-6R 2024
Kawasaki Ninja ZX-7R 1991
Kawasaki Ninja ZX-7RR 1996
Kawasaki Ninja ZX-9R 1994
Kawasaki Ninja ZX-9R 1998
Kawasaki Ninja ZX-9R 2000
Kawasaki Ninja ZX-10R 2004
Kawasaki Ninja ZX-10R 2006
Kawasaki Ninja ZX-10R 2008
Kawasaki Ninja ZX-10R 2011
Kawasaki Ninja ZX-10R 2016
Kawasaki Ninja ZX-10R 2021
Kawasaki Ninja H2 2015
Kawasaki Ninja H2R 2015
Kawasaki Ninja ZX-14R 2006
Kawasaki Ninja ZX-14R 2012
Kawasaki ZZR600 1990
Suzuki GSX-R250 1987
Suzuki GSX-R250R 1989
Suzuki GSX-R400 1984
Suzuki GSX-R400 1988
Suzuki GSX-R600 1997
Suzuki GSX-R600 2001
Suzuki GSX-R600 2004
Suzuki GSX-R600 2006
Suzuki GSX-R600 2008
Suzuki GSX-R600 2011
Suzuki GSX-R750 1985
Suzuki GSX-R750 1988
Suzuki GSX-R750 1990
Suzuki GSX-R750 1992
Suzuki GSX-R750 1996
Suzuki GSX-R750 2000
Suzuki GSX-R750 2006
Suzuki GSX-R750 2008
Suzuki GSX-R750 2011
Suzuki GSX-R1000 2001
Suzuki GSX-R1000 2003
Suzuki GSX-R1000 2005
Suzuki GSX-R1000 2007
Suzuki GSX-R1000 2009
Suzuki GSX-R1000 2012
Suzuki GSX-R1000 2017
Suzuki GSX-R1000R 2017
Suzuki GSX250R 2017
Suzuki GSX-8R 2024
Suzuki GSX-S1000 2015
Suzuki GSX-S1000 2021
Suzuki Hayabusa 1999
Suzuki Hayabusa 2008
Suzuki Hayabusa 2021
Suzuki TL1000R 1998
Suzuki GSX-R1100 1986
Suzuki GSX-R1100 1989
Suzuki GSX-R1100 1993
KTM RC 125 2014
KTM RC 200 2014
KTM RC 390 2014
KTM RC 390 2017
KTM RC 390 2022
KTM RC 8 2008
KTM RC 8 R 2010
KTM RC 8 R 2014
KTM RC 8C 2022
Ducati 748 1994
Ducati 748 1997
Ducati 748 2000
Ducati 749 2003
Ducati 999 2003
Ducati 1098 2007
Ducati 1198 2009
Ducati 1199 Panigale 2012
Ducati 1299 Panigale 2015
Ducati 959 Panigale 2016
Ducati Panigale V2 2020
Ducati Panigale V2 2025
Ducati Panigale V4 2018
Ducati Panigale V4 2022
Ducati Panigale V4 2025
Ducati Superleggera V4 2020
Ducati SuperSport 950 2021
Ducati Streetfighter V4 2020
Ducati Streetfighter V4 2023
Ducati Streetfighter V2 2022
Ducati Monster 1993
Ducati Monster 2001
Ducati Monster 2008
Ducati Monster 2014
Ducati Monster 2021
Aprilia RS 125 1992
Aprilia RS 125 1995
Aprilia RS 125 1999
Aprilia RS 125 2006
Aprilia RS 125 2017
Aprilia RS 125 2021
Aprilia RS 250 1995
Aprilia RS 250 1998
Aprilia RS 457 2024
Aprilia RS 660 2021
Aprilia RSV Mille 1998
Aprilia RSV Mille 2001
Aprilia RSV4 2009
Aprilia RSV4 2015
Aprilia RSV4 2021
Aprilia Tuono V4 2011
Aprilia Tuono 660 2021
BMW G 310 RR 2022
BMW F 900 R 2020
BMW S 1000 RR 2009
BMW S 1000 RR 2012
BMW S 1000 RR 2015
BMW S 1000 RR 2019
BMW S 1000 RR 2023
BMW HP4 2012
BMW M 1000 RR 2021
BMW S 1000 R 2014
BMW S 1000 R 2021
BMW M 1000 R 2023
Triumph Daytona 600 2003
Triumph Daytona 650 2005
Triumph Daytona 675 2006
Triumph Daytona 675 2009
Triumph Daytona 675 2013
Triumph Daytona 765 Moto2 Edition 2020
Triumph Daytona 660 2024
Triumph Trident 660 2021
Triumph Street Triple 675 2007
Triumph Street Triple 675 2013
Triumph Street Triple 765 2017
Triumph Street Triple 765 2023
Triumph Speed Triple 1200 RS 2021
MV Agusta F4 750 1999
MV Agusta F4 1000 2004
MV Agusta F4 1000 2010
MV Agusta F3 675 2012
MV Agusta F3 800 2013
MV Agusta Superveloce 800 2020
MV Agusta Brutale 750 2001
MV Agusta Brutale 800 2013
MV Agusta Brutale 1000 2019
Bimota Tesi 1D 1990
Bimota SB8R 1998
Bimota DB5 2005
Bimota Tesi H2 2020
Bimota KB998 Rimini 2025
CFMoto 250SR 2020
CFMoto 300SR 2020
CFMoto 450SR 2023
CFMoto 450SR S 2023
CFMoto 675SR-R 2025
CFMoto 450NK 2023
CFMoto 675NK 2025
CFMoto 800NK 2023
Kove 450RR 2024
QJMotor SRK 400 RR 2022
QJMotor SRK 600 RR 2023
QJMotor SRK 800 RR 2023
TVS Apache RR 310 2017
TVS Apache RR 310 2024
Bajaj Pulsar RS200 2015
Bajaj Pulsar RS200 2025
Hero Karizma 2003
Hero Karizma ZMR 2009
Hero Karizma XMR 2023
Royal Enfield Continental GT 650 2018
Buell Firebolt XB9R 2002
Buell Firebolt XB12R 2004
Buell 1125R 2008
Buell 1190RX 2014
Buell 1190SX 2014
Buell Hammerhead 1190 2022
Norton F1 1990
Norton 961 Sport 2010
Norton V4SV 2022
Norton V4CR 2023
Husqvarna Vitpilen 401 2018
Husqvarna Vitpilen 401 2024
Husqvarna Vitpilen 801 2024
Kymco Quannon 125 2007
SYM Wolf SB125 2009
Rieju RS2 2003
Rieju RS3 2011
Rieju RS3 125 2011
Horex VR6 Roadster 2012
Horex VR6 Café Racer 2014
Harley-Davidson VR1000 1994
Harley-Davidson XR1200 2009
LiveWire ONE 2021
BSA Gold Star 650 2022
GasGas Sport Models Various Years
Zontes Sport Models Various Years
Kiden Sport Models Various Years
Loncin Sport Models Various Years
Benda Sport Models Various Years
Mahindra Sport Models Various Years
BRP Powersports Models Various Years
""".split(separator: "\n").map { BikeModel(name: String($0)) }

    static let grouped: [(String, [BikeModel])] = {
        let groups = Dictionary(grouping: all) { $0.manufacturer }
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }()

    nonisolated static let precomputed: [PrecomputedBike] = all.map { PrecomputedBike(name: $0.name) }
}

struct SpriteSheetPreview: View {
    @Binding var selectedBike: String
    @State private var spriteSheet: UIImage?
    @State private var detectedMatches: [DetectedSpriteMatch] = []
    @State private var allLabels: [DetectedSpriteLabel] = []
    @State private var lockedSprite: UIImage?
    @State private var isDetecting = false
    @State private var zoomScale = 1.0
    @State private var committedZoomScale = 1.0

    var body: some View {
        Group {
            if let spriteSheet {
                VStack(alignment: .leading, spacing: 10) {
                    if let lockedSprite {
                        LockedSpriteView(sprite: lockedSprite)
                        Button("Show full sheet") {
                            self.lockedSprite = nil
                        }
                        .font(.caption.weight(.semibold))
                    } else {
                        ScrollView([.horizontal, .vertical], showsIndicators: true) {
                            Image(uiImage: spriteSheet)
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .frame(width: 900 * zoomScale)
                        }
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    zoomScale = min(max(committedZoomScale * value, 1), 4)
                                }
                                .onEnded { _ in
                                    committedZoomScale = zoomScale
                                }
                        )
                        .simultaneousGesture(
                            TapGesture(count: 2)
                                .onEnded {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        zoomScale = 1
                                        committedZoomScale = 1
                                    }
                                }
                        )

                        Text("Pinch to zoom • double-tap to reset")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    if isDetecting {
                        Label("Reading sprite labels…", systemImage: "text.viewfinder")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    } else if !detectedMatches.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Detected catalog matches", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(detectedMatches) { match in
                                        Button(match.bikeName) {
                                            selectedBike = match.bikeName
                                            let size = CGSize(
                                                width: spriteSheet.cgImage?.width ?? 0,
                                                height: spriteSheet.cgImage?.height ?? 0
                                            )
                                            let rect = SpriteSheetDetector.spriteRect(
                                                for: match.label,
                                                among: allLabels,
                                                imageSize: size
                                            )
                                            lockedSprite = SpriteSheetDetector.cropSprite(
                                                from: spriteSheet,
                                                rect: rect
                                            )
                                        }
                                        .font(.caption2.weight(.semibold))
                                        .buttonStyle(.borderedProminent)
                                        .tint(selectedBike == match.bikeName ? MapUI.accent : .gray)
                                    }
                                }
                            }
                        }
                    } else {
                        Label("No readable bike label was found in this sheet.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            } else {
                Label("sprites.png could not be loaded", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            }
        }
        .frame(height: 220)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task {
            guard spriteSheet == nil else { return }

            // Image-name lookup handles the normal target-resource path. The
            // URL fallback also handles a synchronized filename with its extension.
            let loadedImage: UIImage?
            if let namedImage = UIImage(named: "sprites") ?? UIImage(named: "sprites.png") {
                loadedImage = namedImage
            } else {
                loadedImage = await Self.loadSpriteSheetFromBundle()
            }

            guard let loadedImage else { return }
            spriteSheet = loadedImage
            isDetecting = true

            let detection: SpriteSheetDetection = await Task.detached(priority: .utility) {
                SpriteSheetDetector.detect(in: loadedImage, precomputedCatalog: BikeCatalog.precomputed)
            }.value

            detectedMatches = detection.matches
            allLabels = detection.labels
            isDetecting = false
        }
    }

    private static func loadSpriteSheetFromBundle() async -> UIImage? {
        guard let url = Bundle.main.url(forResource: "sprites", withExtension: "png") else {
            return nil
        }

        return await Task.detached(priority: .utility) {
            UIImage(contentsOfFile: url.path)
        }.value
    }
}

private struct LockedSpriteView: View {
    let sprite: UIImage

    var body: some View {
        Image(uiImage: sprite)
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: 160)
    }
}

struct BikePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedBike: String
    @State private var query = ""

    private var filteredGroups: [(String, [BikeModel])] {
        BikeCatalog.grouped.compactMap { manufacturer, bikes in
            let filtered = query.isEmpty
                ? bikes
                : bikes.filter { $0.name.localizedCaseInsensitiveContains(query) }
            return filtered.isEmpty ? nil : (manufacturer, filtered)
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Bike sprite sheet", systemImage: "photo")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MapUI.ink)

                    Text("Browse the included sprites, then search below to choose your exact bike.")
                        .font(.footnote)
                        .foregroundStyle(MapUI.secondaryInk)

                    SpriteSheetPreview(selectedBike: $selectedBike)

                    TextField("Search bikes", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.vertical, 8)
            }

            ForEach(filteredGroups, id: \.0) { manufacturer, bikes in
                Section(manufacturer) {
                    ForEach(bikes) { bike in
                        Button {
                            selectedBike = bike.name
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "motorcycle")
                                    .foregroundStyle(MapUI.accent)
                                    .frame(width: 28)
                                Text(bike.name)
                                    .foregroundStyle(MapUI.ink)
                                Spacer()
                                if selectedBike == bike.name {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(MapUI.accent)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Choose your bike")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close bike picker")
            }
        }
        .tint(MapUI.accent)
    }
}
