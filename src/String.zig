pub const String = @This();
const std = @import("std");
const builtin = @import("builtin");
const unicode = std.unicode;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const maxInt = std.math.maxInt;
//const out = std.io.getStdOut().writer();
const BitWriter = std.io.bit_writer.BitWriter;
pub const BitData = @import("bit_data.zig").BitData;

pub const io = @import("io.zig");
pub const mtl = @import("mtl.zig");
pub const Num = @import("Num.zig");

const zg_codepoint = @import("code_point");
const zg_grapheme = @import("grapheme");
const CaseData = @import("CaseData");
const Normalize = @import("Normalize");
const CaseFold = @import("CaseFold");

pub const Codepoint = u21;
pub const CpSlice = []Codepoint;
pub const ConstCpSlice = []const Codepoint;
pub const GraphemeSlice = []const u1;
pub const Error = error{ NotFound, BadArg, Index, Alloc, Other };
const SimdVecLen: u16 = 32;

const BinaryHintByte: u8 = 0b0100_0000;
const BinaryHintU64: u8 =  0b1000_0000;
const BinaryHintMask: u8 = 0b1100_0000;
const BinaryMaxByte: u8 = 0b0011_1111;

pub const KeepEmptyParts = enum(u1) {
    Yes,
    No,
};

pub const CaseSensitive = enum(u1) {
    Yes,
    No,
};

pub const Theme = enum(u8) {
    Light,
    Dark,
};

const Clear = enum(u1) {
    Yes,
    No,
};

pub const Flush = enum(u1) {
    Yes,
    No,
};

const Attr = enum(u2) {
    Ignore,
    Codepoint,
    Grapheme,
};
const SeeAs = enum(u8) { CodepointOnly, PartOfGrapheme };

pub const Grapheme = struct {
    len: u8 = 1,
    idx: Index,
    codepoints: ArrayList(Codepoint) = undefined,
    s: *const String,

    pub fn getSlice(self: Grapheme) ?CpSlice {
        const sd = self.s.d orelse return null;
        const len: usize = self.len;
        // std.debug.print("items.len={}, cp={}, len={}\n",
        //     .{sd.codepoints.items.len, self.idx.cp, len});
        return sd.codepoints.items[self.idx.cp..(self.idx.cp+len)];
    }

    pub fn getCodepoint(self: Grapheme) ?Codepoint {
        if (self.len != 1) {
            return null;
        }
        const sd = self.s.d orelse return null;
        return sd.codepoints.items[self.idx.cp];
    }

    pub fn eq(self: Grapheme, input: []const u8) bool {
        if (input.len == 1) {
            const cp = toCp(input) catch return false;
            return self.eqCp(cp);
        } else {
            const buf = toCodepoints(ctx.a, input) catch return false;
            defer buf.deinit();
            return self.eqSlice(buf.items);
        }
    }

    pub fn eqAscii(self: Grapheme, c: comptime_int) bool {
        const cp = String.toCpAscii(c) catch return false;
        return self.eqCp(cp);
    }

    pub fn eqCp(self: Grapheme, cp: Codepoint) bool {
        const slice = self.getSlice() orelse return false;
        return (slice.len == 1) and (slice[0] == cp);
    }

    pub fn eqSlice(self: Grapheme, input: CpSlice) bool {
        const slice = self.getSlice() orelse return (input.len == 0);
        if (input.len != slice.len)
            return false;
        for (slice, input) |a, b| {
            if (a != b)
                return false;
        }

        return true;
    }

    pub fn format(self: *const Grapheme, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        const slice = self.getSlice() orelse return;
        const utf8 = try String.utf8_from_slice(ctx.a, slice);
        defer utf8.deinit();
        _ = try writer.print("{s}", .{utf8.items});
    }

    pub fn isWordChar(self: Grapheme) bool {
        const cp = self.getCodepoint() orelse return false;
        return String.isWordChar(cp);
    }

    pub fn isWhitespace(self: Grapheme) bool {
        const cp = self.getCodepoint() orelse return false;
        
        return cp == ' ' or cp == '\t' or cp == '\n' or cp == '\r';
    }

    pub fn toOwned(self: Grapheme) !ArrayList(Codepoint) {
        var a = ArrayList(Codepoint).init(ctx.a);
        const sd = self.s.d orelse return a;
        const slice = sd.codepoints.items[0..];
        for (0..self.len) |k| {
            try a.append(slice[k]);
        }

        return a;
    }
};

pub const Iterator = struct {
    first_time: bool = true,
    idx: Index,
    str: *const String,

    pub fn New(str: *const String, index: ?Index) Iterator {
        const idx = if (index) |i| i else Index.strStart();
        return Iterator {.str = str, .idx = idx};
    }

    pub fn continueFrom(self: *Iterator, idx: Index) void {
        self.idx = idx;
        self.first_time = true;
    }

    pub fn nextIndex(self: *Iterator) ?Index {
        if (self.first_time) {
            self.first_time = false;
            return self.idx;
        }

        const sd = self.str.d orelse return null;
        if (self.idx.cp >= sd.codepoints.items.len)
            return null;
        
        return if (self.idx.advance_to_next_grapheme(sd.graphemes.items)) self.idx else null;
    }

    pub fn next(self: *Iterator) ?Grapheme {
        const index = self.nextIndex() orelse return null;
        return self.str.charAtIndex(index);
    }

    pub fn nextFrom(self: *Iterator, idx: Index) ?Grapheme {
        self.first_time = false;
        self.idx = idx;
        return self.next();
    }

    pub fn prev(self: *Iterator) ?Grapheme {
        var idx: Index = undefined;
        if (self.first_time) {
            self.first_time = false;
            idx = self.idx;
        } else {
            idx = self.idx.prevIndex(self.str) orelse return null;
        }
        
        return self.str.charAtIndex(idx);
    }

    pub fn prevFrom(self: *Iterator, idx: Index) ?Grapheme {
        self.first_time = false;
        self.idx = idx;
        return self.prev();
    }
};

pub const Index = struct {
    cp: usize = 0,
    gr: usize = 0,

    pub fn add(self: *Index, input: Index) void {
        self.cp += input.cp;
        self.gr += input.gr;
    }

    pub fn addOne(self: *Index) void {
        self.cp += 1;
        self.gr += 1;
    }

    // advance past grapheme
    pub fn addGrapheme(self: *const Index, g: Grapheme) Index {
        return .{.cp = self.cp + g.len, .gr = self.gr + 1};
    }

    pub fn addString(self: *Index, input: String) void {
        self.gr += input.size();
        self.cp += input.size_cp();
    }

    pub fn addRaw(self: Index, how_much: usize) Index {
        return Index {.cp = self.cp + how_much, .gr = self.gr + how_much};
    }

    pub fn advanceToNextGrapheme(self: *Index, s: *const String) void {
        const sd = s.d orelse return;
        if (self.cp < sd.codepoints.items.len)
            self.advance_to_next_grapheme(sd.graphemes.items);
    }

    fn advance_to_next_grapheme(self: *Index, graphemes: GraphemeSlice) bool {
        self.cp += 1;
        for (graphemes[(self.cp)..], 0..) |gr_bit, i| {
            if (gr_bit == 1) {
                self.cp += i;
                self.gr += 1;
                return true;
            }
        }

        return false;
    }

    pub fn clone(self: Index) Index {
        return Index {.cp = self.cp, .gr = self.gr};
    }

    pub fn equals(self: Index, rhs: Index) bool {
        return self.cp == rhs.cp and self.gr == rhs.gr;
    }

    /// format implements the `std.fmt` format interface for printing types.
    pub fn format(self: Index, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        _ = try writer.print("Index{{cp={},gr={}}}", .{ self.cp, self.gr });
    }

    pub fn hasNext(self: Index, s: *const String) bool {
        const sd = s.d orelse return false;
        return self.cp < sd.codepoints.items.len;
    }

    fn prevIndex(self: *Index, s: *const String) ?Index {
        const sd = s.d orelse return null;
        const cp_count = sd.codepoints.items.len;
        if (self.cp == 0 or self.cp > cp_count)
            return null;

        var i: isize = @intCast(self.cp);
        i -= 1;
        while (i >= 0) : (i -= 1) {
            const b = sd.graphemes.items[@intCast(i)];
            if (b == 1) {
                self.cp = @intCast(i);
                self.gr -= 1;
                return self.*;
            }
        }

        return null;
    }

    pub fn strStart() Index {
        return Index{};
    }
};

const TimeExt = "mc";
inline fn getTime() i128 {
    return std.time.microTimestamp();
}

