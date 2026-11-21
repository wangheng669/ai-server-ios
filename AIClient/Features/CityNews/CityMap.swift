import SwiftUI

private struct CityMapFeatureCollection: Decodable { let features: [CityMapFeature] }

struct CityMapFeature: Decodable, Identifiable {
    struct Properties: Decodable {
        struct Parent: Decodable { let adcode: Int }
        let adcode: Int
        let name: String
        let level: String
        let parent: Parent?
        let center: [Double]?
        let centroid: [Double]?
    }

    struct Geometry: Decodable {
        let outline: Path
        let bounds: CGRect
        let firstCoordinate: [Double]?
        private enum CodingKeys: String, CodingKey { case type, coordinates }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let polygons: [[[[Double]]]]
            switch try container.decode(String.self, forKey: .type) {
            case "Polygon":
                polygons = [try container.decode([[[Double]]].self, forKey: .coordinates)]
            case "MultiPolygon":
                polygons = try container.decode([[[[Double]]]].self, forKey: .coordinates)
            default:
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unsupported map geometry")
            }

            firstCoordinate = polygons.first?.first?.first
            var path = Path()
            for polygon in polygons {
                for ring in polygon {
                    guard let first = ring.first, first.count >= 2 else { continue }
                    path.move(to: CGPoint(x: first[0], y: first[1]))
                    for coordinate in ring.dropFirst() where coordinate.count >= 2 {
                        path.addLine(to: CGPoint(x: coordinate[0], y: coordinate[1]))
                    }
                    path.closeSubpath()
                }
            }
            outline = path
            bounds = path.boundingRect
        }
    }

    let properties: Properties
    let geometry: Geometry
    var id: Int { properties.adcode }
    var parentAdcode: Int? { properties.parent?.adcode }
    var labelCoordinate: [Double]? { properties.centroid ?? properties.center ?? geometry.firstCoordinate }
}

struct CityMapRepository {
    static let shared = CityMapRepository()
    private let features: [CityMapFeature]

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "CityMapRegions", withExtension: "geojson"),
              let data = try? Data(contentsOf: url),
              let collection = try? JSONDecoder().decode(CityMapFeatureCollection.self, from: data)
        else { features = []; return }
        features = collection.features
    }

    func rootRegion() -> CityRegion {
        let byParent = Dictionary(grouping: features, by: \.parentAdcode)
        func region(for feature: CityMapFeature) -> CityRegion? {
            let level: CityRegionLevel
            switch feature.properties.level {
            case "province": level = .province
            case "city": level = .city
            case "district": level = .district
            default: return nil
            }
            return CityRegion(
                adcode: feature.id,
                parentAdcode: feature.parentAdcode,
                name: feature.properties.name,
                level: level,
                children: (byParent[feature.id] ?? []).compactMap(region(for:))
            )
        }
        return CityRegion(
            adcode: 100000,
            parentAdcode: nil,
            name: "全国",
            level: .country,
            children: (byParent[100000] ?? []).compactMap(region(for:))
        )
    }

    func features(for region: CityRegion) -> [CityMapFeature] {
        let codes = Set(region.children.map(\.adcode))
        return features.filter { codes.contains($0.id) }
    }

}

struct CityMapProjection {
    let transform: CGAffineTransform
    let scale: CGFloat

    init(features: [CityMapFeature], size: CGSize) {
        let bounds = features.reduce(CGRect.null) { $0.union($1.geometry.bounds) }
        let source = bounds.isNull ? CGRect(x: 0, y: 0, width: 1, height: 1) : bounds
        let width = max(source.width, 0.001)
        let height = max(source.height, 0.001)
        let padding: CGFloat = 12
        let scale = min(max(size.width - padding * 2, 1) / width, max(size.height - padding * 2, 1) / height)
        self.scale = scale
        transform = CGAffineTransform(
            a: scale, b: 0, c: 0, d: -scale,
            tx: (size.width - width * scale) / 2 - source.minX * scale,
            ty: (size.height - height * scale) / 2 + source.maxY * scale
        )
    }

    func point(for coordinate: [Double]) -> CGPoint {
        guard coordinate.count >= 2 else { return .zero }
        return CGPoint(x: coordinate[0], y: coordinate[1]).applying(transform)
    }

    func contains(_ point: CGPoint, in feature: CityMapFeature) -> Bool {
        feature.geometry.outline.contains(point.applying(transform.inverted()), eoFill: true)
    }
}
