import Foundation

public enum VLFetchOption: Sendable
{
 case additionalHeaders([String: String])
 case encoding(String.Encoding)
 case expectedContentType(String)
 case maxSize(Int)
 case timeout(TimeInterval)
}