pub const Context = struct {
    a: Allocator = undefined,
    grapheme_data: zg_grapheme.GraphemeData = undefined,
    cd: CaseData = undefined,
    //cf: CaseFold = undefined,
    //cfd: CaseFold.FoldData,
    // normalize: Normalize = undefined,
    // norm_data: Normalize.NormData = undefined,

    pub fn New(alloc: Allocator) !Context {
        const ct = Context{
            .a = alloc,
            .grapheme_data = try zg_grapheme.GraphemeData.init(alloc),
            .cd = try CaseData.init(alloc),
            //.cfd = try CaseFold.FoldData.init(alloc),
        };

        // try Normalize.NormData.init(&ct.norm_data, alloc);
        // ct.normalize = Normalize{ .norm_data = &ct.norm_data };
        //ct.cf = CaseFold {.fold_data = &ct.cfd};

        return ct;
    }

    pub fn deinit(self: Context) void {
        self.grapheme_data.deinit();
        self.cd.deinit();
        // self.cfd.deinit();
        //self.norm_data.deinit();
    }
};

pub threadlocal var ctx: Context = undefined;

const Data = struct {
    codepoints: ArrayList(Codepoint) = undefined,
    graphemes: ArrayList(u1) = undefined,
    grapheme_count: usize = 0,

    pub fn Clone(self: Data) !Data {
        return Data {
            .codepoints = try self.codepoints.clone(),
            .graphemes = try self.graphemes.clone(),
            .grapheme_count = self.grapheme_count,
        };
    }

    pub fn CloneFrom(self: Data, from_index: Index) !Data {
        var d = Data {};
        d.codepoints = ArrayList(Codepoint).init(ctx.a);
        d.graphemes = ArrayList(u1).init(ctx.a);
        d.grapheme_count = self.grapheme_count - from_index.gr;

        try d.codepoints.appendSlice(self.codepoints.items[from_index.cp..]);
        try d.graphemes.appendSlice(self.graphemes.items[from_index.cp..]);

        return d;
    }
};

d: ?Data = null,

pub fn New() String {
    return String{};
}

pub fn From(input: []const u8) !String {
    var s = String{};
    s.initEmpty();
    try s.init(input, Clear.No);
    return s;
}

fn initEmpty(self: *String) void {
    if (self.d != null)
        return;
    self.d = Data{
        .graphemes = ArrayList(u1).init(ctx.a),
        .codepoints = ArrayList(Codepoint).init(ctx.a),
        .grapheme_count = 0,
    };
}

pub fn deinit(self: String) void {
    var sd = self.d orelse return;
    sd.codepoints.deinit();
    sd.graphemes.deinit();
}

const ST=[]const u8;
pub fn add(self: *String, what: ST) !void {
    if (what.len == 1) {
        const cp = try toCp(what);
        var sd = try self.getPointer();
        try sd.codepoints.append(cp);
        try sd.graphemes.append(1);
        sd.grapheme_count += 1;
    } else {
        const input = try String.From(what);
        defer input.deinit();
        try self.addStr(input);
    }
}

pub fn add2(self: *String, a1: ST, a2: ST) !void {
    try self.add(a1);
    try self.add(a2);
}

pub fn add3(self: *String, a1: ST, a2: ST, a3: ST) !void {
    try self.add(a1);
    try self.add(a2);
    try self.add(a3);
}

pub fn add4(self: *String, a1: ST, a2: ST, a3: ST, a4: ST) !void {
    try self.add(a1);
    try self.add(a2);
    try self.add(a3);
    try self.add(a4);
}

pub fn addAscii(self: *String, c: comptime_int) !void {
    const ch: u8 = @intCast(c);
    const arr = [_]u8 {ch};
    try self.add(&arr);
}

pub fn addGrapheme(self: *String, gr: Grapheme) !void {
    const gr_slice = gr.getSlice() orelse return String.Error.Other;
    var sd = try self.getPointer();
    sd.grapheme_count += 1;
    for (gr_slice, 0..) |cp, i| {
        try sd.codepoints.append(cp);
        try sd.graphemes.append(if(i == 0) 1 else 0);
    }
}

pub fn addStr(self: *String, other: String) !void {
    const sdo = other.d orelse return;
    var sd = try self.getPointer();
    try sd.codepoints.appendSlice(sdo.codepoints.items);
    try sd.graphemes.appendSlice(sdo.graphemes.items);
    sd.grapheme_count += sdo.grapheme_count;
}

pub fn At(self: String, gr_index: usize) ?Index {
    return self.graphemeAddress(gr_index);
}

pub fn between(self: String, start: usize, end: usize) !String {
    return self.substring(start, @intCast(end - start));
}

pub fn betweenIndices(self: String, start: Index, end: Index) !String {
    return self.substr(start, end.gr - start.gr);
}

pub fn charAt(self: *const String, at: usize) ?Grapheme {
    const index = self.At(at) orelse return null;
    return self.charAtIndex(index);
}

pub fn charAtIndex(self: *const String, at: Index) ?Grapheme {
    const sd = self.d orelse return null;
    
    if (at.cp >= sd.codepoints.items.len)
        return null;

    const cp_slice = sd.codepoints.items[at.cp..];
    const gr_slice = sd.graphemes.items[at.cp..];
    for (cp_slice, gr_slice, 0..) |cp, gr, i| {
        _ = cp;
        _ = gr;
        _ = i;
    }
    
    var g = Grapheme{.s = self, .idx = at};
    
    if (gr_slice.len == 1) {
        return g;
    }

    for (gr_slice[1..]) |b| {
        if (b == 1)
            break;
        g.len += 1;
    }

    return g;
}

pub fn isBetween(self: String, l: []const u8, r: []const u8) ?String {
    if (l.len > 1 or r.len > 1) {
        const a = toCodepoints(ctx.a, l) catch return null;
        defer a.deinit();
        const b = toCodepoints(ctx.a, r) catch return null;
        defer b.deinit();
        return self.isBetweenSlices(a.items, b.items);
    }
    const a = toCp(l) catch return null;
    const b = toCp(r) catch return null;
    return self.isBetweenCp(a, b);
}

pub fn isBetweenCp(self: String, l: Codepoint, r: Codepoint) ?String {
    if (!self.startsWithCp(l) or !self.endsWithCp(r))
        return null;
    return self.between(1, self.size() - 1) catch return null;
}

pub fn isBetweenSlices(self: String, l: CpSlice, r: CpSlice) ?String {
    const cs = CaseSensitive.Yes;
    if (!self.startsWithSlice(l, cs) or !self.endsWithSlice(r, cs))
        return null;
    return self.between(l.len, self.size() - r.len) catch return null;
}

pub fn clearAndFree(self: *String) void {
    var sd = self.getPointer() catch return;
    sd.codepoints.clearAndFree();
    sd.graphemes.clearAndFree();
    sd.grapheme_count = 0;
}

pub fn clearRetainingCapacity(self: *String) void {
    var sd = self.getPointer() catch return;
    sd.codepoints.clearRetainingCapacity();
    sd.graphemes.clearRetainingCapacity();
    sd.grapheme_count = 0;
}

pub fn Clone(self: String) !String {
    var sd = self.d orelse return String{};
    return String{
        .d = try sd.Clone(),
    };
}

pub fn computeSizeInBytes(self: String) u64 {
    const bits_total: u64 = self.computeSizeInBits();
    var byte_count = bits_total / 8;
    if ((bits_total % 8) != 0) {
        byte_count += 1;
    }
    return byte_count;
}

pub fn computeSizeInBits(self: String) u64 {
    const cp_count = self.size_cp();
    if (cp_count == 0)
        return @bitSizeOf(u8);
    
    var bit_count: u64 = @bitSizeOf(u8); // binary header
    if (cp_count > BinaryMaxByte) { // then store cp_count as a u64
        bit_count += @bitSizeOf(u64);
    }

    // if (cp_count <= maxInt(u8)) { // how much to store grapheme count
    //     bit_count += @bitSizeOf(u8);
    // } else {
    //     bit_count += @bitSizeOf(u64);
    // }

    const sd = self.d orelse return 0;
    for (sd.codepoints.items) |cp| {
        if (cp <= maxInt(u8)) {
            bit_count += @bitSizeOf(u8);
        } else if (cp <= maxInt(u16)) {
            bit_count += @bitSizeOf(u16);
        } else {
            bit_count += @bitSizeOf(u24);
        }
    }

    bit_count += cp_count * 3; // each codepoint has a corresponding u3 for size/gr info.

    return bit_count;
}

