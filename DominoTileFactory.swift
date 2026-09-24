import RealityKit
import UIKit

enum TileOwner: String {
    case human
    case ai
    case boneyard
    case chain
}

struct DominoTileComponent: Component {
    var face: DominoFace
    var owner: TileOwner
    var faceUp: Bool
}

enum DominoTileFactory {
    static let length: Float = 0.050
    static let width: Float = 0.025
    static let thickness: Float = 0.008
    static let pipRadius: Float = 0.0021
    static let cornerRadius: Float = 0.0022
    static let gap: Float = 0.0024

    static let ivory = UIColor(red: 0.96, green: 0.93, blue: 0.84, alpha: 1)
    static let ivoryEdge = UIColor(red: 0.86, green: 0.80, blue: 0.68, alpha: 1)
    static let pipColor = UIColor(red: 0.12, green: 0.10, blue: 0.09, alpha: 1)
    static let dividerColor = UIColor(red: 0.55, green: 0.42, blue: 0.28, alpha: 1)
    static let backColor = UIColor(red: 0.42, green: 0.16, blue: 0.16, alpha: 1)

    static func makeTile(face: DominoFace, faceUp: Bool, owner: TileOwner) -> ModelEntity {
        let root = ModelEntity()
        root.name = "domino-\(face.id)"
        root.components.set(DominoTileComponent(face: face, owner: owner, faceUp: faceUp))

        let bodyMesh = MeshResource.generateBox(
            width: length,
            height: thickness,
            depth: width,
            cornerRadius: cornerRadius,
            splitFaces: false
        )
        let ivoryMaterial = SimpleMaterial(color: ivory, roughness: 0.38, isMetallic: false)
        let body = ModelEntity(mesh: bodyMesh, materials: [ivoryMaterial])
        body.name = "domino-body"
        root.addChild(body)

        let backMesh = MeshResource.generatePlane(width: length - 0.003, depth: width - 0.003, cornerRadius: 0.0015)
        let back = ModelEntity(mesh: backMesh, materials: [SimpleMaterial(color: backColor, roughness: 0.55, isMetallic: false)])
        back.position = [0, -thickness / 2 - 0.0002, 0]
        back.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
        back.name = "domino-back"
        root.addChild(back)

        let dividerMesh = MeshResource.generateBox(width: 0.0011, height: 0.0007, depth: width - 0.004)
        let divider = ModelEntity(
            mesh: dividerMesh,
            materials: [SimpleMaterial(color: dividerColor, roughness: 0.6, isMetallic: false)]
        )
        divider.position = [0, thickness / 2 + 0.0002, 0]
        root.addChild(divider)

        addPips(to: root, value: face.a, halfSign: -1)
        addPips(to: root, value: face.b, halfSign: 1)

        if !faceUp {
            root.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
        }

        root.generateCollisionShapes(recursive: false)
        let shape = ShapeResource.generateBox(width: length, height: thickness, depth: width)
        root.collision = CollisionComponent(shapes: [shape])

        return root
    }

    static func setFaceUp(_ entity: Entity, faceUp: Bool) {
        guard var component = entity.components[DominoTileComponent.self] else { return }
        component.faceUp = faceUp
        entity.components.set(component)
        entity.orientation = faceUp
            ? simd_quatf(angle: 0, axis: [1, 0, 0])
            : simd_quatf(angle: .pi, axis: [1, 0, 0])
    }

    private static func addPips(to root: ModelEntity, value: Int, halfSign: Float) {
        let cells = pipCells(for: value)
        let halfCenterX: Float = halfSign * (length * 0.25)
        let gridX: Float = 0.0064
        let gridZ: Float = 0.0054
        let y = thickness / 2

        for cell in cells {
            let sphere = MeshResource.generateSphere(radius: pipRadius)
            let pip = ModelEntity(
                mesh: sphere,
                materials: [SimpleMaterial(color: pipColor, roughness: 0.25, isMetallic: false)]
            )
            pip.position = [
                halfCenterX + Float(cell.x) * gridX,
                y,
                Float(cell.z) * gridZ
            ]
            pip.name = "pip"
            root.addChild(pip)
        }
    }

    /// 3×3 cell offsets on a half: x and z in {-1, 0, 1}.
    private static func pipCells(for value: Int) -> [(x: Int, z: Int)] {
        switch value {
        case 1: return [(0, 0)]
        case 2: return [(-1, -1), (1, 1)]
        case 3: return [(-1, -1), (0, 0), (1, 1)]
        case 4: return [(-1, -1), (1, -1), (-1, 1), (1, 1)]
        case 5: return [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)]
        case 6: return [(-1, -1), (-1, 0), (-1, 1), (1, -1), (1, 0), (1, 1)]
        default: return []
        }
    }
}
