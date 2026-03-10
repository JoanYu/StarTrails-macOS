import Foundation
print("bundleURL: \(Bundle.main.bundleURL.path)")
print("resourceURL: \(Bundle.main.resourceURL?.path ?? "nil")")