inline fn countGraphemes(slice: GraphemeSlice) usize {
    if (slice.len > SimdVecLen * 4) {
        return countGraphemesSimd(slice);
    }
    return countGraphemesLinear(slice);
}

inline fn countGraphemesLinear(slice: GraphemeSlice) usize {
    var count: usize = 0;
    for (slice) |n| {
        if (n == 1)
            count += 1;
    }

    return count;
}

fn countGraphemesSimd(slice: GraphemeSlice) usize {
    const needle: u1 = 1;
    var pos: usize = 0;
    var count: usize = 0;
    const vec_needles: @Vector(SimdVecLen, u1) = @splat(needle);
    while (pos < slice.len) {
        if ((slice.len - pos) < SimdVecLen) { // do it manually
            for (slice[pos..]) |k| {
                if (k == 1)
                    count += 1;
            }
            break;
        }
        const line: @Vector(SimdVecLen, u1) = slice[pos..][0..SimdVecLen].*;
        const does_match = line == vec_needles;
        count += std.simd.countTrues(does_match);
        pos += SimdVecLen;
    }

    return count;
}

pub fn contains(self: String, str: []const u8) bool {
    return self.indexOf(str, null) != null;
}

pub fn contains2(self: String, str: CpSlice) bool {
    return self.indexOf2(str, null) != null;
}

pub fn containsStr(self: String, needles: String) bool {
    const sdn = needles.d orelse return false;
    return self.indexOf2(sdn.codepoints.items, null) != null;
}

pub fn countGraphemesRaw(alloc: Allocator, input: []const u8) usize {
    const gd = zg_grapheme.GraphemeData.init(alloc) catch return 0;
    defer gd.deinit();
    var gr_iter = zg_grapheme.Iterator.init(input, &gd);
    var grapheme_count: usize = 0;
    while (gr_iter.next()) |grapheme| {
        _ = grapheme;
        grapheme_count += 1;
    }

    return grapheme_count;
}

pub fn dupAsCstr(self: String) ![]u8 {
    return self.dupAsCstrAlloc(ctx.a);
}

pub fn dupAsCstrAlloc(self: String, a: Allocator) ![]u8 {
    const buf = try self.toString();
    defer buf.deinit();
    return a.dupe(u8, buf.items);
}

pub fn endsWith(self: String, phrase: []const u8, cs: CaseSensitive) bool {
    const needles = toCodepoints(ctx.a, phrase) catch return false;
    defer needles.deinit();
    return self.endsWithSlice(needles.items, cs);
}

pub fn endsWithChar(self: String, letter: []const u8) bool {
    const cp = toCp(letter) catch return false;
    return self.endsWithCp(cp);
}

/// returns true if the codepoint is a whole grapheme
pub fn endsWithCp(self: String, cp: Codepoint) bool {
    const sd = self.d orelse return false;
    const slice = sd.codepoints.items[0..];
    if (slice.len == 0 or slice[slice.len - 1] != cp)
        return false;
    const glist = sd.graphemes.items[0..];
    return glist[glist.len - 1] == 1;
}

pub fn endsWithSlice(self: String, needles: CpSlice, cs: CaseSensitive) bool {
    const sd = self.d orelse return false;
    const start_index: usize = sd.codepoints.items.len - needles.len;
    // The starting codepoint must be a grapheme
    if (sd.graphemes.items[start_index] != 1) {
        return false;
    }

    if (cs == CaseSensitive.Yes) {
        return std.mem.endsWith(Codepoint, sd.codepoints.items, needles);
    }

    if (sd.codepoints.items.len < needles.len) {
        return false;
    }

    for (sd.codepoints.items[start_index..], needles) |l, r| {
        if (ctx.cd.toUpper(l) != ctx.cd.toUpper(r)) {
            return false;
        }
    }

    return true;
}

pub fn endsWithStr(self: String, needles: String, cs: CaseSensitive) bool {
    const sdn = needles.d orelse return false;
    return self.endsWithSlice(sdn.codepoints.items, cs);
}

pub fn ensureTotalCapacity(self: *String, cp_count: usize) !void {
    var sd = try self.getPointer();
    try sd.graphemes.ensureTotalCapacity(cp_count);
    try sd.codepoints.ensureTotalCapacity(cp_count);
}

pub fn eq(self: String, input: []const u8) bool {
    return self.equals(input, CaseSensitive.Yes);
}

pub fn eqStr(self: String, other: String) bool {
    return self.equalsStr(other, CaseSensitive.Yes);
}

pub fn equals(self: String, input: []const u8, cs: CaseSensitive) bool {
    const list = toCodepoints(ctx.a, input) catch return false;
    defer list.deinit();
    return self.equalsSlice(list.items, cs);
}

pub fn equalsSlice(self: String, slice: CpSlice, cs: CaseSensitive) bool {
    if (slice.len == 0) {
        return self.isEmpty();
    }
    
    const sd = self.d orelse return false;
    if (cs == CaseSensitive.Yes) {
        return std.mem.eql(Codepoint, sd.codepoints.items, slice);
    }

    if (sd.codepoints.items.len != slice.len) {
        return false;
    }

    for (sd.codepoints.items, slice) |l, r| {
        if (ctx.cd.toUpper(l) != ctx.cd.toUpper(r)) {
            return false;
        }
    }

    return true;
}

pub fn equalsStr(self: String, other: String, cs: CaseSensitive) bool {
    const sdo = other.d orelse return false;
    return self.equalsSlice(sdo.codepoints.items, cs);
}

fn findCaseInsensitive(graphemes: []u1, haystack: ConstCpSlice, needles: ConstCpSlice) ?usize {
    var index: ?usize = null;
    const till: usize = haystack.len - needles.len + 1;
    for (0..till) |i| {
        index = i;
        for (needles, haystack[i .. i + needles.len]) |l, r| {
            if (ctx.cd.toUpper(l) != ctx.cd.toUpper(r)) {
                index = null;
                break;
            }
        }
        if (index) |idx| {
            // making sure it ends up on a grapheme boundary so
            // that i.e. we don't find the 'e' in "Jos\u{65}\u{301}"
            const end = idx + needles.len;
            if (end == haystack.len or graphemes[end] == 1) {
                break;
            }
        }
    }

    return index;
}

pub fn findManyLinear(self: String, needles: ConstCpSlice, start: ?Index, cs: CaseSensitive) ?Index {
    const sd = self.d orelse return null;
    const cp_count = sd.codepoints.items.len;
    if (needles.len > cp_count) {
        //out.print("needles > cp_count\n", .{}) catch return null;
        return null;
    }

    const from = start orelse Index.strStart();
    var pos = from.cp;
    var index: usize = undefined;
    while (pos < cp_count) {
        const haystack = sd.codepoints.items[pos..];
        if (cs == CaseSensitive.Yes) {
            index = std.mem.indexOf(Codepoint, haystack, needles) orelse return null;
        } else {
            const graphemes = sd.graphemes.items[pos..];
            index = findCaseInsensitive(graphemes, haystack, needles) orelse return null;
        }
        //out.print("{s} index={}\n", .{@src().fn_name, index}) catch return null;
        pos += index;
        const is_at_haystack_end = (pos >= (cp_count - 1));
        const next_cp_loc = pos + needles.len;
        if (is_at_haystack_end or next_cp_loc >= cp_count or (sd.graphemes.items[next_cp_loc] == 1)) { // is at end
            const slice = sd.graphemes.items[0..pos];
            const gr = countGraphemesLinear(slice);

            return Index{ .cp = pos, .gr = gr };
        }

        pos += 1;
    }

    return null;
}

pub fn findManySimd(self: String, needles: ConstCpSlice, from_index: ?Index, comptime depth: u16) ?Index {
    const sd = self.d orelse return null;
    const from = from_index orelse Index.strStart();
    const cp_count = sd.codepoints.items.len;
    if ((needles.len == 0) or (needles.len > cp_count) or (from.cp >= cp_count)) {
        // Not sure if I should be checking for any of this.
        return null;
    }
    const haystack = sd.codepoints.items[from.cp..];
    const graphemes = sd.graphemes.items[from.cp..];
    var pos: usize = from.cp;
    const first_needle = needles[0];
    while (pos < cp_count) {
        const found_abs = self.findOneSimd(first_needle, pos, depth) orelse {
            return null;
        };

        const first = found_abs - from.cp; // @first is now relative to haystack slice, not to self.codepoints
        var all_match = true;
        for (needles[1..], 1..) |cp, i| {
            if (haystack[first + i] != cp) {
                all_match = false;
                break;
            }
        }

        if (all_match) {
            // Make sure the found result ends on a grapheme cluster boundary,
            // which is true if either it reached the end of the string
            // or the next code point starts a new grapheme cluster:
            const query_end = first + needles.len;
            if ((query_end >= graphemes.len) or (graphemes[query_end] == 1)) {
                // Warning: "(graphemes[query_end] == 1)" must stay after "or", otherwise the app
                // will crash if query_end==graphemes.len!
                const gr = countGraphemesSimd(sd.graphemes.items[0..found_abs]);
                return Index{ .cp = found_abs, .gr = gr };
            }
        }

        pos = found_abs + 1;
    }

    //mtl.debug(@src(), "Found nothing, at end of func", .{});
    return null;
}

