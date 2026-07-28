//
//  ContentView.swift
//  DecisionMaker Watch App
//
//  Created by Camille Kao on 7/28/26.
//

import SwiftUI
import SceneKit


struct CoinFaceView: View {
    let text: String
    let iconName: String
    let flip: Bool
    
    var body: some View {
        ZStack {
            // Background
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.95, green: 0.80, blue: 0.25), Color(red: 0.75, green: 0.55, blue: 0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Outer Border Ring
            Circle()
                .strokeBorder(Color.white.opacity(0.4), lineWidth: 10)
                .padding(15)
            
            // Text & Icon Content
            VStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 80, weight: .bold))
                
                Text(text)
                    .font(.system(size: 60, weight: .black, design: .rounded))
            }
            .foregroundColor(Color(white: 0.15))
            .rotationEffect(.degrees(-90))
        }
        .frame(width: 512, height: 512)
        .scaleEffect(x: -1, y: 1)
        .rotationEffect(.degrees(flip ? 180 : 0))
    }
}

@MainActor
func createTextTextureSwiftUI(text: String, icon: String, flip: Bool) -> CGImage? {
    // 1. Instantiate the view
    let view = CoinFaceView(text: text, iconName: icon, flip: flip)
    
    // 2. Initialize ImageRenderer with the SwiftUI view
    let renderer = ImageRenderer(content: view)
    
    // 3. Match screen resolution density (optional but improves sharpness)
    renderer.scale = 2.0
    
    // 4. Extract CGImage (or renderer.uiImage) for SceneKit
    return renderer.cgImage
}

struct ContentView: View {
    
    @State var sceneView: SCNScene = {
        let scene = SCNScene()
        
        let coin = SCNCylinder(radius: 2, height: 0.1)

        // 2. Create Rim Material (Index 0)
        let rimMaterial = SCNMaterial()
        rimMaterial.diffuse.contents = UIColor(red: 0.85, green: 0.65, blue: 0.13, alpha: 1.0)
        rimMaterial.metalness.contents = 0.9 // High reflectivity
        rimMaterial.roughness.contents = 0.2
            
        // 3. Create "HEADS" Top Material (Index 1)
        let headsMaterial = SCNMaterial()
        headsMaterial.diffuse.contents = createTextTextureSwiftUI(text: "HEADS", icon: "crown.fill", flip: false)
        headsMaterial.metalness.contents = 0.8
        headsMaterial.roughness.contents = 0.3
        
        // 4. Create "TAILS" Bottom Material (Index 2)
        let tailsMaterial = SCNMaterial()
        tailsMaterial.diffuse.contents = createTextTextureSwiftUI(text: "TAILS", icon: "building.columns.fill", flip: true)
        tailsMaterial.metalness.contents = 0.8
        tailsMaterial.roughness.contents = 0.3

        coin.materials = [rimMaterial, headsMaterial, tailsMaterial]
        
        let node = SCNNode(geometry:  coin)
        
        node.position = SCNVector3(x: 0, y: 0, z: 0)
        node.name = "CoinNode"
        
        scene.rootNode.addChildNode(node)
        
        // 1. Create a Camera Node
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()

        // 2. Position the camera (Equal Y and Z distances = 45 degree angle)
        // Adjust the distance (e.g., y: 3, z: 3) to zoom in or out
        cameraNode.position = SCNVector3(x: 0, y: 6, z: 2)

        // 3. Constrain the camera to look directly at the coin
        let lookAtConstraint = SCNLookAtConstraint(target: node)
        lookAtConstraint.isGimbalLockEnabled = true // Prevents weird camera tilting
        cameraNode.constraints = [lookAtConstraint]

        // 4. Add Camera to Scene
        scene.rootNode.addChildNode(cameraNode)
        
        return scene
    }()
    
    @State private var isFlipping = false
    @State private var resultText = "Tap Coin"
    
    private func completeFlip(isHeads: Bool, targetXRotation: Float, coinNode: SCNNode) {
        guard isFlipping else { return } // Prevent double execution
        coinNode.eulerAngles = SCNVector3(targetXRotation, 0, 0)
        isFlipping = false
        resultText = isHeads ? "HEADS!" : "TAILS!"
        WKInterfaceDevice.current().play(.click)
    }
    
    private func flipCoin() {
        guard let coinNode = sceneView.rootNode.childNode(withName: "CoinNode", recursively: false),
              !isFlipping else { return }
        
        isFlipping = true
        resultText = "Flipping..."

        let isHeads = Bool.random()
        let targetXRotation: Float = isHeads ? 0.0 : .pi
        
        let currentXRotation = coinNode.eulerAngles.x.truncatingRemainder(dividingBy: .pi * 2)
        
        var deltaRotation = targetXRotation - currentXRotation
        if deltaRotation < 0 {
            deltaRotation += .pi * 2
        }
        
        let totalXRotation = deltaRotation + (.pi * 2 * 4)

        let duration: TimeInterval = 1.0
        
        let jumpUp = SCNAction.moveBy(x: 0, y: 1.5, z: 0, duration: duration / 2)
        jumpUp.timingMode = .easeOut
        let fallDown = SCNAction.moveBy(x: 0, y: -1.5, z: 0, duration: duration / 2)
        fallDown.timingMode = .easeIn
        
        let spin = SCNAction.rotateBy(x: CGFloat(totalXRotation), y: 0, z: 0, duration: duration)
        spin.timingMode = .easeInEaseOut

        let group = SCNAction.group([SCNAction.sequence([jumpUp, fallDown]), spin])
    
    // 🚨 Fallback safety reset in case the completion handler fails to fire
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.2) {
            if self.isFlipping {
                print("Warning: SCNAction completion timed out. Forcing reset.")
                self.completeFlip(isHeads: isHeads, targetXRotation: targetXRotation, coinNode: coinNode)
            }
        }

        print("before runAction")
        coinNode.runAction(group) {
            coinNode.eulerAngles = SCNVector3(targetXRotation, 0, 0)
            isFlipping = false
            resultText = isHeads ? "HEADS!" : "TAILS!"
            
            // Trigger watchOS haptic feedback upon landing
            WKInterfaceDevice.current().play(.click)
        }
        
    }

    var body: some View {
        VStack {
            Text(resultText)
                .font(.footnote)
                .bold()

            SceneView(
                scene: sceneView, // Pass persistent state here
                options: [.autoenablesDefaultLighting]
            )
            .onTapGesture {
                flipCoin()
            }
        }
    }
    
}

#Preview {
    ContentView()
}
