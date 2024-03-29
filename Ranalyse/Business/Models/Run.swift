//
//  Run.swift
//  Ranalyse
//
//  Created by Mykhailo Moiseienko on 5/11/19.
//  Copyright © 2019 Mykhailo Moiseienko. All rights reserved.
//

import Foundation
import CoreGPX

public struct Run {
    
    // MARK: - Internal properties
    
    let gpx: GPXRoot
    let allPoints: [GPXTrackPoint]
    
    // MARK: - Public properties
    
    /// Name of the run
    public let name: String?
    
    /// Date of the run
    public let date: Date?
    
    /// Total distance in meters
    public let distance: Distance
    
    /// Total duration in seconds
    public let duration: Duration
    
    /// Cumulative Elevation Gain (in meters)
    public let cumulativeElevationGain: Elevation
    
    /// Minimal heart rate in BPM (beats per minute)
    public let minHeartRate: BPM?
    
    /// Maximal heart rate in BPM (beats per minute)
    public let maxHeartRate: BPM?
    
    /// Average heart rate in BPM (beats per minute)
    public let averageHeartRate: BPM?
    
    /// Total Elevation Loss in meters
//    let totalElevationLoss: Int
    
    /// Speed (in kilometers per hour)
    public var speed: Double {
        return distance / duration * 3.6
    }
    
    /// Pace (in minutes per kilometer)
    public var pace: Pace {
        return 60.0 / speed
    }
    
    /// Relative Effort
    public let relativeEffort: Double
    
    /// 1 kilometer splits
    public var splits: [Split]
    
    public var heartRateAnalysis: HeartRateAnalysis?
    
    public init(gpx: GPXRoot) {
        self.gpx = gpx
        
        allPoints = gpx.tracks.flatMap {
            $0.tracksegments.flatMap {
                $0.trackpoints
            }
        }
        splits = Run.initSplits(from: allPoints)
        
        if let maxHeartRate: Int = UserDefaults.get(key: .maxHeartRate) {
            heartRateAnalysis = HeartRateAnalysis(maxHeartRate: maxHeartRate)
        }
        
        var totalDistance = 0.0
        var totalDuration = 0.0
        var cumulativeElevationGain = 0.0
        var minHeartRate = BPM.max
        var maxHeartRate = BPM.min
        
        for i in 1..<allPoints.count {
            let previousPoint = allPoints[i - 1]
            let currentPoint = allPoints[i]
            
            let distance = DistanceCalculator.distanceBetweenPoints(point1: previousPoint, point2: currentPoint)
            totalDistance += distance
            
            let duration = DurationCalculator.timeIntervalBetweenPoints(point1: previousPoint, point2: currentPoint)
            totalDuration += duration
            
            let elevation = ElevationCalculator.elevationDifferenceBetweenPoints(point1: previousPoint, point2: currentPoint)
            cumulativeElevationGain += elevation > 0 ? elevation : 0
            
            if let heartRate = currentPoint.heartRate {
                if heartRate < minHeartRate {
                    minHeartRate = heartRate
                }
                if heartRate > maxHeartRate {
                    maxHeartRate = heartRate
                }
                
                heartRateAnalysis?.addHeartRate(heartRate, for: duration)
            }
        }
        
        self.name = gpx.tracks.first?.name
        self.date = gpx.metadata?.time
        
        self.distance = totalDistance
        self.duration = totalDuration
        self.cumulativeElevationGain = cumulativeElevationGain
        
        self.minHeartRate = minHeartRate == BPM.max ? nil : minHeartRate
        self.maxHeartRate = maxHeartRate == BPM.min ? nil : maxHeartRate
        self.averageHeartRate = HeartRateCalculator.averageHeartRate(forPoints: allPoints)
        
        // TODO: Imlpement calculation of relative effort
        self.relativeEffort = 0.0
    }
}

extension Run {
    public static func run(fromGPXFile fileName: String) -> Run? {
        guard let inputURL = Bundle.main.url(forResource: fileName, withExtension: "gpx") else { return nil }
        let parser = GPXParser(withURL: inputURL)
        guard let gpx = parser?.parsedData() else { return nil }
        return Run(gpx: gpx)
    }
    