pub fn findOneSimd(self: String, needle: Codepoint, from: usize, comptime vec_len: u16) ?usize {
    const sd = self.d orelse return null;
    const haystack = sd.codepoints.items[from..];
    const vector_needles: @Vector(vec_len, Codepoint) = @splat(needle);
    // {0, 1, 2, 3, 4, 5, 6, 7, ..vec_len-1?}
    const vec_indices = std.simd.iota(Codepoint, vec_len);
    // Code points greater than 0x10FFFF are invalid (Unicode standard)
    const nulls: @Vector(vec_len, Codepoint) = @splat(0x10FFFF + 1);
    var pos: usize = 0;

    while (pos < haystack.len) {
        if ((haystack.len - pos) < vec_len) {
            // fallback to a normal scan when our input (or what's left of
            // it is smaller than our vec_len)
            const ret = std.mem.indexOfScalarPos(Codepoint, haystack, pos, needle);
            const index = if (ret) |k| (k + from) else null;
            // out.print("{s} found={?}(from={}), fallback to normal scan\n",
            // .{@src().fn_name, index, from}) catch {};

            return index;
        }

        const h: @Vector(vec_len, Codepoint) = haystack[pos..][0..vec_len].*;
        const does_match = h == vector_needles;

        if (@reduce(.Or, does_match)) { // does it have any true value, if so,
            // we have a match, we just need to find its index
            const result = @select(Codepoint, does_match, vec_indices, nulls);

            const index = pos + @reduce(.Min, result);
            // out.print("{s} returning FoundAt={}, from={}\n",
            // .{@src().fn_name, index + from, from}) catch {};
            return index + from;
        }

        pos += vec_len;
    }

    //out.print("{s} nothing, end of func\n", .{@src().fn_name}) catch {};
    return null;
}

pub fn findOneSimdFromEnd(self: String, needle: Codepoint, start: ?usize, comptime vector_len: ?u16) ?usize {
    const sd = self.d orelse return null;
    const items = sd.codepoints.items;
    const from = start orelse items.len;
    const haystack = items[0..from];
    const vec_len = vector_len orelse SimdVecLen;
    const vector_needles: @Vector(vec_len, Codepoint) = @splat(needle);
    // {0, 1, 2, 3, 4, 5, 6, 7, ..vec_len-1}
    const vec_indices = std.simd.iota(Codepoint, vec_len);
    const nulls: @Vector(vec_len, Codepoint) = @splat(0);
    var pos: usize = haystack.len;

    while (pos > 0) {
        if (pos < vec_len) {
            const ret = std.mem.lastIndexOfScalar(Codepoint, haystack[0..pos], needle);
            return if (ret) |k| k else null;
        }

        const vector_loc = pos - vec_len;
        const h: @Vector(vec_len, Codepoint) = haystack[vector_loc..][0..vec_len].*;
        const does_match = h == vector_needles;

        if (@reduce(.Or, does_match)) {
            const data_vec = @select(Codepoint, does_match, vec_indices, nulls);
            const index = @reduce(.Max, data_vec);
            return index + vector_loc;
        }

        pos -= vec_len;
    }

    return null;
}

/// format implements the `std.fmt` format interface for printing types.
pub fn format(self: String, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = options;
    const buf = self.toString() catch return;
    defer buf.deinit();
    if (fmt.len == 2) {
        const fmtstr = "{s}{s}{s}{s}{s}";
        if (std.mem.eql(u8, fmt, "dt")) { // hilite for dt="Dark Theme"
            try writer.print(fmtstr, .{COLOR_BLACK, BGCOLOR_YELLOW, buf.items, BGCOLOR_DEFAULT, COLOR_DEFAULT});
            return;
        } else if (std.mem.eql(u8, fmt, "lt")) {// hilite for lt="Light Theme"
            try writer.print(fmtstr, .{COLOR_BLACK, BGCOLOR_YELLOW, buf.items, BGCOLOR_DEFAULT, COLOR_DEFAULT});
            return;
        }
    }
    try writer.print("{s}", .{buf.items});
}

pub fn getU3(data: []const u8, u3_index: usize) !u3 {
    const bit_index = u3_index * 3;
    const byte_index = bit_index / 8;
    const remainder: u3 = @intCast(bit_index % 8);
    const byte = data[byte_index];
    if (remainder <= 5) {
        const k = (byte >> remainder) & 0b111;
        return @intCast(k);
    } else if (remainder == 6) {
        var b: u8 = byte >> 6;
        const nb = data[byte_index + 1];
        b |= (nb << 2) & 0b0000_0100;
        return @intCast(b);
    } else {
        var b: u8 = byte >> 7;
        const nb = data[byte_index + 1] << 1;
        b |= nb & 0b0000_0110;
        return @intCast(b);
    }
}

pub fn fromBlob(reader: anytype) !String {
    const cp_count: usize = try readCpCount(reader);
    var ret_str = String{};
    if (cp_count == 0)
        return ret_str;

    var sd = try ret_str.getPointer();
    try ret_str.ensureTotalCapacity(cp_count);
    const cp_bit_count = cp_count * 3;
    var info_byte_count = cp_bit_count / 8;
    if ((cp_bit_count % 8) != 0) {
        info_byte_count += 1;
    }

    const info_data = try ctx.a.alloc(u8, info_byte_count);
    defer ctx.a.free(info_data);
    const len = try reader.read(info_data);
    if (len != info_data.len) {
        @panic("len != info_data.len");
    }
    // var under_u8: usize = 0;
    // var under_u16: usize = 0;
    // var too_large: usize = 0;
    for (0..cp_count) |i| {
        const info: u3 = try getU3(info_data, i);
        //mtl.debug(@src(), "i={}, u3=0b{b:0>3}", .{i, info});
        const gr_bit: u1 = @intCast(info >> 2);
        try sd.graphemes.append(gr_bit);
        if (gr_bit == 0b1) {
            sd.grapheme_count += 1;
        }
        const sz = info & 0b011;
        var cp: u21 = 0;
        if (sz == 0b01) { // u8
            cp = try reader.readByte();
        } else if (sz == 0b10) { // u16
            cp = try reader.readInt(u16, .big);
        } else {
            const k = try reader.readInt(u24, .big);
            cp = @intCast(k);
        }

        try sd.codepoints.append(cp);
        // if (cp <= maxInt(u8)) {
        //     under_u8 += 1;
        // } else if (cp <= maxInt(u16)) {
        //     under_u16 += 1;
        // } else {
        //     too_large += 1;
        // }
    }

    //mtl.debug(@src(), "u8={}, u16={}, u24={}", .{Num.New(under_u8), Num.New(under_u16), Num.New(too_large)});
    return ret_str;
}

pub fn getData(self: *const String) ?*const Data {
    if (self.d) |*k| {
        return k;
    }
    return null;
}

inline fn getPointer(self: *String) !*Data {
    if (self.d) |*k| {
        return k;
    } else {
        self.initEmpty();
        return if (self.d) |*k| k else Error.Alloc;
    }
}

pub fn graphemeAddressFromCp(self: String, codepoint_index: usize) ?Index {
    const sd = self.d orelse return null;
    const gr = countGraphemes(sd.graphemes.items[0 .. codepoint_index + 1]);
    if (gr) |g| {
        return Index{ .cp = codepoint_index, .gr = g };
    }
    return null;
}

pub fn graphemeAddress(self: String, grapheme_index: usize) ?Index {
    const sd = self.d orelse return null;
    if (grapheme_index >= sd.grapheme_count) {
        return null;
    }
    
    const slice = sd.graphemes.items[0..];
    var cp_index: isize = -1;
    var current_grapheme: isize = -1;
    for (slice) |k| {
        cp_index += 1;
        if (k == 1) {
            current_grapheme += 1;
        }
        if (grapheme_index == current_grapheme)
            return Index{ .cp = @abs(cp_index), .gr = grapheme_index };
    }

    return null;
}

