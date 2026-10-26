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

struct ScreenClipTests {
    @Test func circleBecomesTheRectangleReachingItsFarthestPoints() throws {
        let clip = try #require(ScreenClip.make(stroke: ellipse(center: CGPoint(x: 400, y: 300), rx: 100, ry: 60),
                                                bounds: screen, scale: 2))
        #expect(clip.rect == CGRect(x: 300, y: 240, width: 200, height: 120))
    }

    @Test func shakyLoopTakesItsWidestExtremes() throws {
        var loop = ellipse(center: CGPoint(x: 500, y: 400), rx: 80, ry: 80)
        loop[10].x += 25        // a wobble sticking out to the right
        loop[45].y -= 30        // and one at the top
        let clip = try #require(ScreenClip.make(stroke: loop, bounds: screen, scale: 2))
        #expect(clip.rect.contains(CGRect(boundingPoints: loop)))
        #expect(clip.rect.maxX >= loop[10].x)
        #expect(clip.rect.minY <= loop[45].y)
        #expect(clip.rect.width <= CGRect(boundingPoints: loop).width + 1)
    }

    @Test func diagonalStrokeGivesItsRectangle() throws {
        let diagonal = (0...20).map { CGPoint(x: 100 + CGFloat($0) * 10, y: 100 + CGFloat($0) * 6) }
        let clip = try #require(ScreenClip.make(stroke: diagonal, bounds: screen, scale: 2))
        #expect(clip.rect == CGRect(x: 100, y: 100, width: 200, height: 120))
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
    }

    @Test func strokeEntirelyOffScreenGivesNothing() {
        #expect(ScreenClip.make(stroke: ellipse(center: CGPoint(x: -300, y: 300), rx: 50, ry: 50),
                                bounds: screen, scale: 2) == nil)
    }

    @Test func dotsStraightLinesAndTinyLoopsGiveNothing() {
        #expect(ScreenClip.make(stroke: [CGPoint(x: 10, y: 10), CGPoint(x: 11, y: 10)], bounds: screen, scale: 2) == nil)
        let line = (0...30).map { CGPoint(x: 100 + CGFloat($0) * 10, y: 200 + CGFloat($0) / 10) }
        #expect(ScreenClip.make(stroke: line, bounds: screen, scale: 2) == nil)
        #expect(ScreenClip.make(stroke: ellipse(center: CGPoint(x: 300, y: 300), rx: 5, ry: 5),
                                bounds: screen, scale: 2) == nil)
    }
}
