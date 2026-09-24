# TableAR

RealityKit + SwiftUI app that detects a horizontal table, tints that plane, and plays **Cards** or **Dominoes** on the same table anchor.

## Features

- First horizontal ARKit plane is the shared table
- Semi-transparent tint that grows as the plane is refined
- **Cards** mode: tap to place rounded, labeled, draggable card planes
- **Dominoes** mode on that same surface:
  - Double-six set (28 ivory 3D tiles)
  - Half-sphere pips, divider, dark back face
  - Draw and Block rules
  - Human vs simple table AI
  - Drag a matching tile onto a mint end marker (or tap the marker)
  - Boneyard pile on the table
- Clear / Redeal without losing the table anchor

## Requirements

- Xcode 15+
- iOS 16+
- Physical iPhone or iPad (AR does not work well in Simulator)
- Camera permission

LiDAR devices give more stable planes, but the app works on any ARKit device.

## Setup

1. Create a new Xcode project: **iOS → App**, SwiftUI, Swift.
2. Add every `.swift` file in this repo to the app target. Remove the template `ContentView.swift` if it conflicts (`TableARApp.swift` already contains `@main`).
3. In the target **Info** tab, add:
   - **Privacy – Camera Usage Description**: `This app uses the camera for augmented reality to detect tables and place virtual objects.`
4. Build and run on a device.

## How to play Dominoes

1. Scan a table until the tint appears.
2. Switch the segmented control to **Dominoes**.
3. Pick **Draw** or **Block**, then **Deal**.
4. Your tiles sit face-up on the near edge; the opponent is face-down on the far edge; the chain grows in the middle.
5. Highest double (or highest tile) starts. If the opponent starts, they play first.
6. Drag a matching tile onto a mint end marker. Doubles sit crosswise.
7. **Draw**: if you cannot play, tap the boneyard (or **Draw**) until you can, then pass only if the boneyard is empty.
8. **Block**: if you cannot play, **Pass**. The hand ends when both players pass or someone goes out.
9. Score is leftover pips in the opponent’s hand.

## Notes

This repository is source-only (no `.xcodeproj`). Drop the Swift files into a new Xcode app target as described above.

Shared RealityKit sessions cannot be sent natively to Android. For colocated or remote multiplayer across platforms, use Unity AR Foundation (and optionally Niantic Lightship).