pub fn graphemeMatchesAnyCodepoint(self: String, index: Index, slice: CpSlice) bool {
    const sd = self.d orelse return false;
    const codepoints = sd.codepoints.items;
    const graphemes = sd.graphemes.items;
    for (slice) |cp| {
        if ((codepoints[index.cp] != cp) or (graphemes[index.cp] != 1)) {
            continue;
        }

        // Here we're just making sure this grapheme is 1 codepoint length
        // to respect grapheme cluster boundaries.
        const at_end = index.cp == codepoints.len - 1;
        if (at_end or graphemes[index.cp + 1] == 1)
            return true;
    }

    return false;
}

pub fn graphemesToUtf8(alloc: Allocator, input: CpSlice) !ArrayList(u8) {
    return utf8_from_slice(alloc, input);
}

pub const Find = struct {
    from: usize = 0,
    cs: CaseSensitive = CaseSensitive.Yes,
};

pub fn indexOfAscii(self: String, input: []const u8, find: Find) ?Index {
    var from = Index.strStart();
    if (find.from != 0) {
        from = self.graphemeAddress(find.from) orelse return null;
    }

    if (input.len == 1) {
        const cp: Codepoint = input[0];
        var arr = [_]Codepoint {cp};
        const cps: CpSlice = arr[0..1];
        return self.indexOfCp2(cps, from, find.cs);
    } else {
        return self.indexOfCp(input, from, find.cs);
    }
}

// each char in the array must be one codepoint
pub fn indexOfCp(self: String, input: []const u8, from: Index, cs: CaseSensitive) ?Index {
    var input_cps = toCodepoints(ctx.a, input) catch return null;
    defer input_cps.deinit();
    return self.indexOfCp2(input_cps.items, from, cs);
}

pub fn indexOfCp2(self: String, input: CpSlice, from: Index, cs: CaseSensitive) ?Index {
    const sd = self.d orelse return null;
    if (cs == CaseSensitive.No) {
        toUpper2(input) catch return null;
    }
    var grapheme_count: isize = @intCast(from.gr);
    for (sd.codepoints.items[from.cp..], 0..) |cp, cp_index| {
        const at = from.cp + cp_index;
        if (!self.isGrapheme(at)) {
            continue;
        }
        grapheme_count += 1;
        const l = if (cs == CaseSensitive.Yes) cp else (toUpperCp(cp) catch return null);
        for (input) |r| {
            if (l == r) {
                // Make sure the next codepoint is the end of the string or a new grapheme
                // so that we don't return a part of a multi-codepoint grapheme.
                const next = at + 1;
                if (next >= sd.graphemes.items.len or sd.graphemes.items[next] == 1) {
                    return Index{ .cp = at, .gr = @intCast(grapheme_count - 1) };
                }
            }
        }
    }

    return null;
}

pub const FindIndex = struct {
    from: Index = Index.strStart(),
    cs: CaseSensitive = CaseSensitive.Yes,
};

pub fn indexOf(self: String, input: []const u8, find: Find) ?Index {
    if (find.from == 0) {
        return self.indexOf2(input, .{.cs = find.cs});
    }
    const index = self.graphemeAddress(find.from) orelse return null;
    return self.indexOf2(input, .{.from=index, .cs=find.cs});
}

pub fn indexOf2(self: String, input: []const u8, find: FindIndex) ?Index {
    if (input.len == 0)
        return null;
    const sd = self.d orelse return null;
    const from = find.from;
    var slice: ConstCpSlice = undefined;
    var needles: ArrayList(Codepoint) = undefined;
    if (input.len == 1) {
        const cp = toCp(input) catch return null;
        slice = &[_]Codepoint {cp};
    } else {
        needles = String.toCodepoints(ctx.a, input) catch return null;
        slice = needles.items;
    }

    // mtl.debug(@src(), "slice: {any}, input: {s}", .{slice, input});
    var idx: ?Index = undefined;
    if (find.cs == CaseSensitive.Yes and sd.codepoints.items.len >= SimdVecLen) {
        idx = self.findManySimd(slice, from, SimdVecLen);
    } else {
        idx = self.findManyLinear(slice, find.from, find.cs);
    }

    if (input.len != 1)
        needles.deinit();

    return idx;
}

pub fn indexOf3(self: String, needles: CpSlice, from_index: ?Index, cs: CaseSensitive) ?Index {
    if (needles.len == 0)
        return null;
    const sd = self.d orelse return null;
    const from = from_index orelse Index.strStart();
    if (cs == CaseSensitive.Yes and sd.codepoints.items.len >= SimdVecLen) {
        return self.findManySimd(needles, from, SimdVecLen);
    }
    return self.findManyLinear(needles, from, cs);
}

inline fn endsWithGrapheme(a: []const u1, end: usize) bool {
    if (a.len < end)
        return false;
    if (a.len == end)
        return true; // goes till the end, which implies it ends with a grapheme

    return a[end] == 1;// the next one is a grapheme, therefore the previous sequence ends with a grapheme
}

pub fn init(self: *String, input: []const u8, clear: Clear) !void {
    if (clear == Clear.Yes) {
        self.clearAndFree();
    }

    if (input.len == 0)
        return;

    var sd: *Data = try self.getPointer();
    var cp_count: usize = 0;
    const approx = @max(input.len / 2, 2);
    try sd.codepoints.ensureTotalCapacity(approx);
    try sd.graphemes.ensureTotalCapacity(approx);
    var gc_iter = zg_grapheme.Iterator.init(input, &ctx.grapheme_data);
    while (gc_iter.next()) |grapheme| {
        sd.grapheme_count += 1;
        var new_grapheme = true;
        const bytes = grapheme.bytes(input);
        var cp_iter = zg_codepoint.Iterator{ .bytes = bytes };
        while (cp_iter.next()) |obj| {
            cp_count += 1;
            try sd.graphemes.append(if (new_grapheme) 1 else 0);
            if (new_grapheme) {
                new_grapheme = false;
            }
            try sd.codepoints.append(obj.code);
        }
    }
}

/// inserts `what` at grapheme index `at(.gr)`
pub fn insert(self: *String, at_gr_pos: ?Index, what: []const u8) !void {
    var input = try String.From(what);
    defer input.deinit();
    try self.insertStr(at_gr_pos, input);
}

pub fn insertStr(self: *String, at_pos: ?Index, input: String) !void {
    if (input.isEmpty())
        return;
    const index = at_pos orelse return;
    var sd = try self.getPointer();
    const sdo = input.d orelse return Error.Alloc;
    try sd.codepoints.insertSlice(index.cp, sdo.codepoints.items);
    try sd.graphemes.insertSlice(index.cp, sdo.graphemes.items);
    sd.grapheme_count += sdo.grapheme_count;
}

pub fn isEmpty(self: String) bool {
    return if (self.d) |sd| sd.grapheme_count == 0 else true;
}

inline fn isGrapheme(self: String, i: usize) bool {
    const sd = self.d orelse return false;
    return sd.graphemes.items[i] == 1;
}

pub fn isWordChar(cp: Codepoint) bool {
    return (cp >= 'A' and cp <= 'Z') or (cp >= 'a' and cp <= 'z') or
        (cp >= '0' and cp <= '9') or (cp == '_');
}

pub fn iterator(self: *const String) Iterator {
    return Iterator.New(self, null);
}

pub fn iteratorFrom(self: *const String, from: Index) Iterator {
    return Iterator.New(self, from);
}

pub fn lastIndexOf(self: String, needles: []const u8, from_index: ?Index) ?Index {
    const cp_needles = toCodepoints(ctx.a, needles) catch return null;
    defer cp_needles.deinit();
    return self.lastIndexOf2(cp_needles.items, from_index, null);
}

