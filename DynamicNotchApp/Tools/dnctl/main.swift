// dnctl — opens a `dynamicnotch://` command URL (docs/automation.md).
//
//   swift run dnctl profile boost
//   swift run dnctl timer start minutes=25 label="Tea"
//   swift run dnctl --print keepawake on duration=1h
//   swift run dnctl 'dynamicnotch://notch/open'
//
// Positional words become the URL path, `key=value` words the query. The app validates and runs
// the command; the URL scheme has no reply channel, so dnctl only reports whether the URL could be
// handed to an app (the result is in the app's log, category "automation").
import AppKit
import Foundation

let usage = """
usage: dnctl [--print] [--bundle-id <id>] <command> [<word>...] [key=value...]
       dnctl [--print] [--bundle-id <id>] dynamicnotch://<command>

  profile <automatic|constant-quiet|constant-high|boost|max|custom-1|custom-2|name|uuid>
          (the words of a name are joined with spaces: dnctl profile Late Night)
  fan auto
  timer start minutes=<m> [seconds=<s>] [label=<text>]     timer stop [label=<text>]
  notch open | notch close
  widget <id> show
  capture area | window | screen
  keepawake on [duration=15m|1h|2h|indefinite] | off | toggle
  pomodoro start | pause | skip

  --print        print the URL instead of opening it
  --bundle-id    open with this app (default: the scheme's registered handler)
"""

func fail(_ message: String, code: Int32 = 64) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

var args = Array(CommandLine.arguments.dropFirst())
var printOnly = false
var bundleID: String?
var words: [String] = []
while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "--print", "-n": printOnly = true
    case "--bundle-id", "-b":
        guard !args.isEmpty else { fail("--bundle-id needs a value\n\n" + usage) }
        bundleID = args.removeFirst()
    case "--help", "-h": print(usage); exit(0)
    default: words.append(arg)
    }
}
guard !words.isEmpty else { fail(usage) }

let url: URL
if words.count == 1, words[0].lowercased().hasPrefix("dynamicnotch:") {
    guard let raw = URL(string: words[0]) else { fail("not a valid URL: \(words[0])") }
    url = raw
} else {
    var segment = CharacterSet.urlPathAllowed
    segment.remove(charactersIn: "/?#;")
    var path: [String] = []
    var items: [URLQueryItem] = []
    for word in words {
        if let eq = word.firstIndex(of: "="), eq != word.startIndex {
            items.append(URLQueryItem(name: String(word[..<eq]), value: String(word[word.index(after: eq)...])))
        } else {
            path.append(word)
        }
    }
    // a profile name is one path segment: `dnctl profile Late Night` → profile/Late%20Night
    // (a "/" inside the name stays encoded as %2F)
    if let head = path.first, ["profile", "fanprofile"].contains(head.lowercased().filter { !"-_. ".contains($0) }),
       path.count > 2 {
        path = [head, path.dropFirst().joined(separator: " ")]
    }
    guard let host = path.first else { fail("missing command\n\n" + usage) }
    var c = URLComponents()
    c.scheme = "dynamicnotch"
    c.percentEncodedHost = host.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? host
    c.percentEncodedPath = path.count > 1
        ? "/" + path.dropFirst().map { $0.addingPercentEncoding(withAllowedCharacters: segment) ?? $0 }.joined(separator: "/")
        : ""
    if !items.isEmpty {
        // `queryItems` would leave "&", "=" and "+" in values unescaped
        var queryAllowed = CharacterSet.urlQueryAllowed
        queryAllowed.remove(charactersIn: "&=+?#")
        c.percentEncodedQueryItems = items.map {
            URLQueryItem(name: $0.name.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? $0.name,
                         value: $0.value?.addingPercentEncoding(withAllowedCharacters: queryAllowed))
        }
    }
    guard let built = c.url else { fail("could not build a URL from \(words)") }
    url = built
}

if printOnly {
    print(url.absoluteString)
    exit(0)
}

let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = false
configuration.addsToRecentItems = false
var openError: Error?
let done = DispatchSemaphore(value: 0)
if let bundleID {
    guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
        fail("no app with bundle id \(bundleID)", code: 69)
    }
    NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration) { _, error in
        openError = error
        done.signal()
    }
} else {
    guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
        fail("no app handles dynamicnotch:// URLs (build and launch DynamicNotch once)", code: 69)
    }
    NSWorkspace.shared.open(url, configuration: configuration) { _, error in
        openError = error
        done.signal()
    }
}
if done.wait(timeout: .now() + 15) == .timedOut { fail("timed out opening \(url.absoluteString)", code: 75) }
if let openError { fail("could not open \(url.absoluteString): \(openError.localizedDescription)", code: 69) }
print(url.absoluteString)
