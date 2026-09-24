# TableAR

RealityKit + SwiftUI app that detects a horizontal table surface, tints it, and lets you place rounded, labeled, draggable plane objects on it.

## Features

- Horizontal plane detection (first large surface treated as the table)
- Semi-transparent color overlay that grows as ARKit refines the plane
- Tap to place colorful rounded planes
- Drag placed planes around
- Labels on placed planes
- Clear-all button

## Requirements

- Xcode 15+
- iOS 16+
- Physical iPhone or iPad (AR does not work well in Simulator)
- Camera permission

LiDAR devices give more stable planes, but the app works on any ARKit device.

## Setup

1. Create a new Xcode project: **iOS → App**, SwiftUI, Swift.
2. Replace `ContentView.swift` (or add this file and set it as the app entry) with `TableARApp.swift`.
3. In the target **Info** tab, add:
   - **Privacy – Camera Usage Description**: `This app uses the camera for augmented reality to detect tables and place virtual objects.`
4. Build and run on a device.

## Notes

This repository is source-only (no `.xcodeproj`). Drop the Swift file into a new Xcode app target as described above.

Shared RealityKit sessions cannot be sent natively to Android. For colocated or remote multiplayer across platforms, use Unity AR Foundation (and optionally Niantic Lightship).
