import SwiftUI
import RealityKit
import ARKit
import Combine

final class ARManager: NSObject, ObservableObject {
    @Published var tableDetected = false
    @Published var placedCount = 0
    @Published var mode: TableMode = .cards
    @Published var rules: DominoRules = .draw {
        didSet { game.rules = rules }
    }
    @Published var statusLine: String = ""
    @Published var selectedTileID: String?

    weak var arView: ARView?
    var placedAnchors: [AnchorEntity] = []
    var tableAnchorEntity: AnchorEntity?
    var tableModelEntity: ModelEntity?
    var tablePlaneIdentifier: UUID?

    let game = DominoGame()

    var contentRoot: Entity?
    var cardEntities: [ModelEntity] = []
    var tileEntities: [String: ModelEntity] = [:]
    var boneyardEntity: ModelEntity?
    var endMarkerEntities: [Entity] = []

    private var placedColorIndex = 0
    private var cardLabelCounter = 0
    private var aiWorkItem: DispatchWorkItem?
    private var draggingIDs: Set<String> = []

    override init() {
        super.init()
        DominoTileComponent.registerComponent()
        game.rules = rules
    }

    let placedColors: [UIColor] = [
        .systemRed, .systemGreen, .systemBlue, .systemPurple,
        .systemOrange, .systemYellow, .systemPink, .systemTeal
    ]

    func attachContentRootIfNeeded() {
        guard let table = tableAnchorEntity, contentRoot == nil else { return }
        let root = Entity()
        root.name = "table-content"
        table.addChild(root)
        contentRoot = root
    }

    func setMode(_ newMode: TableMode) {
        guard newMode != mode else { return }
        clearModeContent()
        mode = newMode
        if newMode == .dominoes {
            game.resetBoardKeepingRules()
            statusLine = game.status
        } else {
            statusLine = "Tap the table to place a card plane."
        }
    }

    func getNextPlacedColor() -> UIColor {
        let color = placedColors[placedColorIndex % placedColors.count]
        placedColorIndex += 1
        return color
    }

    func nextCardLabel() -> String {
        cardLabelCounter += 1
        return "Card \(cardLabelCounter)"
    }

    func clearPlacedPlanes() {
        for card in cardEntities {
            card.removeFromParent()
        }
        cardEntities.removeAll()
        for anchor in placedAnchors {
            arView?.scene.removeAnchor(anchor)
        }
        placedAnchors.removeAll()
        DispatchQueue.main.async {
            self.placedCount = 0
        }
    }

    func clearModeContent() {
        aiWorkItem?.cancel()
        clearPlacedPlanes()
        for tile in tileEntities.values {
            tile.removeFromParent()
        }
        tileEntities.removeAll()
        boneyardEntity?.removeFromParent()
        boneyardEntity = nil
        clearEndMarkers()
        selectedTileID = nil
        game.resetBoardKeepingRules()
    }

    func clearEndMarkers() {
        for marker in endMarkerEntities {
            marker.removeFromParent()
        }
        endMarkerEntities.removeAll()
    }

    func worldToTable(_ world: SIMD3<Float>) -> SIMD3<Float> {
        guard let table = tableAnchorEntity else { return world }
        return table.convert(position: world, from: nil)
    }

    func placeCard(atWorldTransform worldTransform: simd_float4x4) {
        attachContentRootIfNeeded()
        guard let root = contentRoot else { return }

        let card = CardFactory.makeLabeledCard(label: nextCardLabel(), color: getNextPlacedColor())
        root.addChild(card)
        card.setTransformMatrix(worldTransform, relativeTo: nil)
        var local = card.position
        local.y = 0.006
        card.position = local

        if let arView {
            arView.installGestures([.translation], for: card)
        }
        cardEntities.append(card)
        DispatchQueue.main.async {
            self.placedCount = self.cardEntities.count
        }
    }

    func dealDominoes() {
        guard tableDetected else { return }
        attachContentRootIfNeeded()
        clearDominoVisualsOnly()
        game.rules = rules
        game.deal()
        layoutAllTiles(animated: false)
        refreshEndMarkers()
        DispatchQueue.main.async {
            self.statusLine = self.game.status
        }
        if game.phase == .playing, game.currentPlayer == .ai {
            scheduleAITurn()
        }
    }

