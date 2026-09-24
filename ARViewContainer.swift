import SwiftUI
import RealityKit
import ARKit
import UIKit

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var manager: ARManager

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        manager.arView = arView

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }

        arView.session.run(config)
        arView.session.delegate = context.coordinator

        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        arView.addGestureRecognizer(tapGesture)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(manager: manager)
    }

    class Coordinator: NSObject, ARSessionDelegate {
        var manager: ARManager

        init(manager: ARManager) {
            self.manager = manager
            super.init()
        }

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            for anchor in anchors {
                guard let planeAnchor = anchor as? ARPlaneAnchor,
                      planeAnchor.alignment == .horizontal else { continue }

                if manager.tableAnchorEntity == nil {
                    let anchorEntity = AnchorEntity(anchor: planeAnchor)

                    let width = planeAnchor.planeExtent.width
                    let depth = planeAnchor.planeExtent.height
                    let mesh = MeshResource.generatePlane(width: width, depth: depth)

                    let tableColor = UIColor(red: 0.15, green: 0.55, blue: 0.75, alpha: 0.38)
                    let material = SimpleMaterial(color: tableColor, roughness: 0.7, isMetallic: false)

                    let modelEntity = ModelEntity(mesh: mesh, materials: [material])
                    modelEntity.name = "tableTint"
                    modelEntity.position.y = 0.003

                    anchorEntity.addChild(modelEntity)

                    if let arView = manager.arView {
                        arView.scene.addAnchor(anchorEntity)
                    }

                    manager.tableAnchorEntity = anchorEntity
                    manager.tableModelEntity = modelEntity
                    manager.tablePlaneIdentifier = planeAnchor.identifier
                    manager.attachContentRootIfNeeded()

                    DispatchQueue.main.async {
                        self.manager.tableDetected = true
                        if self.manager.mode == .dominoes {
                            self.manager.game.resetBoardKeepingRules()
                            self.manager.statusLine = self.manager.game.status
                        }
                    }
                }
            }
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            for anchor in anchors {
                guard let planeAnchor = anchor as? ARPlaneAnchor,
                      manager.tablePlaneIdentifier == planeAnchor.identifier,
                      let modelEntity = manager.tableModelEntity else { continue }

                let newWidth = planeAnchor.planeExtent.width
                let newDepth = planeAnchor.planeExtent.height
                let newMesh = MeshResource.generatePlane(width: newWidth, depth: newDepth)

                if var currentModel = modelEntity.model {
                    currentModel.mesh = newMesh
                    modelEntity.model = currentModel
                } else {
                    let tableColor = UIColor(red: 0.15, green: 0.55, blue: 0.75, alpha: 0.38)
                    let material = SimpleMaterial(color: tableColor, roughness: 0.7, isMetallic: false)
                    modelEntity.model = ModelComponent(mesh: newMesh, materials: [material])
                }
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = manager.arView else { return }
            let location = gesture.location(in: arView)

            if manager.mode == .dominoes {
                if let entity = arView.entity(at: location) {
                    manager.tapEntity(entity)
                    return
                }
                return
            }

            var raycastResults = arView.raycast(
                from: location,
                allowing: .existingPlaneGeometry,
                alignment: .horizontal
            )
            if raycastResults.isEmpty {
                raycastResults = arView.raycast(
                    from: location,
                    allowing: .estimatedPlane,
                    alignment: .horizontal
                )
            }
            guard let result = raycastResults.first else { return }
            manager.placeCard(atWorldTransform: result.worldTransform)
        }
    }
}
