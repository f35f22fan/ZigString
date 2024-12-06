pub const String = @This();
const std = @import("std");
const Print = std.debug.print;
const builtin = @import("builtin");
const unicode = std.unicode;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
//const out = std.io.getStdOut().writer();
const BitWriter = std.io.bit_writer.BitWriter;

const zg_codepoint = @import("code_point");
const zg_grapheme = @import("grapheme");
const CaseData = @import("CaseData");
const Normalize = @import("Normalize");
const CaseFold = @import("CaseFold");

pub const Codepoint = u21;
pub const CpSlice = []Codepoint;
pub const ConstCpSlice = []const Codepoint;
pub const GraphemeSlice = []const u1;
pub const Error = error{ NotFound, BadArg, Index, Alloc };
const SimdVecLen: u16 = 32;

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
    s: *const String,

    pub fn getSlice(self: Grapheme) ?CpSlice {
        const sd = self.s.d orelse return null;
        const len: usize = self.len;
        // std.debug.print("items.len={}, cp={}, len={}\n",
        //     .{sd.codepoints.items.len, self.idx.cp, len});
        return sd.codepoints.items[self.idx.cp..(self.idx.cp+len)];
    }

    pub fn eq(self: Grapheme, cp: Codepoint) bool {
        const slice = self.getSlice() orelse return false;
        return (slice.len == 1) and (slice[0] == cp);
    }

    pub fn eqAscii(self: Grapheme, c: comptime_int) bool {
        const cp = String.toCpAscii(c) catch return false;
        return self.eq(cp);
    }

    pub fn eqBytes(self: Grapheme, input: []const u8) bool {
        const buf = toCodepoints(ctx.a, input) catch return false;
        defer buf.deinit();
        return self.eqSlice(buf.items);
    }

    pub fn eqCp(self: Grapheme, input: []const u8) bool {
        const cp = toCp(input) catch return false;
        return self.eq(cp);
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

    pub fn format(self: Grapheme, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        const slice = self.getSlice() orelse return;
        const utf8 = try String.utf8_from_slice(ctx.a, slice);
        defer utf8.deinit();
        _ = try writer.print("{s}", .{utf8.items});
    }

    pub fn index(self: Grapheme) Index {
        return self.idx;
    }

    pub fn toOwned(self: Grapheme) !ArrayList(Codepoint) {
        var a = ArrayList(Codepoint).init(ctx.a);
        errdefer a.deinit();
        const sd = self.s.d orelse return String.Error.NotFound;
        const slice = sd.codepoints.items[0..];
        for (0..self.len) |k| {
            try a.append(slice[k]);
        }

        return a;
    }
};

