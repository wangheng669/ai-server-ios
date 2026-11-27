import Foundation
import SwiftUI

private struct CityMapFeatureCollection: Decodable { let features: [CityMapFeature] }

struct CityMapFeature: Decodable, Identifiable {
    struct Properties: Decodable {
        let adcode: Int
        let name: String
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
    var labelCoordinate: [Double]? { properties.centroid ?? properties.center ?? geometry.firstCoordinate }
}

struct CityObservationService {
    private let baseURL = ServerConfiguration.currentURL
        .appending(path: "api/ios/v1/learning/city-observation")

    func catalog() async throws -> CityRegion {
        struct Catalog: Decodable { let root: CityRegion }
        let response: Catalog = try await fetch("catalog")
        return response.root
    }

    func boundaries(for adcode: Int) async throws -> [CityMapFeature] {
        let response: CityMapFeatureCollection = try await fetch("boundaries", adcode: adcode)
        return response.features
    }

    func statistics(for adcode: Int) async throws -> CityObservationStatistics {
        let result: CityObservationStatistics = try await fetch("statistics", adcode: adcode)
        guard result.adcode == adcode else { throw URLError(.cannotParseResponse) }
        return result
    }

    private func fetch<Value: Decodable>(_ endpoint: String, adcode: Int? = nil) async throws -> Value {
        var components = URLComponents(url: baseURL.appending(path: endpoint), resolvingAgainstBaseURL: false)
        if let adcode {
            components?.queryItems = [.init(name: "adcode", value: String(adcode))]
        }
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 45)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(LearningResponse<Value>.self, from: data).data
    }
}

struct CityObservationStatistics: Decodable {
    enum Status: String, Decodable { case available; case notCovered = "not_covered" }

    struct Source: Decodable {
        let title: String
        let publisher: String
        let url: URL
    }

    struct Metric: Decodable, Identifiable {
        var id: String { key }
        let key: String
        let label: String
        let value: String
        let unit: String
        let group: String
        let year: Int
        let source: Source?
    }

    struct Section: Decodable {
        let title: String
        let paragraphs: [String]
    }

    let adcode: Int
    let status: Status
    let metrics: [Metric]
    let sections: [Section]
    let notes: [String]
    let source: Source?
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