    private func clearDominoVisualsOnly() {
        aiWorkItem?.cancel()
        for tile in tileEntities.values {
            tile.removeFromParent()
        }
        tileEntities.removeAll()
        boneyardEntity?.removeFromParent()
        boneyardEntity = nil
        clearEndMarkers()
        selectedTileID = nil
    }

    func layoutAllTiles(animated: Bool) {
        guard let root = contentRoot else { return }
        let layout = tableLayout()

        layoutHand(game.humanHand, owner: .human, along: layout.humanRow, faceUp: true, animated: animated)
        layoutHand(game.aiHand, owner: .ai, along: layout.aiRow, faceUp: false, animated: animated)
        layoutChain(alongAxis: layout.chainAxis, animated: animated)
        layoutBoneyard(at: layout.boneyard, parent: root)
    }

    private struct TableLayout {
        var humanRow: (origin: SIMD3<Float>, tangent: SIMD3<Float>)
        var aiRow: (origin: SIMD3<Float>, tangent: SIMD3<Float>)
        var chainAxis: SIMD3<Float>
        var boneyard: SIMD3<Float>
    }

    private func tableLayout() -> TableLayout {
        var towardUser = SIMD3<Float>(0, 0, 0.22)
        var along = SIMD3<Float>(1, 0, 0)

        if let arView, let table = tableAnchorEntity, let frame = arView.session.currentFrame {
            let cam = SIMD3<Float>(
                frame.camera.transform.columns.3.x,
                frame.camera.transform.columns.3.y,
                frame.camera.transform.columns.3.z
            )
            var localCam = table.convert(position: cam, from: nil)
            localCam.y = 0
            let length = simd_length(localCam)
            if length > 0.01 {
                towardUser = (localCam / length) * 0.20
            }
            along = simd_normalize(SIMD3<Float>(-towardUser.z, 0, towardUser.x))
        }

        return TableLayout(
            humanRow: (towardUser, along),
            aiRow: (-towardUser, along),
            chainAxis: along,
            boneyard: -along * 0.22
        )
    }

    private func layoutHand(
        _ tiles: [DominoFace],
        owner: TileOwner,
        along row: (origin: SIMD3<Float>, tangent: SIMD3<Float>),
        faceUp: Bool,
        animated: Bool
    ) {
        guard let root = contentRoot else { return }
        let spacing = DominoTileFactory.length + 0.006
        let start = -Float(max(tiles.count - 1, 0)) * spacing * 0.5
        let yaw = atan2(row.tangent.x, row.tangent.z) + .pi / 2

        for (index, face) in tiles.enumerated() {
            let entity = tileEntity(for: face, owner: owner, faceUp: faceUp, parent: root)
            let offset = row.tangent * (start + Float(index) * spacing)
            let target = row.origin + offset + SIMD3<Float>(0, DominoTileFactory.thickness / 2 + 0.001, 0)
            let yawRotation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            let flip = faceUp ? simd_quatf(angle: 0, axis: [1, 0, 0]) : simd_quatf(angle: .pi, axis: [1, 0, 0])
            move(entity, to: target, rotation: yawRotation * flip, animated: animated)
            enableDrag(entity, enabled: owner == .human && game.phase == .playing)
        }
    }

    private func chainSlots(along dir: SIMD3<Float>) -> [(played: PlayedDomino, position: SIMD3<Float>, extent: Float)] {
        guard !game.chain.isEmpty else { return [] }
        let y = DominoTileFactory.thickness / 2 + 0.0015
        var cursor = SIMD3<Float>(0, y, 0)
        var slots: [(PlayedDomino, SIMD3<Float>, Float)] = []
        for (index, played) in game.chain.enumerated() {
            let extent: Float = played.isCrosswise ? DominoTileFactory.width : DominoTileFactory.length
            if index > 0 {
                let previous = game.chain[index - 1]
                let prevExtent: Float = previous.isCrosswise ? DominoTileFactory.width : DominoTileFactory.length
                cursor += dir * ((prevExtent + extent) * 0.5 + DominoTileFactory.gap)
            }
            slots.append((played, cursor, extent))
        }
        if let first = slots.first?.1, let last = slots.last?.1 {
            let mid = (first + last) * 0.5
            slots = slots.map { ($0.0, $0.1 - SIMD3<Float>(mid.x, 0, mid.z), $0.2) }
        }
        return slots
    }

