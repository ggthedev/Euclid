//
//  CSG.swift
//  Euclid
//
//  Created by Nick Lockwood on 03/07/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//
//  Distributed under the permissive MIT license
//  Get the latest version from here:
//
//  https://github.com/nicklockwood/Euclid
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

// Inspired by: https://github.com/evanw/csg.js

public extension Mesh {
    /// Returns a new mesh representing the combined volume of the
    /// mesh parameter and the receiver, with inner faces removed.
    ///
    ///     +-------+            +-------+
    ///     |       |            |       |
    ///     |   A   |            |       |
    ///     |    +--+----+   =   |       +----+
    ///     +----+--+    |       +----+       |
    ///          |   B   |            |       |
    ///          |       |            |       |
    ///          +-------+            +-------+
    ///
    func union(_ mesh: Mesh) -> Mesh {
        let ap = BSPNode(mesh.polygons).clip(polygons, .greaterThan)
        let bp = BSPNode(polygons).clip(mesh.polygons, .greaterThanEqual)
        return Mesh(unchecked: ap + bp)
    }

    /// Efficiently form union from multiple meshes
    static func union(_ meshes: [Mesh]) -> Mesh {
        return multimerge(meshes, using: { $0.union($1) })
    }

    /// Returns a new mesh created by subtracting the volume of the
    /// mesh parameter from the receiver.
    ///
    ///     +-------+            +-------+
    ///     |       |            |       |
    ///     |   A   |            |       |
    ///     |    +--+----+   =   |    +--+
    ///     +----+--+    |       +----+
    ///          |   B   |
    ///          |       |
    ///          +-------+
    ///
    func subtract(_ mesh: Mesh) -> Mesh {
        let ap = BSPNode(mesh.polygons).clip(polygons, .greaterThan)
        let bp = BSPNode(polygons).clip(mesh.polygons, .lessThan)
        return Mesh(unchecked: ap + bp.map { $0.inverted() })
    }

    /// Efficiently subtract multiple meshes
    static func difference(_ meshes: [Mesh]) -> Mesh {
        return reduce(meshes, using: { $0.subtract($1) })
    }

    /// Returns a new mesh reprenting only the volume exclusively occupied by
    /// one shape or the other, but not both.
    ///
    ///     +-------+            +-------+
    ///     |       |            |       |
    ///     |   A   |            |       |
    ///     |    +--+----+   =   |    ++++----+
    ///     +----+--+    |       +----++++    |
    ///          |   B   |            |       |
    ///          |       |            |       |
    ///          +-------+            +-------+
    ///
    func xor(_ mesh: Mesh) -> Mesh {
        let absp = BSPNode(polygons)
        let bbsp = BSPNode(mesh.polygons)
        // TODO: combine clip operations
        let ap1 = bbsp.clip(polygons, .greaterThan)
        let bp1 = absp.clip(mesh.polygons, .lessThan)
        let ap2 = bbsp.clip(polygons, .lessThan)
        let bp2 = absp.clip(mesh.polygons, .greaterThan)
        // Avoids slow compilation from long expression
        let lhs = ap1 + bp1.map { $0.inverted() }
        let rhs = bp2 + ap2.map { $0.inverted() }
        return Mesh(unchecked: lhs + rhs)
    }

    /// Efficiently xor multiple meshes
    static func xor(_ meshes: [Mesh]) -> Mesh {
        return multimerge(meshes, using: { $0.xor($1) })
    }

    /// Returns a new mesh reprenting the volume shared by both the mesh
    /// parameter and the receiver. If these do not intersect, an empty
    /// mesh will be returned.
    ///
    ///     +-------+
    ///     |       |
    ///     |   A   |
    ///     |    +--+----+   =   +--+
    ///     +----+--+    |       +--+
    ///          |   B   |
    ///          |       |
    ///          +-------+
    ///
    func intersect(_ mesh: Mesh) -> Mesh {
        let ap = BSPNode(mesh.polygons).clip(polygons, .lessThan)
        let bp = BSPNode(polygons).clip(mesh.polygons, .lessThanEqual)
        return Mesh(unchecked: ap + bp)
    }

    /// Efficiently compute intersection of multiple meshes
    static func intersection(_ meshes: [Mesh]) -> Mesh {
        return reduce(meshes, using: { $0.intersect($1) })
    }

