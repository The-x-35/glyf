import Foundation

/// A `.glyd` dictionary (shared/typing/FORMAT.md): memory-mapped from the
/// bundle for the base language — read-only pages don't count against the
/// extension's memory limit — or built in memory for pack, added and learned
/// words. Both are the same bytes, read the same way.
final class GlydTrie {
    static let none: UInt32 = 0xFFFF_FFFF
    static let flagOffensive: UInt8 = 1
    static let flagNotAWord: UInt8 = 2
    static let flagWhitelist: UInt8 = 4
    static let flagHasUpper: UInt8 = 8

    let nodeCount: Int
    let entryCount: Int
    private let storage: AnyObject
    private let nodes: UnsafeRawPointer
    private let entries: UnsafeRawPointer
    private let bigrams: UnsafeRawPointer
    private let strings: UnsafeRawPointer
    /// Word triples (FORMAT.md "Contexts"): records after a count, or none.
    private let contexts: UnsafeRawPointer?
    private let contextCount: Int

    private init?(pointer: UnsafeRawPointer, length: Int, storage: AnyObject) {
        guard length >= 44,
              pointer.loadUnaligned(as: UInt32.self) == 0x4459_4C47, // "GLYD"
              pointer.loadUnaligned(fromByteOffset: 4, as: UInt32.self) == 1 else { return nil }
        func u32(_ offset: Int) -> Int { Int(pointer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
        nodeCount = u32(8)
        entryCount = u32(12)
        let bigramCount = u32(16), stringBytes = u32(20)
        let nodesOff = u32(24), entriesOff = u32(28), bigramsOff = u32(32), stringsOff = u32(36)
        let contextsOff = u32(40)
        let contextCount = contextsOff > 0 && contextsOff + 8 <= length ? u32(contextsOff) : 0
        guard nodeCount > 0,
              nodesOff + nodeCount * 16 <= length,
              entriesOff + entryCount * 16 <= length,
              bigramsOff + bigramCount * 8 <= length,
              stringsOff + stringBytes <= length,
              contextCount == 0 || contextsOff + 8 + contextCount * 16 <= length else { return nil }
        self.storage = storage
        nodes = pointer + nodesOff
        entries = pointer + entriesOff
        bigrams = pointer + bigramsOff
        strings = pointer + stringsOff
        contexts = contextCount > 0 ? pointer + contextsOff + 8 : nil
        self.contextCount = contextCount
    }

    /// Maps a dictionary file; nil if missing or malformed.
    static func mapped(path: String) -> GlydTrie? {
        guard let file = MappedFile(path: path) else { return nil }
        return GlydTrie(pointer: file.pointer, length: file.length, storage: file)
    }

    static func load(bytes: [UInt8]) -> GlydTrie? {
        let buffer = OwnedBytes(bytes)
        return GlydTrie(pointer: UnsafeRawPointer(buffer.pointer), length: bytes.count, storage: buffer)
    }

    // MARK: Nodes

    @inline(__always) func scalar(_ node: UInt32) -> UInt32 {
        nodes.loadUnaligned(fromByteOffset: Int(node) * 16, as: UInt32.self) & 0x00FF_FFFF
    }

    @inline(__always) func maxProbability(_ node: UInt32) -> UInt8 {
        UInt8(nodes.loadUnaligned(fromByteOffset: Int(node) * 16, as: UInt32.self) >> 24)
    }

    @inline(__always) func firstChild(_ node: UInt32) -> UInt32 {
        nodes.loadUnaligned(fromByteOffset: Int(node) * 16 + 4, as: UInt32.self)
    }

    @inline(__always) func childCount(_ node: UInt32) -> UInt32 {
        UInt32(nodes.loadUnaligned(fromByteOffset: Int(node) * 16 + 8, as: UInt16.self))
    }

    @inline(__always) func entryCount(_ node: UInt32) -> UInt32 {
        UInt32(nodes.loadUnaligned(fromByteOffset: Int(node) * 16 + 10, as: UInt16.self))
    }

    @inline(__always) func firstEntry(_ node: UInt32) -> UInt32 {
        nodes.loadUnaligned(fromByteOffset: Int(node) * 16 + 12, as: UInt32.self)
    }

    /// Children are contiguous and sorted by scalar: binary search.
    func child(of node: UInt32, scalar target: UInt32) -> UInt32? {
        let first = firstChild(node)
        guard first != Self.none else { return nil }
        var lo = first, hi = first + childCount(node)
        while lo < hi {
            let mid = (lo + hi) / 2
            let s = scalar(mid)
            if s == target { return mid }
            if s < target { lo = mid + 1 } else { hi = mid }
        }
        return nil
    }

    func node(forKey key: String) -> UInt32? {
        var node: UInt32 = 0
        for u in key.unicodeScalars {
            guard let next = child(of: node, scalar: u.value) else { return nil }
            node = next
        }
        return node
    }

    // MARK: Entries

    func form(_ entry: UInt32) -> String {
        let base = Int(entry) * 16
        let offset = Int(entries.loadUnaligned(fromByteOffset: base, as: UInt32.self))
        let length = Int(entries.loadUnaligned(fromByteOffset: base + 4, as: UInt16.self))
        return String(decoding: UnsafeRawBufferPointer(start: strings + offset, count: length), as: UTF8.self)
    }

    @inline(__always) func probability(_ entry: UInt32) -> UInt8 {
        entries.loadUnaligned(fromByteOffset: Int(entry) * 16 + 6, as: UInt8.self)
    }

    @inline(__always) func flags(_ entry: UInt32) -> UInt8 {
        entries.loadUnaligned(fromByteOffset: Int(entry) * 16 + 7, as: UInt8.self)
    }

    /// Next words recorded for this entry, most probable first.
    func bigrams(_ entry: UInt32, limit: Int = .max) -> [(target: UInt32, probability: UInt8)] {
        let base = Int(entry) * 16
        let first = entries.loadUnaligned(fromByteOffset: base + 8, as: UInt32.self)
        let count = min(Int(entries.loadUnaligned(fromByteOffset: base + 12, as: UInt16.self)), limit)
        guard first != Self.none, count > 0 else { return [] }
        return (0..<count).map { i in
            let at = (Int(first) + i) * 8
            return (bigrams.loadUnaligned(fromByteOffset: at, as: UInt32.self),
                    bigrams.loadUnaligned(fromByteOffset: at + 4, as: UInt8.self))
        }
    }

    /// Every next word of this entry, target entry → probability: looked up
    /// for each candidate while one word is typed.
    func followers(_ entry: UInt32) -> [UInt32: UInt8] {
        let base = Int(entry) * 16
        let first = entries.loadUnaligned(fromByteOffset: base + 8, as: UInt32.self)
        let count = Int(entries.loadUnaligned(fromByteOffset: base + 12, as: UInt16.self))
        guard first != Self.none, count > 0 else { return [:] }
        var out = [UInt32: UInt8](minimumCapacity: count)
        for i in 0..<count {
            let at = (Int(first) + i) * 8
            let target = bigrams.loadUnaligned(fromByteOffset: at, as: UInt32.self)
            if out[target] == nil { out[target] = bigrams.loadUnaligned(fromByteOffset: at + 4, as: UInt8.self) }
        }
        return out
    }

    func bigramProbability(from entry: UInt32, to target: UInt32) -> UInt8? {
        followers(entry)[target]
    }

    /// The likeliest words after two others (the word two back, then the
    /// previous one), most probable first.
    func trigrams(twoBack: UInt32, previous: UInt32) -> [(target: UInt32, probability: UInt8)] {
        guard let contexts else { return [] }
        var lo = 0, hi = contextCount
        while lo < hi {
            let mid = (lo + hi) / 2
            let at = mid * 16
            let a = contexts.loadUnaligned(fromByteOffset: at, as: UInt32.self)
            let b = contexts.loadUnaligned(fromByteOffset: at + 4, as: UInt32.self)
            if a == twoBack && b == previous {
                let first = Int(contexts.loadUnaligned(fromByteOffset: at + 8, as: UInt32.self))
                let count = Int(contexts.loadUnaligned(fromByteOffset: at + 12, as: UInt16.self))
                return (0..<count).map { i in
                    let row = (first + i) * 8
                    return (bigrams.loadUnaligned(fromByteOffset: row, as: UInt32.self),
                            bigrams.loadUnaligned(fromByteOffset: row + 4, as: UInt8.self))
                }
            }
            if a < twoBack || (a == twoBack && b < previous) { lo = mid + 1 } else { hi = mid }
        }
        return []
    }

    // MARK: Building (pack, added and learned words)

    struct Word {
        var form: String
        var probability: UInt8
        var flags: UInt8 = 0
    }

    /// Same layout as tools/build_dictionary.py, without bigrams.
    static func build(_ words: [Word]) -> GlydTrie {
        final class Node {
            var children: [UInt32: Node] = [:]
            var forms: [(form: String, probability: UInt8, flags: UInt8)] = []
        }
        let root = Node()
        for w in words {
            let key = TypingText.key(w.form)
            guard !key.isEmpty else { continue }
            var node = root
            for u in key.unicodeScalars {
                if let next = node.children[u.value] { node = next } else {
                    let next = Node()
                    node.children[u.value] = next
                    node = next
                }
            }
            var flags = w.flags
            if TypingText.hasUppercase(w.form) { flags |= flagHasUpper }
            if let i = node.forms.firstIndex(where: { $0.form == w.form }) {
                node.forms[i].probability = max(node.forms[i].probability, w.probability)
                node.forms[i].flags |= flags
            } else {
                node.forms.append((w.form, w.probability, flags))
            }
        }

        var order: [(node: Node, scalar: UInt32)] = [(root, 0)]
        var head = 0
        while head < order.count {
            let (node, _) = order[head]
            head += 1
            for s in node.children.keys.sorted() { order.append((node.children[s]!, s)) }
        }
        var indexOf: [ObjectIdentifier: UInt32] = [:]
        for (i, item) in order.enumerated() { indexOf[ObjectIdentifier(item.node)] = UInt32(i) }

        var maxProb = [UInt8](repeating: 0, count: order.count)
        for i in stride(from: order.count - 1, through: 0, by: -1) {
            let node = order[i].node
            var best: UInt8 = 0
            for f in node.forms where f.flags & (flagOffensive | flagNotAWord) == 0 {
                best = max(best, f.probability)
            }
            for child in node.children.values { best = max(best, maxProb[Int(indexOf[ObjectIdentifier(child)]!)]) }
            maxProb[i] = best
        }

        var nodeBytes = [UInt8](), entryBytes = [UInt8](), stringBytes = [UInt8]()
        nodeBytes.reserveCapacity(order.count * 16)
        var entryIndex: UInt32 = 0
        for (i, item) in order.enumerated() {
            let node = item.node
            let sortedChildren = node.children.keys.sorted()
            let firstChild = sortedChildren.first.map { indexOf[ObjectIdentifier(node.children[$0]!)]! } ?? none
            let forms = node.forms.sorted { $0.probability != $1.probability ? $0.probability > $1.probability : $0.form < $1.form }
            append(&nodeBytes, UInt32(item.scalar & 0xFF_FFFF) | UInt32(maxProb[i]) << 24)
            append(&nodeBytes, firstChild)
            append(&nodeBytes, UInt16(sortedChildren.count))
            append(&nodeBytes, UInt16(forms.count))
            append(&nodeBytes, forms.isEmpty ? none : entryIndex)
            for f in forms {
                let utf8 = Array(f.form.utf8)
                append(&entryBytes, UInt32(stringBytes.count))
                append(&entryBytes, UInt16(utf8.count))
                entryBytes.append(f.probability)
                entryBytes.append(f.flags)
                append(&entryBytes, none)
                append(&entryBytes, UInt16(0))
                append(&entryBytes, UInt16(0))
                stringBytes.append(contentsOf: utf8)
                entryIndex += 1
            }
        }

        let header = 44
        var out = [UInt8]()
        out.reserveCapacity(header + nodeBytes.count + entryBytes.count + stringBytes.count)
        out.append(contentsOf: Array("GLYD".utf8))
        let nodesOff = header, entriesOff = nodesOff + nodeBytes.count
        let bigramsOff = entriesOff + entryBytes.count, stringsOff = bigramsOff
        for v in [1, order.count, Int(entryIndex), 0, stringBytes.count,
                  nodesOff, entriesOff, bigramsOff, stringsOff, 0] {
            append(&out, UInt32(v))
        }
        out.append(contentsOf: nodeBytes)
        out.append(contentsOf: entryBytes)
        out.append(contentsOf: stringBytes)
        return load(bytes: out)!
    }

    private static func append<T: FixedWidthInteger>(_ bytes: inout [UInt8], _ value: T) {
        withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
    }
}

/// A read-only mmap, unmapped when the dictionary goes away.
private final class MappedFile {
    let pointer: UnsafeRawPointer
    let length: Int

    init?(path: String) {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_size > 0 else { return nil }
        let length = Int(info.st_size)
        guard let raw = mmap(nil, length, PROT_READ, MAP_PRIVATE, fd, 0), raw != MAP_FAILED else { return nil }
        pointer = UnsafeRawPointer(raw)
        self.length = length
    }

    deinit { munmap(UnsafeMutableRawPointer(mutating: pointer), length) }
}

private final class OwnedBytes {
    let pointer: UnsafeMutableRawPointer

    init(_ bytes: [UInt8]) {
        pointer = UnsafeMutableRawPointer.allocate(byteCount: max(bytes.count, 1), alignment: 8)
        bytes.withUnsafeBytes { pointer.copyMemory(from: $0.baseAddress!, byteCount: bytes.count) }
    }

    deinit { pointer.deallocate() }
}