    private func layoutChain(alongAxis axis: SIMD3<Float>, animated: Bool) {
        guard contentRoot != nil else { return }
        let dir = simd_normalize(axis)
        for slot in chainSlots(along: dir) {
            let entity = tileEntity(for: slot.played.face, owner: .chain, faceUp: true, parent: contentRoot!)
            enableDrag(entity, enabled: false)

            var yaw = atan2(dir.x, dir.z) - .pi / 2
            if slot.played.growsLeft { yaw += .pi }
            if slot.played.face.b == slot.played.inwardValue && slot.played.face.a != slot.played.inwardValue {
                yaw += .pi
            }
            var rotation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            if slot.played.isCrosswise {
                rotation = simd_quatf(angle: yaw + .pi / 2, axis: [0, 1, 0])
            }
            move(entity, to: slot.position, rotation: rotation, animated: animated)
        }
    }

    private func layoutBoneyard(at position: SIMD3<Float>, parent: Entity) {
        if boneyardEntity == nil {
            let pile = ModelEntity(
                mesh: MeshResource.generateBox(
                    width: DominoTileFactory.length,
                    height: 0.018,
                    depth: DominoTileFactory.width,
                    cornerRadius: 0.002
                ),
                materials: [SimpleMaterial(color: DominoTileFactory.backColor, roughness: 0.5, isMetallic: false)]
            )
            pile.name = "boneyard"
            pile.generateCollisionShapes(recursive: true)
            parent.addChild(pile)
            boneyardEntity = pile
        }
        boneyardEntity?.position = position + SIMD3<Float>(0, 0.01, 0)
        boneyardEntity?.isEnabled = !game.boneyard.isEmpty && game.phase == .playing
    }

    func refreshEndMarkers() {
        clearEndMarkers()
        guard game.phase == .playing, !game.chain.isEmpty, let root = contentRoot else { return }

        let layout = tableLayout()
        let dir = simd_normalize(layout.chainAxis)
        let slots = chainSlots(along: dir)
        guard let first = slots.first, let last = slots.last else { return }
        let left = first.position - dir * (first.extent * 0.5 + 0.012) + SIMD3<Float>(0, 0.01, 0)
        let right = last.position + dir * (last.extent * 0.5 + 0.012) + SIMD3<Float>(0, 0.01, 0)

        for end in game.openEnds {
            let pos = end.side == .left ? left : right
            let marker = ModelEntity(
                mesh: MeshResource.generateSphere(radius: 0.007),
                materials: [UnlitMaterial(color: UIColor.systemMint.withAlphaComponent(0.85))]
            )
            marker.name = "end-\(end.side.rawValue)"
            marker.position = pos
            marker.generateCollisionShapes(recursive: true)
            root.addChild(marker)
            endMarkerEntities.append(marker)
        }
    }

    private func tileEntity(for face: DominoFace, owner: TileOwner, faceUp: Bool, parent: Entity) -> ModelEntity {
        if let existing = tileEntities[face.id] {
            if var component = existing.components[DominoTileComponent.self] {
                component.owner = owner
                component.faceUp = faceUp
                existing.components.set(component)
            }
            return existing
        }
        let entity = DominoTileFactory.makeTile(face: face, faceUp: faceUp, owner: owner)
        parent.addChild(entity)
        tileEntities[face.id] = entity
        return entity
    }

    private func move(_ entity: Entity, to position: SIMD3<Float>, rotation: simd_quatf, animated: Bool) {
        if animated {
            var transform = entity.transform
            transform.translation = position
            transform.rotation = rotation
            entity.move(to: transform, relativeTo: entity.parent, duration: 0.28, timingFunction: .easeInOut)
        } else {
            entity.position = position
            entity.orientation = rotation
        }
    }

