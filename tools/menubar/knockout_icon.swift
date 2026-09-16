// knockout_icon.swift — make an icon PNG's white surround transparent.
//
// Flood-fills from the four corners through near-white pixels, so white
// artwork INSIDE the icon is never touched (the icon body walls it off),
// then un-mixes the anti-aliased rim against white so the edge fades
// instead of leaving a grey fringe. Also writes a preview on magenta so any
// leftover halo is obvious.
//
//   swiftc -O -o /tmp/knockout knockout_icon.swift
//   /tmp/knockout in.png AppIcon.png preview.png

import AppKit
import CoreGraphics

let args = CommandLine.arguments
let inURL = URL(fileURLWithPath: args[1]), outURL = URL(fileURLWithPath: args[2])
let previewURL = URL(fileURLWithPath: args[3])

guard let src = CGImageSourceCreateWithURL(inURL as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("load") }
let w = img.width, h = img.height
var px = [UInt8](repeating: 0, count: w * h * 4)
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

func idx(_ x: Int, _ y: Int) -> Int { (y * w + x) * 4 }
func bright(_ i: Int) -> Int { min(Int(px[i]), Int(px[i+1]), Int(px[i+2])) }

// Reference fill colour of the icon body, sampled well inside the square.
let ci = idx(w / 2, h / 6)
let fill = (Double(px[ci]), Double(px[ci+1]), Double(px[ci+2]))

// 1) Flood-fill background from the corners through near-white pixels.
var bg = [Bool](repeating: false, count: w * h)
var stack = [(0,0), (w-1,0), (0,h-1), (w-1,h-1)]
while let (x, y) = stack.popLast() {
    if x < 0 || y < 0 || x >= w || y >= h { continue }
    let k = y * w + x
    if bg[k] || bright(k * 4) < 232 { continue }
    bg[k] = true
    stack.append((x+1,y)); stack.append((x-1,y)); stack.append((x,y+1)); stack.append((x,y-1))
}

// 2) Distance (in px) from the background, for a thin rim band.
let BAND = 10
var dist = [Int](repeating: Int.max, count: w * h)
var q = [Int](); q.reserveCapacity(w * h / 4)
for k in 0..<(w*h) where bg[k] { dist[k] = 0; q.append(k) }
var head = 0
while head < q.count {
    let k = q[head]; head += 1
    let d = dist[k]; if d >= BAND { continue }
    let x = k % w, y = k / w
    for (nx, ny) in [(x+1,y),(x-1,y),(x,y+1),(x,y-1)] where nx >= 0 && ny >= 0 && nx < w && ny < h {
        let nk = ny * w + nx
        if dist[nk] > d + 1 { dist[nk] = d + 1; q.append(nk) }
    }
}

// 3) Write alpha. Background -> clear. Rim -> un-mix against white:
//    observed = a*fill + (1-a)*255  =>  a = (255-observed)/(255-fill)
var cleared = 0, blended = 0
for k in 0..<(w*h) {
    let i = k * 4
    if bg[k] { px[i] = 0; px[i+1] = 0; px[i+2] = 0; px[i+3] = 0; cleared += 1; continue }
    if dist[k] <= BAND {
        let c = (Double(px[i]), Double(px[i+1]), Double(px[i+2]))
        let a0 = (255 - c.0) / max(1, 255 - fill.0)
        let a1 = (255 - c.1) / max(1, 255 - fill.1)
        let a2 = (255 - c.2) / max(1, 255 - fill.2)
        let a = max(0, min(1, (a0 + a1 + a2) / 3))
        if a >= 0.985 { continue }
        // premultiplied output: colour contribution = observed - (1-a)*255
        func pm(_ o: Double) -> UInt8 { UInt8(max(0, min(255, o - (1 - a) * 255)).rounded()) }
        px[i] = pm(c.0); px[i+1] = pm(c.1); px[i+2] = pm(c.2)
        px[i+3] = UInt8((a * 255).rounded())
        blended += 1
    }
}
print("size \(w)x\(h)  fill=(\(Int(fill.0)),\(Int(fill.1)),\(Int(fill.2)))  cleared=\(cleared)  rim-blended=\(blended)")

func writePNG(_ cg: CGImage, _ url: URL) {
    let dst = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, cg, nil); CGImageDestinationFinalize(dst)
}
let out = ctx.makeImage()!
writePNG(out, outURL)

// Preview on a loud colour so any leftover halo is obvious.
let pv = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                   space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
pv.setFillColor(CGColor(red: 1, green: 0.1, blue: 0.6, alpha: 1))
pv.fill(CGRect(x: 0, y: 0, width: w, height: h))
pv.draw(out, in: CGRect(x: 0, y: 0, width: w, height: h))
writePNG(pv.makeImage()!, previewURL)
