import FanCurveCore
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// Answers "what would my fan curve ask for at this temperature?" with no GUI.
// Pure FanCurveCore + Foundation, so it runs on macOS and Linux alike.

let usage = """
usage: fan-curve-curve [--points T:P,T:P,...] [--ceiling PCT] [--range MIN:MAX] [--step DEGREES]
  --points   curve points, default: the built-in five-point curve
  --ceiling  scene ceiling percentage 0-100; enables the fan budget
  --range    fan RPM range as MIN:MAX, default 2000:8000 (M5 Pro two-fan range)
  --step     temperature step in degrees, default 5
"""

func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func badArgument(_ message: String) -> Never {
    writeError(usage + "\nfan-curve-curve: " + message)
    exit(64)
}

// Plain-ASCII number text: "35" for whole numbers, "37.5" otherwise.
func text(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
}

func pad(_ value: String, _ width: Int) -> String {
    String(repeating: " ", count: max(0, width - value.count)) + value
}

func number(_ raw: String) -> Double? {
    guard let value = Double(raw), value.isFinite else { return nil }
    return value
}

func parsePoints(_ raw: String) -> [CurvePoint]? {
    var points: [CurvePoint] = []
    for field in raw.split(separator: ",", omittingEmptySubsequences: false) {
        let parts = field.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let temperature = number(String(parts[0])),
              let percentage = number(String(parts[1])) else { return nil }
        points.append(CurvePoint(temperature: temperature, percentage: percentage))
    }
    return points.isEmpty ? nil : points
}

func parseRange(_ raw: String) -> (minimum: Int, maximum: Int)? {
    let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, let minimum = Int(parts[0]), let maximum = Int(parts[1]),
          minimum >= 0, maximum > minimum else { return nil }
    return (minimum, maximum)
}

var points = FanCurve.defaultPoints
var step = 5.0
var ceiling: Int?
var range = (minimum: 2000, maximum: 8000)
let arguments = Array(CommandLine.arguments.dropFirst())
var index = 0

while index < arguments.count {
    let flag = arguments[index]
    if ["--help", "-h"].contains(flag) { print(usage); exit(0) }
    guard index + 1 < arguments.count else { badArgument("missing value for '\(flag)'") }
    let value = arguments[index + 1]
    switch flag {
    case "--points":
        guard let parsed = parsePoints(value) else { badArgument("bad --points '\(value)', expected T:P,T:P,...") }
        points = parsed
    case "--ceiling":
        guard let percent = Int(value), (0...100).contains(percent) else { badArgument("bad --ceiling '\(value)', expected 0-100") }
        ceiling = percent
    case "--range":
        guard let parsed = parseRange(value) else { badArgument("bad --range '\(value)', expected MIN:MAX") }
        range = parsed
    case "--step":
        guard let degrees = number(value), degrees > 0 else { badArgument("bad --step '\(value)', expected a positive number") }
        step = degrees
    default:
        badArgument("unknown argument '\(flag)'")
    }
    index += 2
}

guard FanCurve.isValid(points) else {
    writeError("invalid curve: " + points.map { "\(text($0.temperature)):\(text($0.percentage))" }.joined(separator: ","))
    exit(2)
}

let curve = FanCurve(points: points)
let budget = ceiling.map { FanBudget(enabled: true, ceilingPercentage: $0) } ?? FanBudget.disabled
let fan = FanRange(id: 0, minimumRPM: range.minimum, maximumRPM: range.maximum)
let first = curve.points.first?.temperature ?? 0
let last = curve.points.last?.temperature ?? first
guard (last - first) / step < 500 else { badArgument("bad --step, it would print more than 500 rows") }

print(pad("temp(C)", 8) + pad("curve%", 8) + pad("budget%", 9) + pad("rpm", 7) + "  note")
var row = 0
while first + Double(row) * step <= last + 1e-9 {
    let temperature = first + Double(row) * step
    let curvePercentage = min(100, max(0, Int(curve.percentage(at: temperature).rounded())))
    let budgetPercentage = budget.applying(to: curvePercentage)
    print(pad(text(temperature), 8) + pad(String(curvePercentage), 8)
        + pad(String(budgetPercentage), 9) + pad(String(fan.rpm(at: budgetPercentage)), 7)
        + (budget.caps(curvePercentage) ? "  capped" : ""))
    row += 1
}

print("")
print("floor \(text(curve.points.first?.percentage ?? 0))% at \(text(first))C, "
    + "ceiling \(text(curve.points.last?.percentage ?? 0))% at \(text(last))C, "
    + "points valid: \(FanCurve.isValid(points) ? "yes" : "no")")
exit(0)
