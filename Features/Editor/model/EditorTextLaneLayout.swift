import Foundation

/// Text and captions share these half-open timeline intervals. Lane allocation
/// does not depend on zoom, playhead position, or rendered minimum clip widths.
struct EditorTextLaneInterval: Equatable {
    let id: UUID
    let start: TimeInterval
    let end: TimeInterval
}

enum EditorTextLaneLayout {
    static func assign(
        _ intervals: [EditorTextLaneInterval],
        preserving previous: [UUID: Int] = [:]
    ) -> [UUID: Int] {
        // Place existing items first so adding a title over captions cannot
        // push the captions out of their lane, even if the title starts earlier.
        let ordered = intervals.sorted {
            let lhsExisting = previous[$0.id] != nil
            let rhsExisting = previous[$1.id] != nil
            if lhsExisting != rhsExisting { return lhsExisting }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.id.uuidString < $1.id.uuidString
        }
        var lanes: [[EditorTextLaneInterval]] = []
        var result: [UUID: Int] = [:]
        for interval in ordered {
            func insertionIndex(in lane: Int) -> Int? {
                guard lane < lanes.count else { return 0 }
                let items = lanes[lane]
                var low = 0
                var high = items.count
                while low < high {
                    let mid = (low + high) / 2
                    if items[mid].start < interval.start { low = mid + 1 }
                    else { high = mid }
                }
                if low > 0 && items[low - 1].end > interval.start { return nil }
                if low < items.count && items[low].start < interval.end { return nil }
                return low
            }
            var destination: (lane: Int, index: Int)?
            if let preferred = previous[interval.id], preferred >= 0,
               let index = insertionIndex(in: preferred) {
                destination = (preferred, index)
            }
            if destination == nil {
                for lane in 0...lanes.count {
                    if let index = insertionIndex(in: lane) {
                        destination = (lane, index)
                        break
                    }
                }
            }
            guard let destination else { continue }
            while lanes.count <= destination.lane { lanes.append([]) }
            lanes[destination.lane].insert(interval, at: destination.index)
            result[interval.id] = destination.lane
        }
        // Remove empty lanes left after deletion without changing lane order.
        let occupied = Set(result.values).sorted()
        let compact = Dictionary(uniqueKeysWithValues: occupied.enumerated().map { ($0.element, $0.offset) })
        return result.mapValues { compact[$0] ?? 0 }
    }
}