pub fn lastIndexOf2(self: String, needles: CpSlice, start: ?Index, comptime vector_len: ?u16) ?Index {
    const sd = self.d orelse return null;
    const vec_len = vector_len orelse SimdVecLen;
    const from = start orelse self.strEnd();
    const cp_count = sd.codepoints.items.len;
    if ((needles.len == 0) or (needles.len > cp_count) or (from.cp == 0)) {
        // Not sure if I should be checking for any of this.
        return null;
    }
    const haystack = sd.codepoints.items[0..from.cp];
    const graphemes = sd.graphemes.items[0..from.cp];
    var pos: usize = from.cp;
    const first_needle = needles[0];
    while (pos > 0) {
        const found_index = self.findOneSimdFromEnd(first_needle, pos, vec_len) orelse {
            return null;
        };
        if (found_index + needles.len >= haystack.len) {
            return null;
        }
        var all_match = true;
        for (needles[1..], 1..) |cp, i| {
            if (haystack[found_index + i] != cp) {
                all_match = false;
                break;
            }
        }

        if (all_match) {
            // Make sure the found result ends on a grapheme cluster boundary,
            // which is true if either it reached the end of the string
            // or the next code point starts a new grapheme cluster:
            const query_end = found_index + needles.len;
            if ((query_end >= graphemes.len) or (graphemes[query_end] == 1)) {
                // Warning: above "(graphemes[query_end] == 1)" must stay after "or",
                // otherwise the app will crash if query_end==graphemes.len!
                const slice = sd.graphemes.items[0..found_index];
                const gr = countGraphemesSimd(slice);
                return Index{ .cp = found_index, .gr = gr };
            }
        }

        pos = found_index; // the next search happens to the left of `found_index`
    }

    return null;
}

/// Returned value is the position right after the matched string
pub fn matches(self: String, needles: []const u8, from: Index) ?Index { // ADD CASE sensitivity!
    if (needles.len == 0) {
        // mtl.debug(@src(), "needles.len == 0", .{});
        return null;
    }

    // const input = String.toCodepoints(ctx.a, needles) catch return null;
    // defer input.deinit();
    const input = String.From(needles) catch return null;
    defer input.deinit();
    return self.matchesStr(input, from);
}

pub fn matchesStr(self: String, input: String, from: Index) ?Index {
    
    const sd = self.d orelse return null;
    const end = from.cp + input.size_cp();
    if (!endsWithGrapheme(sd.graphemes.items, end)) {
        return null;
    }

    const str_cps = sd.codepoints.items[from.cp..end];
    const str_graphemes = sd.graphemes.items[from.cp..end];
    var gr_count: usize = 0;
    const input_sd = input.d orelse return null;
    const needles_cps = input_sd.codepoints.items;
    for (str_cps, needles_cps, str_graphemes)|a, b, gr| {
        if (a != b) {
            return null;
        }

        if (gr == 1)
            gr_count += 1;
    }

    return Index {.cp = end, .gr = from.gr + gr_count};
}

pub fn mid(self: String, start: usize, count: isize) !String {
    return self.substring(start, count);
}

pub fn midIndex(self: String, from_index: Index) !String {
    var sd = self.d orelse return String{};
    return String{
        .d = try sd.CloneFrom(from_index),
    };
}

/// parseInt tries to parse this Zigstr as an integer of type `T` in base `radix`.
pub fn parseInt(self: String, comptime T: type, radix: u8) !T {
    const buf = try self.toString();
    defer buf.deinit();
    return std.fmt.parseInt(T, buf.items, radix);
}

/// parseFloat tries to parse this Zigstr as an floating point number of type `T`.
pub fn parseFloat(self: String, comptime T: type) !T {
    const buf = try self.toString();
    defer buf.deinit();
    return std.fmt.parseFloat(T, buf.items);
}

pub threadlocal var string_theme = Theme.Dark;
pub fn print(self: String, src: std.builtin.SourceLocation, msg: ?[]const u8) void {
    self.print2(src, string_theme, msg);
}

pub fn print2(self: String, src: std.builtin.SourceLocation, theme: Theme, msg: ?[]const u8) void {
    const color = if (theme == Theme.Light) COLOR_DEFAULT else COLOR_GREEN;
    const info = if (msg) |k| k else "String.print(): ";
    mtl.debug(src, "{s}{s}\"{s}\"", .{ info, color, self});
}

pub fn printInfo(self: String, src: std.builtin.SourceLocation, msg: ?[] const u8) void {
    const color = if (string_theme == Theme.Light) COLOR_DEFAULT else COLOR_GREEN;
    const info = if (msg) |k| k else "String.printInfo(): ";
    if (self.size() <= 255) {
        mtl.debug(src, "{s}[gr={},cp={}]={s}\"{s}\"", .{ info, Num.New(self.size()), Num.New(self.size_cp()), color, self});
    } else {
        mtl.debug(src, "{s}[gr={},cp={}]={s}", .{ info, Num.New(self.size()), Num.New(self.size_cp()), color});
    }
}

const print_format_str = "{s}{}{s}{s}[{s}]{s}{s}{s}{s} ";
const nl_chars = UNDERLINE_START ++ "(LF)" ++ UNDERLINE_END;
const cr_chars = UNDERLINE_START ++ "(CR)" ++ UNDERLINE_END;
const crnl_chars = UNDERLINE_START ++ "(CR/LF)" ++ UNDERLINE_END;

fn printCpBuf(out: anytype, cp_buf: ArrayList(Codepoint), gr_index: isize, see_as: SeeAs, attr: Attr) !void {
    const theme = string_theme;
    if (cp_buf.items.len == 0)
        return;

    var codepoints_str = String{};
    defer codepoints_str.deinit();
    var temp_str_buf: [32]u8 = undefined;

    for (cp_buf.items, 0..) |k, i| {
        const num_as_str = try std.fmt.bufPrint(&temp_str_buf, "{d}", .{k});
        try codepoints_str.add(num_as_str);
        const s = if (i < cp_buf.items.len - 1) "+" else " ";
        try codepoints_str.add(s);
    }

    var utf8: ArrayList(u8) = try utf8_from_slice(ctx.a, cp_buf.items);
    defer utf8.deinit();
    var cp_as_str: []const u8 = utf8.items;
    if (cp_buf.items.len == 1) {
        const cp = cp_buf.items[0];
        if (cp == 10) {
            cp_as_str = nl_chars;
        } else if (cp == 13) {
            cp_as_str = cr_chars;
        }
    } else if (cp_buf.items.len == 2) {
        if (cp_buf.items[0] == 13 and cp_buf.items[1] == 10) {
            cp_as_str = crnl_chars;
        }
    }
    const cp_color: []const u8 = if (see_as == SeeAs.PartOfGrapheme) COLOR_GREEN else COLOR_MAGENTA;
    var final_fg: []const u8 = if (theme == Theme.Light) COLOR_BLACK else cp_color;
    if (attr == Attr.Codepoint) {
        final_fg = COLOR_RED ++ BOLD_START;
    }
    const end_final_fg = if (attr == Attr.Codepoint) COLOR_DEFAULT ++ BOLD_END else COLOR_DEFAULT;
    const num_color = if (theme == Theme.Light) "\x1B[38;5;196m" else COLOR_YELLOW;
    out.print(print_format_str, .{ COLOR_BLUE, gr_index, COLOR_DEFAULT, final_fg, cp_as_str, end_final_fg, num_color, codepoints_str, COLOR_DEFAULT });
}

pub fn printCodepoints(self: String, src: std.builtin.SourceLocation) !void {
    const sd = self.d orelse return Error.Alloc;
    var cp_buf = ArrayList(Codepoint).init(ctx.a);
    defer cp_buf.deinit();
    const out = std.debug;
    self.print(src, "Codepoints: ");
    for (sd.codepoints.items, 0..) |cp, i| {
        if (i > 255) {
            break;
        }
        const attr = if (sd.graphemes.items[i] == 1) Attr.Grapheme else Attr.Codepoint;
        try cp_buf.append(cp);
        try printCpBuf(out, cp_buf, @intCast(i), SeeAs.CodepointOnly, attr);
        cp_buf.clearRetainingCapacity();
    }
    out.print("\n", .{});
}

pub fn printGraphemes(self: String, src: std.builtin.SourceLocation) !void {
    const sd = self.d orelse return Error.Alloc;
    var cp_buf = std.ArrayList(Codepoint).init(ctx.a);
    defer cp_buf.deinit();
    var gr_index: isize = -1;
    const out = std.debug;
    self.print(src, "Graphemes: ");
    for (sd.codepoints.items, 0..) |cp, i| {
        if (i > 255) {
            break;
        }

        if (sd.graphemes.items[i] == 1) {
            try printCpBuf(out, cp_buf, gr_index, SeeAs.PartOfGrapheme, Attr.Ignore);
            gr_index += 1;
            cp_buf.clearRetainingCapacity();
        }

        try cp_buf.append(cp);
    }

    try printCpBuf(out, cp_buf, gr_index, SeeAs.PartOfGrapheme, Attr.Ignore);
    out.print("\n", .{});
}

pub fn printFind(self: String, needles: []const u8, from: usize, cs: CaseSensitive) ?Index {
    const index = self.indexOf(needles, from, cs);
    const needles_str = String.From(needles) catch return null;
    defer needles_str.deinit();
    return index;
}

