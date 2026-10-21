import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

import Foundation

// Standard 3D Perlin noise generator with permutation table
//   (256 ints shuffled), 16 gradient vectors, lerp/fade interpolation.
//   Used for organic displacement effects in media player visualization.
class PerlinNoiseGenerator {

    // MARK: - Constants

    //   Contains shuffled indices 0..255, duplicated (512 total) for wrapping
    private var perm: [Int] = []

    //   Unit vectors for gradient dot-product lookup
    private let gradVectors: [(Double, Double, Double)] = [
        (1, 1, 0), (-1, 1, 0), (1, -1, 0), (-1, -1, 0),
        (1, 0, 1), (-1, 0, 1), (1, 0, -1), (-1, 0, -1),
        (0, 1, 1), (0, -1, 1), (0, 1, -1), (0, -1, -1),
        (1, 1, 0), (1, -1, 0), (-1, 1, 0), (-1, -1, 0),
    ]

    // MARK: - Init

    //   Fills a 256-entry table with 0..255,
    //   then shuffles using SystemRandomNumberGenerator.
    //   Duplicates the table (appends to self) for 512 entries.
    init() {
        let size = 256
        var table = [Int](repeating: 0, count: size)

        for i in 0..<size {
            table[i] = i
        }

        table.shuffle()

        self.perm = table + table
    }

    // MARK: - Noise

    //   Classic 3D Perlin noise:
    //   1. Floor to integer cube corners: xi = int(floor(x)) & 255, yi, zi
    //   2. Fractional offsets: xf = x - floor(x), yf, zf
    //   3. Fade curves: fade(t) = t^3 * (t * (t * 6 - 15) + 10)
    //   4. Hash: perm[perm[perm[xi] + yi] + zi] & 15 → gradient index
    //   5. Grad dot products at 8 corners
    //   6. Lerp along x, y, z axes
    func noise(x: Double, y: Double, z: Double) -> Double {
        let xi = Int(floor(x)) & 255
        let yi = Int(floor(y)) & 255
        let zi = Int(floor(z)) & 255

        var xf = x - floor(x)
        var yf = y - floor(y)
        var zf = z - floor(z)

        func fade(_ t: Double) -> Double {
            return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
        }

        let u = fade(xf)
        let v = fade(yf)
        let w = fade(zf)

        let aaa = perm[perm[perm[xi] + yi] + zi]
        let aba = perm[perm[perm[xi] + yi + 1] + zi]
        let aab = perm[perm[perm[xi] + yi] + zi + 1]
        let abb = perm[perm[perm[xi] + yi + 1] + zi + 1]
        let baa = perm[perm[perm[xi + 1] + yi] + zi]
        let bba = perm[perm[perm[xi + 1] + yi + 1] + zi]
        let bab = perm[perm[perm[xi + 1] + yi] + zi + 1]
        let bbb = perm[perm[perm[xi + 1] + yi + 1] + zi + 1]

        func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
            return a + t * (b - a)
        }

        func grad(_ hash: Int, _ dx: Double, _ dy: Double, _ dz: Double) -> Double {
            let h = hash & 15
            let g = gradVectors[h]
            return g.0 * dx + g.1 * dy + g.2 * dz
        }

        let x1 = lerp(grad(aaa, xf, yf, zf), grad(baa, xf - 1, yf, zf), u)
        let x2 = lerp(grad(aba, xf, yf - 1, zf), grad(bba, xf - 1, yf - 1, zf), u)
        let y1 = lerp(x1, x2, v)

        let x1b = lerp(grad(aab, xf, yf, zf - 1), grad(bab, xf - 1, yf, zf - 1), u)
        let x2b = lerp(grad(abb, xf, yf - 1, zf - 1), grad(bbb, xf - 1, yf - 1, zf - 1), u)
        let y2 = lerp(x1b, x2b, v)

        return lerp(y1, y2, w)
    }
}