    static func initSplits(from points: [GPXTrackPoint]) -> [Split] {
        var splits = [Split]()
        var currentSplit: Split!
        
        for i in 1..<points.count {
            let previousPoint = points[i - 1]
            let currentPoint = points[i]
            
            if currentSplit == nil {
                currentSplit = Split(index: splits.endIndex + 1)
            }
            
            // Add point to split
            if currentSplit.points.count == 0/*i == 1*/ {
                currentSplit.addPoint(previousPoint)
            }
            currentSplit.addPoint(currentPoint)
            
            // Distance
            currentSplit.distance += DistanceCalculator.distanceBetweenPoints(point1: previousPoint, point2: currentPoint)
            
            if currentSplit.distance >= 1_000.0 || currentPoint == points.last {
                currentSplit.initFromPoints()
                
                splits.append(currentSplit)
                currentSplit = nil
            }
        }
        
        return splits
    }
}

extension Run {
    func allPossibleSplits(of distance: Distance) -> Set<Split> {
        guard self.distance >= distance else { return [] }
        
        var uncompletedSplits = Set<Split>()
        var completedSplits = Set<Split>()
        var index = 0
        
        for point in allPoints {
            let split = Split(index: index)
            index += 1
            uncompletedSplits.insert(split)
            
            for split in uncompletedSplits {
                // Calculate Distance
                if let previousPoint = split.points.last {
                    split.distance += DistanceCalculator.distanceBetweenPoints(point1: previousPoint, point2: point)
                }
                
                // Add point to split
                split.addPoint(point)
                
                // Complete Split
                if split.distance >= distance {
                    split.initFromPoints()
                    
                    uncompletedSplits.remove(split)
                    completedSplits.insert(split)
                }
            }
        }
        
        return completedSplits
    }
    
    func allPossibleSplits(of distance: Distance, completion: @escaping (Set<Split>) -> Void) {
        guard self.distance >= distance else {
            completion([])
            return
        }
        
        DispatchQueue.global(qos: .default).async {
            var uncompletedSplits = Set<Split>()
            var completedSplits = Set<Split>()
            var index = 0
            
            for point in self.allPoints {
                let split = Split(index: index)
                index += 1
                uncompletedSplits.insert(split)
                
                for split in uncompletedSplits {
                    // Calculate Distance
                    if let previousPoint = split.points.last {
                        split.distance += DistanceCalculator.distanceBetweenPoints(point1: previousPoint, point2: point)
                    }
                    
                    // Add point to split
                    split.addPoint(point)
                    
                    // Complete Split
                    if split.distance >= distance {
                        split.initFromPoints()
                        
                        uncompletedSplits.remove(split)
                        completedSplits.insert(split)
                    }
                }
            }
            
            DispatchQueue.main.async {
                completion(completedSplits)
            }
        }
    }
    
    var fastestOneKilometer: Duration? {
        return allPossibleSplits(of: 1_000.0)
            .map { $0.time }
            .min()
    }
    
    var fastestFiveKilometer: Duration? {
        return allPossibleSplits(of: 5_000.0)
            .map { $0.time }
            .min()
    }
    
    var fastestTenKilometer: Duration? {
        return allPossibleSplits(of: 10_000.0)
            .map { $0.time }
            .min()
    }
    
    var fastestHalfMarathon: Duration? {
        return allPossibleSplits(of: 21_097.5)
            .map { $0.time }
            .min()
    }
    
    var fastestMarathon: Duration? {
        return allPossibleSplits(of: 42_195.0)
            .map { $0.time }
            .min()
    }
}

extension Run {
    func vdot(_ completion: @escaping (VDOT?) -> Void) {
        var vdot: VDOT? = nil
        
        guard let nearestDistance = KnownDistance.nearestDistance(to: distance) else {
            completion(vdot)
            return
        }
        
        allPossibleSplits(of: nearestDistance.rawValue) { splits in
            if let fastestSplitDuration = splits.map({ $0.time }).min() {
                vdot = VDOT(distance: nearestDistance, duration: fastestSplitDuration)
                vdot?.date = self.date
            }
            
            completion(vdot)
        }
    }
}

extension Array where Element == Run {
    func forLastTwoWeeks() -> [Run] {
        return filter { run in
            guard let date = run.date else {
                return false
            }
            
            guard let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) else {
                return false
            }
            
            return date > twoWeeksAgo
        }
    }
    
    func forLastMonth() -> [Run] {
        return filter { run in
            guard let date = run.date else {
                return false
            }
            
            guard let monthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) else {
                return false
            }
            
            return date > monthAgo
        }
    }
}