    /// Returns a new mesh that retains the shape of the receiver, but with
    /// the intersecting area colored using material from the parameter.
    ///
    ///     +-------+            +-------+
    ///     |       |            |       |
    ///     |   A   |            |       |
    ///     |    +--+----+   =   |    +--+
    ///     +----+--+    |       +----+--+
    ///          |   B   |
    ///          |       |
    ///          +-------+
    ///
    func stencil(_ mesh: Mesh) -> Mesh {
        // TODO: combine clip operations
        let bsp = BSPNode(mesh.polygons)
        let outside = bsp.clip(polygons, .greaterThan)
        let inside = bsp.clip(mesh.polygons, .lessThanEqual)
        return Mesh(unchecked: outside + inside.map {
            Polygon(
                unchecked: $0.vertices,
                plane: $0.plane,
                isConvex: $0.isConvex,
                material: mesh.polygons.first?.material ?? $0.material
            )
        })
    }

    /// Efficiently perform stencil with multiple meshes
    static func stencil(_ meshes: [Mesh]) -> Mesh {
        return reduce(meshes, using: { $0.stencil($1) })
    }

    /// Split mesh along a plane
    func split(along plane: Plane) -> (Mesh?, Mesh?) {
        var id = 0
        var coplanar = [Polygon](), front = [Polygon](), back = [Polygon]()
        for polygon in polygons {
            polygon.split(along: plane, &coplanar, &front, &back, &id)
        }
        for polygon in coplanar where plane.normal.dot(polygon.plane.normal) > 0 {
            front.append(polygon)
        }
        return (front.isEmpty ? nil : Mesh(unchecked: front), back.isEmpty ? nil : Mesh(unchecked: back))
    }

    /// Clip mesh to a plane and optionally fill sheared aces with specified material
    func clip(to plane: Plane, fill: Polygon.Material = nil) -> Mesh {
        var id = 0
        var coplanar = [Polygon](), front = [Polygon](), back = [Polygon]()
        for polygon in polygons {
            polygon.split(along: plane, &coplanar, &front, &back, &id)
        }
        for polygon in coplanar where plane.normal.dot(polygon.plane.normal) > 0 {
            front.append(polygon)
        }
        let mesh = Mesh(front)
        guard let material = fill else {
            return mesh
        }
        // Project each corner of mesh bounds onto plan to find radius
        var radius = 0.0
        for corner in mesh.bounds.corners {
            let p = corner.project(onto: plane)
            radius = max(radius, p.lengthSquared)
        }
        radius = radius.squareRoot()
        // Create back face
        let normal = Vector(0, 0, 1)
        let angle = -normal.angle(with: plane.normal)
        let axis = normal.cross(plane.normal).normalized()
        let rotation = Rotation(unchecked: axis, radians: angle)
        let rect = Polygon(
            unchecked: [
                Vertex(Vector(-radius, radius, 0), -normal, .zero),
                Vertex(Vector(radius, radius, 0), -normal, Vector(1, 0, 0)),
                Vertex(Vector(radius, -radius, 0), -normal, Vector(1, 1, 0)),
                Vertex(Vector(-radius, -radius, 0), -normal, Vector(0, 1, 0)),
            ],
            normal: -normal,
            isConvex: true,
            material: material
        )
        .rotated(by: rotation)
        .translated(by: plane.normal * plane.w)
        // Clip rect
        return Mesh(mesh.polygons + BSPNode(polygons).clip([rect], .lessThan))
    }
}

// Merge all the meshes into a single mesh using fn
private func multimerge(_ meshes: [Mesh], using fn: (Mesh, Mesh) -> Mesh) -> Mesh {
    var mesh = Mesh([])
    var meshesAndBounds = meshes.map { ($0, $0.bounds) }
    var i = 0
    while i < meshesAndBounds.count {
        let m = reduce(&meshesAndBounds, at: i, using: fn)
        mesh = mesh.merge(m)
        i += 1
    }
    return mesh
}

// Merge each intersecting mesh after i into the mesh at index i using fn
private func reduce(_ meshes: [Mesh], using fn: (Mesh, Mesh) -> Mesh) -> Mesh {
    var meshesAndBounds = meshes.map { ($0, $0.bounds) }
    return reduce(&meshesAndBounds, at: 0, using: fn)
}

private func reduce(
    _ meshesAndBounds: inout [(Mesh, Bounds)],
    at i: Int,
    using fn: (Mesh, Mesh) -> Mesh
) -> Mesh {
    var (m, mb) = meshesAndBounds[i]
    var j = i + 1, count = meshesAndBounds.count
    while j < count {
        let (n, nb) = meshesAndBounds[j]
        if mb.intersects(nb) {
            m = fn(m, n)
            mb = m.bounds
            meshesAndBounds[i] = (m, mb)
            meshesAndBounds.remove(at: j)
            count -= 1
            continue
        }
        j += 1
    }
    return m
}
