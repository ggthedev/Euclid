//
//  SceneViewController.swift
//  Example
//
//  Created by Nick Lockwood on 11/12/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Euclid
import SceneKit
import UIKit

class SceneViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        // create a new scene
        let scene = SCNScene()

        // create and add a camera to the scene
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        scene.rootNode.addChildNode(cameraNode)

        // place the camera
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 3)

        // create some geometry using Euclid
        let start = CFAbsoluteTimeGetCurrent()
        let extrusion = Mesh.extrude(Path([
            .point(-0.5, -0.5),
            .point(0.5, -0.5),
            .point(0.5, -0.3),
            .point(0.2, -0.3),
            .point(0.2, 0.3),
            .point(0.5, 0.3),
            .point(0.5, 0.5),
            .point(-0.5, 0.5),
            .point(-0.5, -0.5),
        ]), material: UIColor.red)
        let sphere = Mesh.sphere(slices: 120, material: UIColor.blue).translated(by: Vector(-0.1, 0, 0))
        let mesh = extrusion.subtract(sphere)
        print("Time:", CFAbsoluteTimeGetCurrent() - start)
        print("Polys:", mesh.polygons.count)

        // create SCNNode
        let geometry = SCNGeometry(mesh) {
            let material = SCNMaterial()
            material.diffuse.contents = $0 as? UIColor
            return material
        }
        let node = SCNNode(geometry: geometry)
        scene.rootNode.addChildNode(node)

        // configure the SCNView
        let scnView = view as! SCNView
        scnView.scene = scene
        scnView.autoenablesDefaultLighting = true
        scnView.allowsCameraControl = true
        scnView.showsStatistics = true
        scnView.backgroundColor = .white
    }

    override var shouldAutorotate: Bool {
        return true
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
}