fn readCpCount(reader: anytype) !usize {
    const value: u8 = try reader.readByte();
    if (value == 0)
        return 0;

    if ((value & BinaryHintMask) == BinaryHintByte) {
        return value & ~BinaryHintMask;
    }

    const count = try reader.readInt(u64, .big);
    return count;
}

pub fn remove(self: *String, needles: []const u8) !void {
    const from = self.indexOf(needles, .{});
    const count = countGraphemesRaw(ctx.a, needles);
    try self.removeByIndex(from, count);
}

pub fn removeByIndex(self: *String, start_index: ?Index, gr_count_to_remove: usize) !void {
    var sd = try self.getPointer();
    const start = start_index orelse return;
    if (gr_count_to_remove == 0)
        return; // removing zero graphemes is not an error

    var cp_count: usize = 0;
    var gr_so_far: usize = 0;
    var break_at_next = false;
    for (sd.graphemes.items[start.cp..]) |b| {
        cp_count += 1;
        if (b == 1) {
            if (break_at_next) {
                cp_count -= 1;
                break;
            }
            gr_so_far += 1;
            if (gr_so_far == gr_count_to_remove) {
                break_at_next = true; // go till the end of the grapheme
                continue;
            }
        }
    }

    const till = @min(sd.codepoints.items.len, start.cp + cp_count);
    const len_in_cp = till - start.cp;
    try self.removeLowLevel(start.cp, len_in_cp);
}

pub fn removeLowLevel(self: *String, from_cp: usize, cp_count: usize) !void {
    var sd = try self.getPointer();
    const new_cps: []const Codepoint = &[_]Codepoint{};
    try sd.codepoints.replaceRange(from_cp, cp_count, new_cps);

    const new_grs: []const u1 = &[_]u1{};
    try sd.graphemes.replaceRange(from_cp, cp_count, new_grs);

    sd.grapheme_count -= cp_count;
}

pub fn replace(self: *String, start_index: ?Index, gr_count_to_remove: usize, replacement: []const u8) !void {
    try self.removeByIndex(start_index, gr_count_to_remove);
    try self.insert(start_index, replacement);
}

pub fn replaceStr(self: *String, start_index: ?Index, gr_count_to_remove: usize, replacement: String) !void {
    try self.removeByIndex(start_index, gr_count_to_remove);
    try self.insertStr(start_index, replacement);
}

pub fn resetTo(self: *String, str: []const u8) !void {
    try self.init(str, Clear.Yes);
}

pub fn reset(self: *String) void {
    self.clearAndFree();
}

/// returns the graphemes count in string
pub fn size(self: String) usize {
    return if (self.d) |sd| sd.grapheme_count else 0;
}

/// returns the codepoints count in string
pub fn size_cp(self: String) usize {
    return if (self.d) |sd| sd.codepoints.items.len else 0;
}

// Each `sep` grapheme must be 1 codepoint long
pub fn split(self: String, sep: []const u8, cs: CaseSensitive, kep: KeepEmptyParts) !ArrayList(String) {
    const sd = self.d orelse return Error.Alloc;
    var array = std.ArrayList(String).init(ctx.a);
    errdefer {
        for (array.items) |item| {
            item.deinit();
        }
        array.deinit();
    }

    var from = Index.strStart();
    while (self.indexOfCp(sep, from, cs)) |found| {
        const s = try self.mid(from.gr, @intCast(found.gr - from.gr));
        from = Index{ .cp = found.cp + 1, .gr = found.gr + 1 };

        if (kep == KeepEmptyParts.No and s.isEmpty()) {
            s.deinit();
            continue;
        }

        try array.append(s);
        if (from.cp >= sd.codepoints.items.len) {
            break;
        }
    }

    if (from.cp < sd.codepoints.items.len) {
        const s = try self.mid(from.gr, -1);
        if (kep == KeepEmptyParts.No and s.isEmpty()) {
            //try s.print(std.debug, "Skipping2: ");
            s.deinit();
        } else {
            try array.append(s);
        }
    }

    return array;
}

pub fn startsWith(self: String, phrase: []const u8, cs: CaseSensitive) !bool {
    const needles = try String.toCodepoints(ctx.a, phrase);
    defer needles.deinit();
    return self.startsWithSlice(needles.items, cs);
}

/// `letter` must resolve to one codepoint, which all ASCII chars are.
pub fn startsWithChar(self: String, letter: []const u8) bool {
    const cp = toCp(letter) catch return false;
    return self.startsWithCp(cp);
}

// returns true if the codepoint is a whole grapheme
pub fn startsWithCp(self: String, cp: Codepoint) bool {
    const sd = self.d orelse return false;
    const cp_slice = sd.codepoints.items[0..];
    if (cp_slice.len == 0 or cp_slice[0] != cp)
        return false;
    const gr_list = sd.graphemes.items[0..];
    return gr_list.len == 1 or gr_list[1] == 1; // it's either the end or the next cp is a grapheme
}

pub fn startsWithSlice(self: String, needles: CpSlice, cs: CaseSensitive) bool {
    const sd = self.d orelse return false;
    if (sd.graphemes.items.len > needles.len) {
        // make sure it ends on a grapheme boundary:
        if (sd.graphemes.items[needles.len] != 1) {
            return false;
        }
    }

    if (cs == CaseSensitive.Yes) {
        return std.mem.startsWith(Codepoint, sd.codepoints.items, needles);
    }

    if (sd.codepoints.items.len < needles.len) {
        return false;
    }

    for (sd.codepoints.items[0..needles.len], needles) |l, r| {
        if (ctx.cd.toUpper(l) != ctx.cd.toUpper(r)) {
            return false;
        }
    }

    return true;
}

pub fn startsWithStr(self: String, needles: String, cs: CaseSensitive) bool {
    const sdn = needles.d orelse return false;
    return self.startsWithSlice(sdn.codepoints.items, cs);
}

pub fn strEnd(self: String) Index {
    const sd = self.d orelse return strStart();
    var i: usize = sd.codepoints.items.len;
    while (i > 0) {
        i -= 1;
        if (sd.graphemes.items[i] == 1) {
            break;
        }
    }

    return Index {.cp = i, .gr = sd.grapheme_count - 1};
}

/// returns `Index` of the first item
pub fn strStart() Index {
    return Index{};
}

pub fn substr(self: String, start: Index, how_many_gr: usize) !String {
    const sd = self.d orelse return Error.Other;
    if (start.gr + how_many_gr > sd.grapheme_count) {
        return Error.Index;
    }

    var gr_sofar: usize = 0;
    var cp_to_copy: usize = 0;
    for (sd.graphemes.items[start.cp..], 0..) |g, i| {
        if (g == 1) {
            gr_sofar += 1;
            if (gr_sofar > how_many_gr) {
                break;
            }
        }
        cp_to_copy = i + 1;
    }

    var s = String.New();
    try s.ensureTotalCapacity(cp_to_copy);
    errdefer s.deinit();
    var sdo = try s.getPointer();
    const end_cp: usize = start.cp + cp_to_copy;
    try sdo.codepoints.appendSlice(sd.codepoints.items[start.cp..end_cp]);
    try sdo.graphemes.appendSlice(sd.graphemes.items[start.cp..end_cp]);
    sdo.grapheme_count = countGraphemes(sdo.graphemes.items);

    return s;
}

pub fn substring(self: String, start: usize, count: isize) !String {
    const sd = self.d orelse return Error.Other;
    const how_many_gr: usize = if (count == -1) sd.grapheme_count - start else @intCast(count);
    const index = self.graphemeAddress(start) orelse return Error.NotFound;
    return self.substr(index, how_many_gr);
}

pub fn toCp(input: []const u8) !Codepoint {
    // This function is for `input` that is one codepoint in size.
    // This case is useful because:
    // a) no memory allocation is needed
    // b) the code is shorter cause no deallocation is needed
    // c) convenient for example for many text parsing
    // operations where delimiters are often known to be one
    // codepoint, like empty space, or "=", or "[", or "\n".
    var cp_iter = zg_codepoint.Iterator{ .bytes = input };
    if (cp_iter.next()) |obj| {
        return obj.code;
    }
    return Error.BadArg;
}

pub fn toCpAscii(a: comptime_int) !Codepoint {
    if (a > 127) {
        return Error.BadArg;
    }
    return a;
}

