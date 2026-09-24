import RealityKit
import UIKit

enum CardFactory {
    static let width: Float = 0.063
    static let height: Float = 0.088
    static let corner: Float = 0.006

    static func makeLabeledCard(label: String, color: UIColor) -> ModelEntity {
        let mesh = MeshResource.generatePlane(
            width: width,
            depth: height,
            cornerRadius: corner
        )
        let material = SimpleMaterial(color: color, roughness: 0.45, isMetallic: false)
        let card = ModelEntity(mesh: mesh, materials: [material])
        card.name = "card-plane"
        card.position.y = 0.006
        card.generateCollisionShapes(recursive: true)

        if let textMesh = try? MeshResource.generateText(
            label,
            extrusionDepth: 0.0008,
            font: .systemFont(ofSize: 0.018, weight: .semibold),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        ) {
            let text = ModelEntity(mesh: textMesh, materials: [UnlitMaterial(color: .white)])
            text.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            let bounds = text.visualBounds(relativeTo: text)
            text.position = [-bounds.center.x, 0.004, -bounds.center.y]
            card.addChild(text)
        }

        return card
    }
}