    func enableDrag(_ entity: ModelEntity, enabled: Bool) {
        guard let arView else { return }
        arView.removeGestures(from: entity)
        draggingIDs.remove(entity.name)
        guard enabled else { return }
        let recognizers = arView.installGestures([.translation], for: entity)
        for recognizer in recognizers {
            recognizer.addTarget(self, action: #selector(handleTileGesture(_:)))
        }
        draggingIDs.insert(entity.name)
    }

    @objc func handleTileGesture(_ recognizer: EntityGestureRecognizer) {
        guard recognizer.state == .ended || recognizer.state == .cancelled else { return }
        guard let entity = recognizer.entity else { return }
        guard let component = entity.components[DominoTileComponent.self],
              component.owner == .human else {
            return
        }
        tryPlayDroppedTile(entity)
    }

    func tryPlayDroppedTile(_ entity: Entity) {
        guard game.phase == .playing, game.currentPlayer == .human else {
            layoutAllTiles(animated: true)
            return
        }
        guard let component = entity.components[DominoTileComponent.self] else { return }
        let tile = component.face

        if game.chain.isEmpty {
            let result = game.play(tile: tile, on: nil, player: .human)
            apply(result)
            return
        }

        let drop = entity.position
        var best: (end: OpenEnd, distance: Float)?
        for (index, end) in game.openEnds.enumerated() {
            guard tile.contains(end.value) else { continue }
            guard index < endMarkerEntities.count else { continue }
            let markerPos = endMarkerEntities[index].position
            let distance = simd_distance(SIMD3<Float>(drop.x, 0, drop.z), SIMD3<Float>(markerPos.x, 0, markerPos.z))
            if best == nil || distance < best!.distance {
                best = (end, distance)
            }
        }

        if let best, best.distance < 0.08, tile.contains(best.end.value) {
            let result = game.play(tile: tile, on: best.end, player: .human)
            apply(result)
        } else if let only = game.legalPlays(for: tile).first, game.legalPlays(for: tile).count == 1 {
            let result = game.play(tile: tile, on: only, player: .human)
            apply(result)
        } else {
            layoutAllTiles(animated: true)
            DispatchQueue.main.async {
                self.statusLine = "Drop a matching tile on a mint end marker. \(self.game.endSummary())."
            }
        }
    }

    func tapEntity(_ entity: Entity) {
        if entity.name == "boneyard" || entity.name == "boneyard-label" {
            humanDraw()
            return
        }
        if entity.name.hasPrefix("end-") {
            if let selected = selectedTileID,
               let face = game.humanHand.first(where: { $0.id == selected }) {
                let side: OpenEnd.Side = entity.name.contains("left") ? .left : .right
                if let end = game.openEnds.first(where: { $0.side == side }) {
                    let result = game.play(tile: face, on: end, player: .human)
                    apply(result)
                }
            }
            return
        }
        if let component = entity.components[DominoTileComponent.self], component.owner == .human {
            selectedTileID = component.face.id
            DispatchQueue.main.async {
                self.statusLine = "Selected \(self.game.label(component.face)). Drag onto an end or tap a mint marker."
            }
            return
        }
        if let parent = entity.parent, parent.components[DominoTileComponent.self] != nil {
            tapEntity(parent)
        }
    }

    func humanDraw() {
        guard game.phase == .playing, game.currentPlayer == .human else { return }
        guard game.rules == .draw else {
            DispatchQueue.main.async { self.statusLine = "Block rules — pass if you cannot play." }
            return
        }
        let drawn = game.drawUntilPlayableOrEmpty(player: .human)
        layoutAllTiles(animated: true)
        refreshEndMarkers()
        if game.playableTiles(for: .human).isEmpty {
            let result = game.pass(player: .human)
            apply(result)
        } else {
            DispatchQueue.main.async {
                self.statusLine = drawn.isEmpty
                    ? self.game.status
                    : "Drew \(drawn.count). Play a matching tile."
            }
        }
    }

    func humanPass() {
        let result = game.pass(player: .human)
        apply(result)
    }

    private func apply(_ result: DominoTurnResult) {
        layoutAllTiles(animated: true)
        refreshEndMarkers()
        selectedTileID = nil
        DispatchQueue.main.async {
            self.statusLine = result.message
        }
        if result.gameOver { return }
        if game.currentPlayer == .ai {
            scheduleAITurn()
        }
    }

    private func scheduleAITurn() {
        aiWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.performAITurn()
        }
        aiWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func performAITurn() {
        guard game.phase == .playing, game.currentPlayer == .ai else { return }

        if game.mustDrawOrPass(player: .ai) {
            if game.rules == .draw {
                _ = game.drawUntilPlayableOrEmpty(player: .ai)
            }
        }

        if let play = game.chooseAIPlay() {
            let result = game.play(tile: play.tile, on: play.end, player: .ai)
            apply(result)
        } else {
            let result = game.pass(player: .ai)
            apply(result)
        }
    }
}
