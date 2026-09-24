import SwiftUI
import RealityKit
import ARKit
import UIKit

// MARK: - ARManager
class ARManager: ObservableObject {
    @Published var tableDetected = false
    @Published var placedCount = 0

    weak var arView: ARView?
    var placedAnchors: [AnchorEntity] = []
    var tableAnchorEntity: AnchorEntity?
    var tableModelEntity: ModelEntity?
    var tablePlaneIdentifier: UUID?

    private var placedColorIndex = 0
    let placedColors: [UIColor] = [
        .systemRed, .systemGreen, .systemBlue, .systemPurple,
        .systemOrange, .systemYellow, .systemPink, .systemTeal
    ]

    func clearPlacedPlanes() {
        guard let arView = arView else { return }
        for anchor in placedAnchors {
            arView.scene.removeAnchor(anchor)
        }
        placedAnchors.removeAll()
        DispatchQueue.main.async {
            self.placedCount = 0
        }
    }

    func getNextPlacedColor() -> UIColor {
        let color = placedColors[placedColorIndex % placedColors.count]
        placedColorIndex += 1
        return color
    }
}

// MARK: - ARView Container
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
        private var labelCounter = 0

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
                    modelEntity.position.y = 0.003

                    anchorEntity.addChild(modelEntity)

                    if let arView = manager.arView {
                        arView.scene.addAnchor(anchorEntity)
                    }

                    manager.tableAnchorEntity = anchorEntity
                    manager.tableModelEntity = modelEntity
                    manager.tablePlaneIdentifier = planeAnchor.identifier

                    DispatchQueue.main.async {
                        self.manager.tableDetected = true
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

            var raycastResults = arView.raycast(from: location, allowing: .existingPlaneGeometry, alignment: .horizontal)
            if raycastResults.isEmpty {
                raycastResults = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .horizontal)
            }

            guard let result = raycastResults.first else { return }

            let placedAnchor = AnchorEntity(world: result.worldTransform)

            let placedWidth: Float = 0.12
            let placedDepth: Float = 0.12
            let cornerRadius: Float = 0.02

            let mesh = MeshResource.generatePlane(
                width: placedWidth,
                depth: placedDepth,
                cornerRadius: cornerRadius
            )

            let color = manager.getNextPlacedColor()
            let material = SimpleMaterial(color: color, roughness: 0.5, isMetallic: false)

            let modelEntity = ModelEntity(mesh: mesh, materials: [material])
            modelEntity.position.y = 0.01

            modelEntity.generateCollisionShapes(recursive: true)
            if let collision = modelEntity.collision {
                modelEntity.components.set(collision)
            }
            arView.installGestures([.translation], for: modelEntity)

            let labelText = "Plane \(labelCounter + 1)"
            labelCounter += 1

            if let textMesh = try? MeshResource.generateText(
                labelText,
                extrusionDepth: 0.001,
                font: .systemFont(ofSize: 0.028),
                containerFrame: CGRect.zero,
                alignment: .center,
                lineBreakMode: .byTruncatingTail
            ) {
                let textMaterial = UnlitMaterial(color: .white)
                let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])
                textEntity.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
                textEntity.position = [0, 0.085, 0]

                let bgMesh = MeshResource.generatePlane(width: 0.11, depth: 0.035, cornerRadius: 0.008)
                let bgMaterial = UnlitMaterial(color: UIColor.black.withAlphaComponent(0.7))
                let bgEntity = ModelEntity(mesh: bgMesh, materials: [bgMaterial])
                bgEntity.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
                bgEntity.position = [0, 0.08, -0.002]

                textEntity.addChild(bgEntity)
                modelEntity.addChild(textEntity)
            }

            placedAnchor.addChild(modelEntity)
            arView.scene.addAnchor(placedAnchor)

            manager.placedAnchors.append(placedAnchor)

            DispatchQueue.main.async {
                self.manager.placedCount += 1
            }
        }
    }
}

// MARK: - ContentView
struct ContentView: View {
    @StateObject private var manager = ARManager()

    var body: some View {
        ZStack(alignment: .bottom) {
            ARViewContainer(manager: manager)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                if !manager.tableDetected {
                    VStack(spacing: 10) {
                        Text("Scan for Table Surface")
                            .font(.title2.bold())
                        Text("Point your camera at a flat horizontal surface\nsuch as a table, desk, or countertop.")
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 24)
                } else {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.green)
                            Text("Table Detected & Colored")
                                .font(.headline)
                        }
                        Text("Tap to place labeled rounded planes • Drag them around")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 24)
                }

                if manager.placedCount > 0 {
                    Button(role: .destructive) {
                        manager.clearPlacedPlanes()
                    } label: {
                        Label("Clear Placed Planes (\(manager.placedCount))", systemImage: "trash.fill")
                            .font(.callout.bold())
                            .frame(minWidth: 220)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red.opacity(0.85))
                    .controlSize(.large)
                    .padding(.top, 4)
                } else if manager.tableDetected {
                    Text("Tap the table to place objects • Drag them freely")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.8))
                        .padding(.top, 4)
                }
            }
            .padding(.bottom, 28)
            .animation(.easeInOut(duration: 0.25), value: manager.tableDetected)
            .animation(.easeInOut(duration: 0.2), value: manager.placedCount)
        }
    }
}

// MARK: - App
@main
struct TableARApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