pub fn toCodepoints(a: Allocator, input: []const u8) !ArrayList(Codepoint) {
    var buf = ArrayList(Codepoint).init(a);
    errdefer buf.deinit();
    var cp_iter = zg_codepoint.Iterator{ .bytes = input };
    while (cp_iter.next()) |obj| {
        try buf.append(obj.code);
    }

    return buf;
}

pub fn toLower(self: *String) !void {
    const sd = try self.getPointer();
    try toLower2(sd.codepoints.items);
}

pub fn toLower2(list: CpSlice) !void {
    for (list) |*k| {
        k.* = ctx.cd.toLower(k.*);
    }
}

pub fn toString(self: String) !ArrayList(u8) {
    const sd = self.d orelse return ArrayList(u8).init(ctx.a);
    return utf8_from_slice(ctx.a, sd.codepoints.items);
}

pub fn toOwnedSlice(self: String) ![]const u8 {
    const arr = try self.toString();
    defer arr.deinit();
    var memory = try ctx.a.alloc(u8, arr.items.len);
    for (0..arr.items.len) |i| {
        memory[i] = arr.items[i];
    }

    return memory;
}

pub fn toUpper(self: *String) !void {
    const sd = try self.getPointer();
    try toUpper2(sd.codepoints.items);
}

pub fn toUpper2(list: CpSlice) !void {
    for (list) |*k| {
        k.* = ctx.cd.toUpper(k.*);
    }
}

pub fn toUpperCp(cp: Codepoint) !Codepoint {
    return ctx.cd.toUpper(cp);
}

pub fn trim(self: *String) !void {
    try self.trimLeft();
    try self.trimRight();
}

/// These are ASCII chars so they translate directly to codepoints
/// because UTF-8 guarantees that.
const CodepointsToTrim = [_]Codepoint{ ' ', '\t', '\n', '\r' };

pub fn trimLeft(self: *String) !void {
    const sd = try self.getPointer();
    const cp_count = sd.codepoints.items.len;
    if (cp_count == 0) {
        return;
    }

    var found_count: usize = 0;
    var i: usize = 0;
    while (i < cp_count) : (i += 1) {
        if (sd.graphemes.items[i] != 1)
            break;
        // is the grapheme one codepoint or larger?
        if ((i + 1) < cp_count) {
            if (sd.graphemes.items[i + 1] != 1) {
                break; // the grapheme is >=2 codepoints large, full stop.
            }
        }
        const cp = sd.codepoints.items[i];
        if (std.mem.indexOfScalar(u21, &CodepointsToTrim, cp)) |index| {
            _ = index;
            found_count += 1;
        } else {
            break;
        }
    }

    if (found_count > 0) {
        try self.removeLowLevel(0, found_count);
    }
}

pub fn trimRight(self: *String) !void {
    const sd = try self.getPointer();
    const cp_count = sd.codepoints.items.len;
    if (cp_count == 0) {
        return;
    }

    var found_count: usize = 0;
    var i = cp_count;
    while (i > 0) {
        i -= 1;
        if (sd.graphemes.items[i] != 1)
            break;
        const cp = sd.codepoints.items[i];
        if (std.mem.indexOfScalar(u21, &CodepointsToTrim, cp)) |index| {
            _ = index;
            found_count += 1;
        }
    }

    if (found_count > 0) {
        const from_cp = cp_count - found_count;
        try self.removeLowLevel(from_cp, found_count);
    }
}

pub fn utf8_from_cp(a: Allocator, cp: Codepoint) !ArrayList(u8) {
    var buf = ArrayList(u8).init(a);
    errdefer buf.deinit();
    var tmp: [4]u8 = undefined;
    const len = try unicode.utf8Encode(cp, &tmp);
    try buf.appendSlice(tmp[0..len]);

    return buf;
}

pub fn utf8_from_slice(a: Allocator, slice: ConstCpSlice) !ArrayList(u8) {
    var buf = ArrayList(u8).init(a);
    errdefer buf.deinit();
    var tmp: [4]u8 = undefined;
    //mtl.debug(@src(), "slice.len={}, slice={any}", .{slice.len, slice});
    for (slice) |cp| {
        const len = try unicode.utf8Encode(cp, &tmp);
        try buf.appendSlice(tmp[0..len]);
    }

    return buf;
}

fn writeCpCount(out: anytype, count: u64) !void {
    if (count == 0) {
        try out.writeByte(0);
    } else if (count <= BinaryMaxByte) {
        //mtl.debug(@src(), "writing as byte={}", .{count});
        var z: u8 = @intCast(count);
        z |= BinaryHintByte;
        try out.writeByte(z);
    } else {
        //mtl.debug(@src(), "writing as u64={}", .{count});
        try out.writeByte(BinaryHintU64);
        try out.writeInt(u64, count, .big);
    }
}

pub fn toBlob(self: String, alloc: Allocator) ![]const u8 {
    const str_byte_count = self.computeSizeInBytes();
    const memory = try alloc.alloc(u8, str_byte_count);
    errdefer alloc.free(memory);
    var stream = std.io.fixedBufferStream(memory);
    const writer = stream.writer();
    const cp_count = self.size_cp();
    try writeCpCount(writer, cp_count);
    if (cp_count == 0) {
        return memory;
    }
    
    const sd = self.d orelse return String.Error.Other;
    var under_u8: usize = 0;
    var under_u16: usize = 0;
    var full_size: usize = 0;
    var bit_data = BitData.New(alloc);
    defer bit_data.deinit();

    for (sd.codepoints.items, sd.graphemes.items) |cp, grapheme_bit| {
        var n: u3 = 0;
        if (cp <= maxInt(u8)) {
            under_u8 += 1;
            n = 0b01;
        } else if (cp <= maxInt(u16)) {
            under_u16 += 1;
            n = 0b10;
        } else {
            full_size += 1;
            n = 0b11;
        }

        n |= @as(u3, grapheme_bit) << 2;
        try bit_data.addBits(n);
    }

    try bit_data.finish();
    //bit_data.printBits();
    try writer.writeAll(bit_data.bytes());

    for (sd.codepoints.items) |cp| {
        if (cp <= maxInt(u8)) {
            try writer.writeByte(@intCast(cp));
        } else if (cp <= maxInt(u16)) {
            try writer.writeInt(u16, @intCast(cp), .big);
        } else {
            try writer.writeInt(u24, @intCast(cp), .big);
        }
    }

    //self.printInfo(@src(), null);
    // mtl.debug(@src(), "u8={}, u16={}, u24={}",
    //     .{Num.New(under_u8), Num.New(under_u16), Num.New(full_size)});

    return memory;
}

const posix = (builtin.target.os.tag != .windows);

pub const COLOR_BLACK = if (posix) "\x1B[38;5;16m" else "";
pub const COLOR_BLUE = if (posix) "\x1B[34m" else "";
pub const COLOR_CYAN = if (posix) "\x1B[36m" else "";
pub const COLOR_DEFAULT = if (posix) "\x1B[0m" else "";
pub const COLOR_GREEN = if (posix) "\x1B[32m" else "";
pub const COLOR_LIGHTGRAY = if (posix) "\x1B[37m" else "";
pub const COLOR_MAGENTA = if (posix) "\x1B[35m" else "";
pub const COLOR_ORANGE = if (posix) "\x1B[0;33m" else "";
pub const COLOR_RED = if (posix) "\x1B[0;91m" else "";
pub const COLOR_YELLOW = if (posix) "\x1B[93m" else "";

pub const BGCOLOR_BLACK = if (posix) "\x1B[40m" else "";
pub const BGCOLOR_BLUE = if (posix) "\x1B[44m" else "";
pub const BGCOLOR_DEFAULT = if (posix) "\x1B[49m" else "";
pub const BGCOLOR_GREEN = if (posix) "\x1B[42m" else "";
pub const BGCOLOR_LIGHTGRAY = if (posix) "\x1B[47m" else "";
pub const BGCOLOR_MAGENTA = if (posix) "\x1B[45m" else "";
pub const BGCOLOR_ORANGE = if (posix) "\x1B[43m" else "";
pub const BGCOLOR_RED = if (posix) "\x1B[41m" else "";
pub const BGCOLOR_YELLOW = if (posix) "\x1B[103m" else "";

pub const BLINK_START = if (posix) "\x1B[5m" else "";
pub const BLINK_END = if (posix) "\x1B[25m" else "";
pub const BOLD_START = if (posix) "\x1B[1m" else "";
pub const BOLD_END = if (posix) "\x1B[0m" else "";
pub const UNDERLINE_START = if (posix) "\x1B[4m" else "";
pub const UNDERLINE_END = if (posix) "\x1B[0m" else "";
