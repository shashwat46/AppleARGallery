import SwiftUI
import RealityKit
import ARKit
import AVFoundation


struct ContentView: View {
    var body: some View {
        ARViewContainer().edgesIgnoringSafeArea(.all)
    }
}

struct ARViewContainer: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView
        arView.session.delegate = context.coordinator

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)

        guard let referenceImages = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) else {
            fatalError("Missing AR Resources group in asset catalog.")
        }

        let config = ARWorldTrackingConfiguration()
        config.detectionImages = referenceImages
        config.maximumNumberOfTrackedImages = 1

        print("Running AR session configuration...")
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        print("ARView initialized, session delegate set, tap gesture added.")

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

@MainActor
class Coordinator: NSObject, ARSessionDelegate {
    weak var arView: ARView?
    let allVideoNames = ["iphone15", "visionpro", "macbook", "airpods"]
    private var currentVideoIndex = 0

    private var currentVideoEntity: ModelEntity?
    private var currentPlayer: AVQueuePlayer?
    private var currentPlayerLooper: AVPlayerLooper?
    private var currentItemObserver: NSKeyValueObservation?

    private var galleryAnchorEntity: AnchorEntity?
    private var layoutEntity: Entity?
    private var anchorHasBeenAdded = false

    @objc func handleTap(_ sender: UITapGestureRecognizer) {
        print("handleTap function called.")
        guard let arView = arView else {
            print("handleTap: ARView is nil.")
            return
        }
        guard currentVideoEntity != nil else {
            print("handleTap: currentVideoEntity is nil (no video showing?).")
            return
        }

        let tapLocation = sender.location(in: arView)
        print("handleTap: Tap location: \(tapLocation)")

        if let tappedEntity = arView.entity(at: tapLocation) {
            print("handleTap: Hit entity: \(tappedEntity.name) (ID: \(tappedEntity.id))")

            if tappedEntity == currentVideoEntity {
                print("handleTap: Tap HIT the current video entity!")
                currentVideoIndex = (currentVideoIndex + 1) % allVideoNames.count
                print("handleTap: Advancing to index \(currentVideoIndex)")
                displayVideo(at: currentVideoIndex)
            } else {
                print("handleTap: Tap hit some OTHER entity, not the current video.")
            }
        } else {
            print("handleTap: Tap hit NO entity.")
        }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        print("ARSession didAdd anchors: \(anchors.count)")
        for anchor in anchors {
            guard let imageAnchor = anchor as? ARImageAnchor,
                  let referenceImageName = imageAnchor.referenceImage.name,
                  referenceImageName == "Apple_Poster"
            else {
                continue
            }

            print("Detected target image anchor: \(referenceImageName)")

            guard self.galleryAnchorEntity == nil else {
                print("Already processing an anchor.")
                return
            }

            let anchorEntity = AnchorEntity()
            anchorEntity.anchoring = AnchoringComponent(.anchor(identifier: imageAnchor.identifier))
            self.galleryAnchorEntity = anchorEntity

            let layoutHolder = Entity()
            anchorEntity.addChild(layoutHolder)
            self.layoutEntity = layoutHolder

            self.anchorHasBeenAdded = false

            print("Setting up initial video...")
            displayVideo(at: currentVideoIndex)
        }
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
         print("ARSession didRemove anchors: \(anchors.count)")
         for anchor in anchors {
             if let imageAnchor = anchor as? ARImageAnchor, galleryAnchorEntity?.anchorIdentifier == imageAnchor.identifier {
                 print("Target image anchor removed.")
                 cleanupCurrentVideo()
                 if let anchor = galleryAnchorEntity {
                     arView?.scene.removeAnchor(anchor)
                     galleryAnchorEntity = nil
                     print("Gallery anchor removed from scene.")
                 }
                 layoutEntity = nil
                 anchorHasBeenAdded = false
             }
         }
     }

    private func displayVideo(at index: Int) {
        guard index >= 0 && index < allVideoNames.count else {
            print("Error: Invalid video index \(index)")
            return
        }

        cleanupCurrentVideo()

        let name = allVideoNames[index]
        print("Attempting to display video: \(name) at index \(index)")
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp4") else {
            print("Error: Could not find video file \(name).mp4")
            return
        }

        let playerItem = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: playerItem)
        self.currentPlayer = player

        print("Setting up KVO for \(name)...")
        currentItemObserver = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
             Task { @MainActor [weak self] in
                guard let self = self else { return }

                switch item.status {
                case .readyToPlay:
                    print("Player item ready for \(name)")
                    guard let player = self.currentPlayer else {
                        print("Player became nil before ready.")
                        return
                    }

                    let videoMaterial = VideoMaterial(avPlayer: player)
                    let plane = ModelEntity(mesh: .generatePlane(width: 0.4, height: 0.225), materials: [videoMaterial])
                    plane.name = "VideoPlane_\(name)"
                    
                    plane.generateCollisionShapes(recursive: false)
                    print("Generated collision shape for \(plane.name)")

                    plane.components.set(BillboardComponent())

                    plane.position = .zero

                    self.currentVideoEntity = plane

                    if let layoutHolder = self.layoutEntity {
                         layoutHolder.addChild(plane)
                         print("Added video plane for \(name) to layout entity.")
                    } else {
                         print("Error: Layout entity not found when trying to add plane.")
                         self.currentVideoEntity = nil
                         return
                    }

                    let looper = AVPlayerLooper(player: player, templateItem: item)
                    self.currentPlayerLooper = looper
                    player.play()
                    print("Playing video: \(name)")

                     if !self.anchorHasBeenAdded {
                         if let scene = self.arView?.scene, let mainAnchor = self.galleryAnchorEntity {
                            if !scene.anchors.contains(where: { $0 == mainAnchor }) {
                                print("Adding gallery anchor entity to the scene.")
                                scene.addAnchor(mainAnchor)
                                self.anchorHasBeenAdded = true
                            }
                        } else {
                            print("Error: Could not get ARView scene or main anchor to add anchor.")
                        }
                    }


                case .failed:
                    print("Error: Player item failed to load for \(name). Error: \(item.error?.localizedDescription ?? "unknown error")")
                    self.cleanupCurrentVideo()

                case .unknown:
                     print("Player item status unknown for \(name).")

                @unknown default:
                     print("Player item status encountered an unknown default case for \(name).")
                }
             }
        }
    }

    private func cleanupCurrentVideo() {
        print("Cleaning up current video resources...")

        currentPlayer?.pause()
        currentPlayer = nil
        print("Current player paused and released.")

        currentPlayerLooper = nil

        currentItemObserver?.invalidate()
        currentItemObserver = nil
        print("Current KVO observer invalidated.")

        if let entity = currentVideoEntity {
            entity.removeFromParent()
            currentVideoEntity = nil
            print("Current video entity removed from parent.")
        }
    }

}
