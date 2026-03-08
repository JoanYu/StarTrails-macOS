import Foundation
import CoreGraphics

public struct OBBResult: Sendable {
    public let cx: Float
    public let cy: Float
    public let w: Float
    public let h: Float
    public let conf: Float
    public let angle: Float // Radians
    
    // Calculate the 4 corners of the oriented bounding box using YOLO's xywhr convention
    public var corners: [CGPoint] {
        // Core operations from `ultralytics/utils/ops.py -> xywhr2xyxyxyxy`
        let cosA = cos(CGFloat(angle))
        let sinA = sin(CGFloat(angle))
        
        let vec1X = CGFloat(w) / 2.0 * cosA
        let vec1Y = CGFloat(w) / 2.0 * sinA
        let vec2X = -CGFloat(h) / 2.0 * sinA
        let vec2Y = CGFloat(h) / 2.0 * cosA
        
        // Point 1
        let pt1X = CGFloat(cx) + vec1X + vec2X
        let pt1Y = CGFloat(cy) + vec1Y + vec2Y
        
        // Point 2
        let pt2X = CGFloat(cx) + vec1X - vec2X
        let pt2Y = CGFloat(cy) + vec1Y - vec2Y
        
        // Point 3
        let pt3X = CGFloat(cx) - vec1X - vec2X
        let pt3Y = CGFloat(cy) - vec1Y - vec2Y
        
        // Point 4
        let pt4X = CGFloat(cx) - vec1X + vec2X
        let pt4Y = CGFloat(cy) - vec1Y + vec2Y
        
        return [
            CGPoint(x: pt1X, y: pt1Y),
            CGPoint(x: pt2X, y: pt2Y),
            CGPoint(x: pt3X, y: pt3Y),
            CGPoint(x: pt4X, y: pt4Y)
        ]
    }
    
    // Axis aligned bounding box
    public var boundingBox: CGRect {
        let pts = corners
        let minX = pts.map { $0.x }.min()!
        let maxX = pts.map { $0.x }.max()!
        let minY = pts.map { $0.y }.min()!
        let maxY = pts.map { $0.y }.max()!
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

public class OBBPostProcessor {
    
    /// Parses the raw output from YOLO model [1, 6, 5376] MultiArray into an array of OBBResult
    public static func parse(_ data: UnsafeMutablePointer<Float>, numBoxes: Int = 5376, confThreshold: Float = 0.25) -> [OBBResult] {
        var results = [OBBResult]()
        
        for i in 0..<numBoxes {
            let conf = data[4 * numBoxes + i]
            if conf >= confThreshold {
                let cx = data[0 * numBoxes + i]
                let cy = data[1 * numBoxes + i]
                let w = data[2 * numBoxes + i]
                let h = data[3 * numBoxes + i]
                let angle = data[5 * numBoxes + i]
                
                results.append(OBBResult(cx: cx, cy: cy, w: w, h: h, conf: conf, angle: angle))
            }
        }
        
        return results
    }
    
    /// Approximate NMS using axis-aligned bounding boxes of the rotated boxes
    public static func nonMaxSuppression(_ boxes: [OBBResult], iouThreshold: Float = 0.45) -> [OBBResult] {
        let sorted = boxes.sorted { $0.conf > $1.conf }
        var keep = [OBBResult]()
        var active = [Bool](repeating: true, count: sorted.count)
        
        for i in 0..<sorted.count {
            if !active[i] { continue }
            keep.append(sorted[i])
            let box1 = sorted[i].boundingBox
            
            for j in (i + 1)..<sorted.count {
                if !active[j] { continue }
                let box2 = sorted[j].boundingBox
                let iou = intersectionOverUnion(box1, box2)
                if Float(iou) > iouThreshold {
                    active[j] = false
                }
            }
        }
        return keep
    }
    
    /// Weighted Boxes Fusion for OBBs
    public static func weightedBoxesFusion(_ boxes: [OBBResult], iouThreshold: Float = 0.45) -> [OBBResult] {
        if boxes.isEmpty { return [] }
        
        // Sort boxes by confidence
        let sorted = boxes.sorted { $0.conf > $1.conf }
        
        // Each cluster is an array of OBBResults
        var clusters: [[OBBResult]] = []
        
        for box in sorted {
            var bestIou: Float = 0
            var bestClusterIdx = -1
            
            // Find the cluster that matches best (compare with the cluster's current merged box AABB)
            for (idx, cluster) in clusters.enumerated() {
                let mergedBox = averageOBB(cluster)
                let iou = Float(intersectionOverUnion(box.boundingBox, mergedBox.boundingBox))
                if iou > bestIou {
                    bestIou = iou
                    bestClusterIdx = idx
                }
            }
            
            if bestIou > iouThreshold {
                clusters[bestClusterIdx].append(box)
            } else {
                clusters.append([box])
            }
        }
        
        // Merge each cluster into a single OBBResult
        return clusters.map { averageOBB($0) }
    }
    
    private static func averageOBB(_ cluster: [OBBResult]) -> OBBResult {
        if cluster.count == 1 { return cluster[0] }
        
        var totalConf: Float = 0
        var sumCX: Float = 0
        var sumCY: Float = 0
        var sumW: Float = 0
        var sumH: Float = 0
        
        // For angle, we average the cos and sin of 2 * angle to handle periodic wraps (-pi/2 to pi/2)
        var sumSin: Float = 0
        var sumCos: Float = 0
        
        for box in cluster {
            totalConf += box.conf
            sumCX += box.cx * box.conf
            sumCY += box.cy * box.conf
            sumW += box.w * box.conf
            sumH += box.h * box.conf
            
            sumSin += sin(2.0 * box.angle) * box.conf
            sumCos += cos(2.0 * box.angle) * box.conf
        }
        
        let avgCX = sumCX / totalConf
        let avgCY = sumCY / totalConf
        let avgW = sumW / totalConf
        let avgH = sumH / totalConf
        let avgConf = totalConf / Float(cluster.count)
        let maxConf = cluster.map { $0.conf }.max() ?? avgConf
        
        let avgAngle = atan2(sumSin, sumCos) / 2.0
        
        return OBBResult(cx: avgCX, cy: avgCY, w: avgW, h: avgH, conf: maxConf, angle: avgAngle)
    }
    
    private static func intersectionOverUnion(_ box1: CGRect, _ box2: CGRect) -> CGFloat {
        let intersection = box1.intersection(box2)
        if intersection.isNull { return 0.0 }
        
        let interArea = intersection.width * intersection.height
        let area1 = box1.width * box1.height
        let area2 = box2.width * box2.height
        
        return interArea / (area1 + area2 - interArea)
    }
}
