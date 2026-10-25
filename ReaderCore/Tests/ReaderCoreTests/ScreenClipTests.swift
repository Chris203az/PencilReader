import CoreGraphics
import Foundation
import Testing
@testable import ReaderCore

private let screen = CGRect(x: 0, y: 0, width: 1180, height: 820)

private func ellipse(center: CGPoint, rx: CGFloat, ry: CGFloat, steps: Int = 80) -> [CGPoint] {
    (0...steps).map { i in
        let a = 2 * Double.pi * Double(i) / Double(steps)
        return CGPoint(x: center.x + rx * CGFloat(cos(a)), y: center.y + ry * CGFloat(sin(a)))
    }
}

/// A rectangle traced by hand: a few points per side, a little shaky, ends not quite meeting.
private func handRectangle(_ r: CGRect) -> [CGPoint] {
    let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                   CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY),
                   CGPoint(x: r.minX + 3, y: r.minY + 4)]
    var points: [CGPoint] = []
    for i in 0..<(corners.count - 1) {
        let a = corners[i], b = corners[i + 1]
        for s in 0..<20 {
            let t = CGFloat(s) / 20
            let wobble = CGFloat(sin(Double(s) * 1.7)) * 2
            points.append(CGPoint(x: a.x + (b.x - a.x) * t + wobble, y: a.y + (b.y - a.y) * t - wobble))
        }
    }
    points.append(corners.last!)
    return points
}

struct ScreenClipTests {
    @Test func circleKeepsItsBoundingBoxAndMasksTheCorners() throws {
        let clip = try #require(ScreenClip.make(stroke: ellipse(center: CGPoint(x: 400, y: 300), rx: 100, ry: 60),
                                                bounds: screen, scale: 2))
        #expect(clip.rect == CGRect(x: 300, y: 240, width: 200, height: 120))
        let outline = try #require(clip.outline)
        #expect(outline.count == 81)
        #expect(clip.contains(CGPoint(x: 100, y: 60)))      // centre
        #expect(!clip.contains(CGPoint(x: 3, y: 3)))        // top-left corner of the box
        #expect(!clip.contains(CGPoint(x: 197, y: 117)))    // bottom-right corner
        #expect(!clip.contains(CGPoint(x: 250, y: 60)))     // outside the box
    }

    @Test func outlineIsRelativeToTheRect() throws {
        let stroke = ellipse(center: CGPoint(x: 600, y: 500), rx: 50, ry: 50)
        let clip = try #require(ScreenClip.make(stroke: stroke, bounds: screen, scale: 2))
        let outline = try #require(clip.outline)
        #expect(CGRect(boundingPoints: outline).origin == .zero)
        #expect(outline[0] == CGPoint(x: stroke[0].x - clip.rect.minX, y: stroke[0].y - clip.rect.minY))
    }

    @Test func nearlyRectangularStrokeKeepsTheWholeRectangle() throws {
        let clip = try #require(ScreenClip.make(stroke: handRectangle(CGRect(x: 100, y: 100, width: 300, height: 200)),
                                                bounds: screen, scale: 2))
        #expect(clip.outline == nil)
        #expect(clip.contains(CGPoint(x: 1, y: 1)))
        #expect(clip.rect.width >= 300 && clip.rect.width <= 306)
    }

    @Test func circleAndRoundedBlobAreNotRectangles() {
        let circle = ellipse(center: CGPoint(x: 400, y: 400), rx: 120, ry: 120)
        #expect(!ScreenClip.isNearlyRectangle(circle, box: CGRect(boundingPoints: circle)))
        // A diamond fills half its box.
        let diamond = [CGPoint(x: 200, y: 100), CGPoint(x: 300, y: 200), CGPoint(x: 200, y: 300),
                       CGPoint(x: 100, y: 200), CGPoint(x: 200, y: 100)]
        #expect(!ScreenClip.isNearlyRectangle(diamond, box: CGRect(boundingPoints: diamond)))
    }

    @Test func rectIsOnWholePixels() throws {
        let stroke = ellipse(center: CGPoint(x: 200.3, y: 200.3), rx: 40.1, ry: 30.1)
        let clip = try #require(ScreenClip.make(stroke: stroke, bounds: screen, scale: 2))
        for edge in [clip.rect.minX, clip.rect.minY, clip.rect.maxX, clip.rect.maxY] {
            #expect((edge * 2).rounded() == edge * 2)
        }
        #expect(clip.rect.contains(CGRect(boundingPoints: stroke)))
    }

    @Test func strokeOffScreenIsClampedToTheScreen() throws {
        let clip = try #require(ScreenClip.make(stroke: ellipse(center: CGPoint(x: 20, y: 800), rx: 80, ry: 80),
                                                bounds: screen, scale: 2))
        #expect(clip.rect == CGRect(x: 0, y: 720, width: 100, height: 100))
        #expect(clip.contains(CGPoint(x: 10, y: 80)))
    }

    @Test func strokeEntirelyOffScreenGivesNothing() {
        #expect(ScreenClip.make(stroke: ellipse(center: CGPoint(x: -300, y: 300), rx: 50, ry: 50),
                                bounds: screen, scale: 2) == nil)
    }

    @Test func dotsLinesAndTinyLoopsGiveNothing() {
        #expect(ScreenClip.make(stroke: [CGPoint(x: 10, y: 10), CGPoint(x: 11, y: 10)], bounds: screen, scale: 2) == nil)
        let line = (0...30).map { CGPoint(x: 100 + CGFloat($0) * 10, y: 200 + CGFloat($0)) }
        #expect(ScreenClip.make(stroke: line, bounds: screen, scale: 2) == nil)
        #expect(ScreenClip.make(stroke: ellipse(center: CGPoint(x: 300, y: 300), rx: 5, ry: 5),
                                bounds: screen, scale: 2) == nil)
    }

    @Test func loopGoingAroundTwiceStaysFilled() throws {
        let twice = ellipse(center: CGPoint(x: 400, y: 400), rx: 100, ry: 80)
            + ellipse(center: CGPoint(x: 404, y: 402), rx: 98, ry: 78).dropFirst()
        let clip = try #require(ScreenClip.make(stroke: twice, bounds: screen, scale: 2))
        #expect(clip.contains(CGPoint(x: clip.rect.width / 2, y: clip.rect.height / 2)))
    }
}
