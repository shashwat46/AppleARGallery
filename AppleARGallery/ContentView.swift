import SwiftUI
import RealityKit
import ARKit
import AVKit

struct ContentView: View {
    var body: some View {
        ZStack{
            ARViewContainer().edgesIgnoringSafeArea(.all)
            VStack{
                Text("Initializing AR View...")
                    .foregroundColor(.red)
                    .background(Color.black.opacity(0.5))
                Spacer()
            }
            
            
        }
        
    }
}

struct ARViewContainer: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.session.delegate = context.coordinator
        context.coordinator.arView = arView

        // Load image tracking configuration
        guard let referenceImages = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) else {
            fatalError("Missing AR Resources")
        }

        let config = ARWorldTrackingConfiguration()
        config.detectionImages = referenceImages
        config.maximumNumberOfTrackedImages = 1

        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

class Coordinator: NSObject, ARSessionDelegate {
    var arView: ARView!

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let imageAnchor = anchor as? ARImageAnchor else { continue }

            DispatchQueue.main.async {
                self.displayGallery(over: imageAnchor)
            }
        }
    }

    func displayGallery(over imageAnchor: ARImageAnchor) {
        let anchorEntity = AnchorEntity()
        anchorEntity.transform = Transform(matrix: imageAnchor.transform)

        let spacing: Float = 0.25
        let videoNames = ["iphone15", "visionpro", "macbook", "airpods"]

        for (index, name) in videoNames.enumerated() {
            guard let url = Bundle.main.url(forResource: name, withExtension: "mp4") else { continue }

            let playerItem = AVPlayerItem(url: url)
            let player = AVQueuePlayer(playerItem: playerItem)
            let _ = AVPlayerLooper(player: player, templateItem: playerItem)
            player.play()

            let videoMaterial = VideoMaterial(avPlayer: player)
            let plane = ModelEntity(mesh: .generatePlane(width: 0.2, height: 0.1125), materials: [videoMaterial])
            plane.position = SIMD3(Float(index) * spacing - 0.3, 0, 0)

            anchorEntity.addChild(plane)
        }

        arView.scene.addAnchor(anchorEntity)
    }
}