pub const Index = struct {
    cp: usize = 0,
    gr: usize = 0,

    fn advance_to_next_grapheme(self: *Index, gr_slice: GraphemeSlice) void {
        self.cp += 1;
        const slice = gr_slice[self.cp..];
        for (slice, 0..) |gr_bit, i| {
            if (gr_bit == 1) {
                self.cp += i;
                self.gr += 1;
                return;
            }
        }
    }

    /// format implements the `std.fmt` format interface for printing types.
    pub fn format(self: Index, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        _ = try writer.print("Index{{cp={},gr={}}}", .{ self.cp, self.gr });
    }

    // Must return the next grapheme index
    pub fn next(self: *Index, s: String) ?Index {
        const sd = s.d orelse return null;
        const from_cp = self.cp;
        if (from_cp >= sd.codepoints.items.len)
            return null;

        const gr_slice = sd.graphemes.items[from_cp..];
        for (gr_slice, 0..) |gr_bit, i| {
            if (gr_bit == 1) {
                self.cp = from_cp + i;
                const index = self.*;
                self.advance_to_next_grapheme(sd.graphemes.items);
                return index;
            }
        }

        return null;
    }

    pub fn prev(self: *Index, s: String) ?Index {
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
        return Data{
            .codepoints = try self.codepoints.clone(),
            .graphemes = try self.graphemes.clone(),
            .grapheme_count = self.grapheme_count,
        };
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

pub fn append(self: *String, what: []const u8) !void {
    if (what.len == 1) {
        const cp = try toCp(what);
        var sd = try self.getPointer();
        try sd.codepoints.append(cp);
        try sd.graphemes.append(1);
        sd.grapheme_count += 1;
    } else {
        const input = try String.From(what);
        defer input.deinit();
        try self.appendStr(input);
    }
}

pub fn appendStr(self: *String, other: String) !void {
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

pub fn charAt(self: *const String, at: usize) ?Grapheme {
    const index = self.At(at) orelse return null;
    return self.charAtIndex(index);
}

pub fn charAtIndex(self: *const String, at: Index) ?Grapheme {
    const sd = self.d orelse return null;
    const slice = sd.codepoints.items[0..];
    if (at.cp >= slice.len)
        return null;
    
    var g = Grapheme{.s = self, .idx = at};
    const gr_slice = sd.graphemes.items[at.cp..];
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
        const matches = line == vec_needles;
        count += std.simd.countTrues(matches);
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
        //Print("Bad params. Needles.len={}, haystack.len={}, from={?}\n",
        //.{ needles.len, cp_count, from });
        return null;
    }
    const haystack = sd.codepoints.items[from.cp..];
    const graphemes = sd.graphemes.items[from.cp..];
    var pos: usize = from.cp;
    const first_needle = needles[0];
    while (pos < cp_count) {
        const found_abs = self.findOneSimd(first_needle, pos, depth) orelse {
            //Print("{s}() found nothing\n", .{@src().fn_name});
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

    //Print("{s} found nothing, at end of func\n", .{@src().fn_name});
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
        const matches = h == vector_needles;

        if (@reduce(.Or, matches)) { // does it have any true value, if so,
            // we have a match, we just need to find its index
            const result = @select(Codepoint, matches, vec_indices, nulls);

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
        const matches = h == vector_needles;

        if (@reduce(.Or, matches)) {
            const data_vec = @select(Codepoint, matches, vec_indices, nulls);
            const index = @reduce(.Max, data_vec);
            return index + vector_loc;
        }

        pos -= vec_len;
    }

    return null;
}

/// format implements the `std.fmt` format interface for printing types.
pub fn format(self: String, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;
    const buf = self.toString() catch return;
    defer buf.deinit();
    try writer.print("{s}", .{buf.items});
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

pub fn indexOf(self: String, input: []const u8, from_gr_index: usize, cs: CaseSensitive) ?Index {
    if (from_gr_index == 0) {
        return self.indexOf2(input, Index.strStart(), cs);
    }
    const index = self.graphemeAddress(from_gr_index) orelse return null;
    return self.indexOf2(input, index, cs);
}

pub fn indexOf2(self: String, input: []const u8, from_index: ?Index, cs: CaseSensitive) ?Index {
    const sd = self.d orelse return null;
    const needles = String.toCodepoints(ctx.a, input) catch return null;
    defer needles.deinit();
    const from = from_index orelse Index.strStart();
    if (cs == CaseSensitive.Yes and sd.codepoints.items.len >= SimdVecLen) {
        return self.findManySimd(needles.items, from, SimdVecLen);
    }

    return self.findManyLinear(needles.items, from, cs);
}

pub fn indexOf3(self: String, needles: CpSlice, from_index: ?Index, cs: CaseSensitive) ?Index {
    const sd = self.d orelse return null;
    const from = from_index orelse Index.strStart();
    if (cs == CaseSensitive.Yes and sd.codepoints.items.len >= SimdVecLen) {
        return self.findManySimd(needles, from, SimdVecLen);
    }
    return self.findManyLinear(needles, from, cs);
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
        // Print("Bad args. Needles.len={}, haystack.len={}, from={}\n",
        // .{ needles.len, cp_count, from });
        return null;
    }
    const haystack = sd.codepoints.items[0..from.cp];
    const graphemes = sd.graphemes.items[0..from.cp];
    var pos: usize = from.cp;
    const first_needle = needles[0];
    while (pos > 0) {
        const found_index = self.findOneSimdFromEnd(first_needle, pos, vec_len) orelse {
            //Print("{s}() found nothing\n", .{@src().fn_name});
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

    //Print("{s} found nothing, at end of func\n", .{@src().fn_name});
    return null;
}

pub fn mid(self: String, start: usize, count: isize) !String {
    return self.substring(start, count);
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
pub fn print(self: String, out: anytype, msg: ?[]const u8) !void {
    try self.print2(out, string_theme, msg);
}

pub fn print2(self: String, out: anytype, theme: Theme, msg: ?[]const u8) !void {
    const color = if (theme == Theme.Light) COLOR_DEFAULT else COLOR_GREEN;
    const info = if (msg) |k| k else "String.print(): ";
    out.print("{s}{s}\"{s}\"{s}\n", .{ info, color, self, COLOR_DEFAULT });
}

pub fn printInfo(self: String, out: anytype, msg: ?[] const u8) !void {
    const color = if (string_theme == Theme.Light) COLOR_DEFAULT else COLOR_GREEN;
    const info = if (msg) |k| k else "String.printInfo(): ";

    out.print("{s}[gr={},cp={}]={s}\"{s}\"{s}\n", .{ info, self.size(), self.size_cp(), color, self, COLOR_DEFAULT });
}

const print_format_str = "{s}{}{s}{s}[{s}]{s}{s}{s}{s} ";
const nl_chars = UNDERLINE_START ++ "(LF)" ++ UNDERLINE_END;
const cr_chars = UNDERLINE_START ++ "(CR)" ++ UNDERLINE_END;
const crnl_chars = UNDERLINE_START ++ "(CR/LF)" ++ UNDERLINE_END;

fn printCpBuf(out: anytype, cp_buf: ArrayList(Codepoint), gr_index: isize,
see_as: SeeAs, attr: Attr, theme: Theme) !void {
    if (cp_buf.items.len == 0)
        return;

    var codepoints_str = String{};
    defer codepoints_str.deinit();
    var temp_str_buf: [32]u8 = undefined;

    for (cp_buf.items, 0..) |k, i| {
        const num_as_str = try std.fmt.bufPrint(&temp_str_buf, "{d}", .{k});
        try codepoints_str.append(num_as_str);
        const s = if (i < cp_buf.items.len - 1) "+" else " ";
        try codepoints_str.append(s);
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

pub fn printCodepoints(self: String, out: anytype, theme: Theme) !void {
    const sd = self.d orelse return Error.Alloc;
    var cp_buf = ArrayList(Codepoint).init(ctx.a);
    defer cp_buf.deinit();
    out.print("Codepoints: ", .{});
    for (sd.codepoints.items, 0..) |cp, i| {
        if (i > 255) {
            break;
        }
        const attr = if (sd.graphemes.items[i] == 1) Attr.Grapheme else Attr.Codepoint;
        try cp_buf.append(cp);
        try printCpBuf(out, cp_buf, @intCast(i), SeeAs.CodepointOnly, attr, theme);
        cp_buf.clearRetainingCapacity();
    }
    out.print("\n", .{});
}

pub fn printGraphemes(self: String, out: anytype, theme: Theme) !void {
    const sd = self.d orelse return Error.Alloc;
    var cp_buf = std.ArrayList(Codepoint).init(ctx.a);
    defer cp_buf.deinit();
    var gr_index: isize = -1;
    out.print("Graphemes: ", .{});
    for (sd.codepoints.items, 0..) |cp, i| {
        if (i > 255) {
            break;
        }

        if (sd.graphemes.items[i] == 1) {
            try printCpBuf(out, cp_buf, gr_index, SeeAs.PartOfGrapheme, Attr.Ignore, theme);
            gr_index += 1;
            cp_buf.clearRetainingCapacity();
        }

        try cp_buf.append(cp);
    }

    try printCpBuf(out, cp_buf, gr_index, SeeAs.PartOfGrapheme, Attr.Ignore, theme);
    out.print("\n", .{});
}

pub fn printFind(self: String, needles: []const u8, from: usize, cs: CaseSensitive) ?Index {
    const index = self.indexOf(needles, from, cs);
    const needles_str = String.From(needles) catch return null;
    defer needles_str.deinit();
    Print("{s}(): \"{s}(len={})\"=>{?}, haystack_len={}\n", .{ @src().fn_name, needles, needles_str.size(), index, self.size() });
    //self.printGraphemes(std.debug) catch {};
    return index;
}

pub fn remove(self: *String, needles: []const u8) !void {
    const from = self.indexOf(needles, 0, CaseSensitive.Yes);
    const count = countGraphemesRaw(ctx.a, needles);
    //Print("{s}(): grapheme count={}\n", .{@src().fn_name, count});
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

pub fn reset(self: *String, str: []const u8) !void {
    try self.init(str, Clear.Yes);
}

/// returns the graphemes count in string
pub fn size(self: String) usize {
    return if (self.d) |sd| sd.grapheme_count else 0;
}

/// returns the codepoints count in string
pub fn size_cp(self: String) usize {
    return if (self.d) |sd| sd.codepoints.items.len else 0;
}

pub fn regionEquals(self: String, at: Index, slice: CpSlice, cs: CaseSensitive) bool {
    std.debug.print("{s} TBD.\n", .{@src().fn_name});
    _ = self;
    _ = at;
    _ = slice;
    _ = cs;
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
        //Print("{s}(): found={}\n", .{ @src().fn_name, found });
        const s = try self.mid(from.gr, @intCast(found.gr - from.gr));
        from = Index{ .cp = found.cp + 1, .gr = found.gr + 1 };

        if (kep == KeepEmptyParts.No and s.isEmpty()) {
            //try s.print(std.debug, "Skipping: ");
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

/// returns `Index` after the last grapheme, exec is O(1)
pub fn strEnd(self: String) Index {
    const sd = self.d orelse return strStart();
    return Index{ .cp = sd.codepoints.items.len, .gr = sd.grapheme_count };
}

/// returns `Index` of the first item
pub fn strStart() Index {
    return Index{};
}

pub fn substring(self: String, start: usize, count: isize) !String {
    const sd = self.d orelse return Error.Alloc;
    const how_many_gr: usize = if (count == -1) sd.grapheme_count - start else @intCast(count);
    const index = self.graphemeAddress(start) orelse return Error.NotFound;
    if (index.gr + how_many_gr > sd.grapheme_count) {
        return Error.Index;
    }

    var gr_sofar: usize = 0;
    var cp_to_copy: usize = 0;
    for (sd.graphemes.items[index.cp..], 0..) |g, i| {
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
    const end: usize = index.cp + cp_to_copy;
    try sdo.codepoints.appendSlice(sd.codepoints.items[index.cp..end]);
    try sdo.graphemes.appendSlice(sd.graphemes.items[index.cp..end]);
    sdo.grapheme_count = countGraphemes(sdo.graphemes.items);

    return s;
}

//const HintEmpty: u2 = 0;
const HintByte: u8 = 1 << 6;
const HintU16: u8 = 2 << 6;
const HintU64: u8 = 3 << 6;

fn readSize(in: anytype, msg: []const u8) !usize {
    var read_count: u16 = 0;
    const b1: u8 = try in.readBits(u8, @bitSizeOf(u8), &read_count);
    if (read_count != @bitSizeOf(u8)) {
        Print("{s}FN={s}:{}: msg=\"{s}\" count={}, b1={}{s}\n", .{ COLOR_RED, @src().fn_name, @src().line, msg, read_count, b1, COLOR_DEFAULT });
    }
    if (b1 == 0)
        return 0;

    if ((b1 & HintByte) == HintByte) {
        const retval = b1 & ~HintByte;
        return retval;
    }

    _ = try in.readBits(u8, @bitSizeOf(u8), &read_count);
    if (read_count != @bitSizeOf(u8)) {
        Print("{s}FN(u8/u64)={s}:{}: msg=\"{s}\" read_count={}{s}\n", .{ COLOR_RED, @src().fn_name, @src().line, msg, read_count, COLOR_DEFAULT });
    }
    const z = try in.readBits(u64, @bitSizeOf(u64), &read_count);
    if (read_count != @bitSizeOf(u64)) {
        Print("{s}FN(u64)={s}:{}: msg=\"{s}\" read_count={}{s}\n", .{ COLOR_RED, @src().fn_name, @src().line, msg, read_count, COLOR_DEFAULT });
    }
    return z;
}

fn writeSize(out: anytype, count: u64) !void {
    if (count == 0) {
        try out.writeBits(@as(u8, 0), @bitSizeOf(u8));
    } else if (count <= 0b0011_1111) {
        var z: u8 = @intCast(count);
        z |= HintByte;
        try out.writeBits(z, @bitSizeOf(u8));
    } else {
        try out.writeBits(HintU64, @bitSizeOf(u8));
        try out.writeBits(count, @bitSizeOf(u64));
    }
}

pub fn writeTo(self: String, bitw: anytype, f: Flush) !void {
    //var bitw = std.io.bitWriter(.big, out); //mem_out_be.writer());
    const cp_count = self.size_cp();
    try writeSize(bitw, cp_count);

    if (cp_count == 0)
        return;

    const sd = self.d orelse return;
    for (sd.codepoints.items) |cp| {
        try bitw.writeBits(cp, @bitSizeOf(@TypeOf(cp)));
    }

    for (sd.graphemes.items) |g| {
        try bitw.writeBits(g, 1);
    }

    try writeSize(bitw, sd.grapheme_count);
    if (f == Flush.Yes) {
        const rembits = 8 - bitw.count;
        std.debug.print("Remaining bits: {}\n", .{rembits});
        try bitw.flushBits();
    }
}

pub fn readFrom(bits: anytype) !String {
    //var bits = std.io.bitReader(.big, in);
    var read_count: u16 = 0;
    const cp_count: usize = try readSize(bits, "codepoints");
    std.debug.print("{s}(): cp count: {}\n", .{@src().fn_name, cp_count});
    var ret_str = String{};
    if (cp_count == 0)
        return ret_str;
    try ret_str.ensureTotalCapacity(cp_count);
    var sd = try ret_str.getPointer();
    for (0..cp_count) |_| {
        try sd.codepoints.append(try bits.readBits(Codepoint, @bitSizeOf(Codepoint), &read_count));
        if (read_count != @bitSizeOf(Codepoint)) {
            Print("{s}codepoint bit count read {}{s}\n", .{ COLOR_RED, read_count, COLOR_DEFAULT });
        }
    }
    for (0..cp_count) |_| {
        try sd.graphemes.append(try bits.readBits(u1, @bitSizeOf(u1), &read_count));
        if (read_count != @bitSizeOf(u1)) {
            Print("{s}grapheme bit count read {}{s}\n", .{ COLOR_RED, read_count, COLOR_DEFAULT });
        }
    }

    sd.grapheme_count = try readSize(bits, "grapheme count");
    return ret_str;
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
            //Print("{s}(): {}\n", .{ @src().fn_name, index });
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
    for (slice) |cp| {
        const len = try unicode.utf8Encode(cp, &tmp);
        try buf.appendSlice(tmp[0..len]);
    }

    return buf;
}

const posix = (builtin.target.os.tag == .linux);
pub const COLOR_BLUE = if (posix) "\x1B[34m" else "";
pub const COLOR_DEFAULT = if (posix) "\x1B[0m" else "";
pub const COLOR_GREEN = if (posix) "\x1B[32m" else "";
pub const COLOR_RED = if (posix) "\x1B[0;91m" else "";
pub const COLOR_YELLOW = if (posix) "\x1B[93m" else "";
pub const COLOR_MAGENTA = if (posix) "\x1B[35m" else "";
pub const COLOR_CYAN = if (posix) "\x1B[36m" else "";
pub const COLOR_BLACK = if (posix) "\x1B[38;5;16m" else "";
pub const BLINK_START = if (posix) "\x1B[5m" else "";
pub const BLINK_END = if (posix) "\x1B[25m" else "";
pub const BOLD_START = if (posix) "\x1B[1m" else "";
pub const BOLD_END = if (posix) "\x1B[0m" else "";
pub const UNDERLINE_START = if (posix) "\x1B[4m" else "";
pub const UNDERLINE_END = if (posix) "\x1B[0m" else "";
