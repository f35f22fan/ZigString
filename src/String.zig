const std = @import("std");
const unicode = std.unicode;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
//const out = std.io.getStdOut().writer();

const zgl = @import("ziglyph");
const letter = zgl.letter;
const number = zgl.number;

const Grapheme = zgl.Grapheme;
const GraphemeIterator = Grapheme.GraphemeIterator;

pub const Codepoint = u21;
pub const CodePointSlice = []Codepoint;
pub const GraphemeSlice = []const u1;
pub const String = @This();
pub const Error = error{ NotFound, BadArg, Index, Alloc };
const SimdVecLen: u16 = 32;

pub const KeepEmptyParts = enum(u8) {
    Yes,
    No,
};

pub const CaseSensitive = enum(u8) {
    Yes,
    No,
};

pub const Index = struct {
    cp: usize = 0,
    gr: usize = 0,
    gr_size: u3 = 1, // how many codepoints is the grapheme

    fn advance_to_next_grapheme(self: *Index, s: String) void {
        self.cp += 1;
        const gr_slice = s.graphemes.items[self.cp..];
        for (gr_slice, 0..) |gr_bit, i| {
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
        const from_cp = self.cp;
        if (from_cp >= s.codepoints.items.len)
            return null;

        const gr_slice = s.graphemes.items[from_cp..];
        for (gr_slice, 0..) |gr_bit, i| {
            if (gr_bit == 1) {
                self.cp = from_cp + i;
                const index = self.*;
                self.advance_to_next_grapheme(s);
                return index;
            }
        }

        return null;
    }

    pub fn prev(self: Index, s: String) ?Index {
        const cp_count = s.codepoints.items.len;
        if (self.cp == 0 or self.cp >= cp_count)
            return null;

        var i: usize = self.cp - 1;
        while (i > 0) : (i -= 1) {
            const b = s.graphemes.items[i];
            if (b == 1) {
                return Index{ .cp = i, .gr = self.gr - 1 };
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

codepoints: ArrayList(Codepoint) = undefined,
graphemes: ArrayList(u1) = undefined,
grapheme_count: usize = 0,
a: Allocator = undefined,

pub fn clearAndFree(self: *String) void {
    self.codepoints.clearAndFree();
    self.graphemes.clearAndFree();
    self.grapheme_count = 0;
}

pub fn clearRetainingCapacity(self: *String) void {
    self.codepoints.clearRetainingCapacity();
    self.graphemes.clearRetainingCapacity();
    self.grapheme_count = 0;
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

pub fn append(self: *String, what: []const u8) !void {
    var input = try String.From(self.a, what);
    defer input.deinit();
    try self.appendStr(input);
}

pub fn appendStr(self: *String, other: String) !void {
    try self.codepoints.appendSlice(other.codepoints.items);
    try self.graphemes.appendSlice(other.graphemes.items);
    self.grapheme_count += other.grapheme_count;
}

pub fn contains(self: String, str: []const u8) bool {
    return self.indexOf(str, null) != null;
}

pub fn contains2(self: String, str: CodePointSlice) bool {
    return self.indexOf2(str, null) != null;
}

pub fn containsStr(self: String, needles: String) bool {
    return self.indexOf2(needles.codepoints.items, null) != null;
}

pub fn deinit(self: String) void {
    self.codepoints.deinit();
    self.graphemes.deinit();
}

pub fn endsWith(self: String, phrase: []const u8, cs: CaseSensitive) bool {
    const needles = toCodePoints(self.a, phrase) catch return false;
    defer needles.deinit();
    return self.endsWithSlice(needles.items, cs);
}

pub fn endsWithSlice(self: String, needles: CodePointSlice, cs: CaseSensitive) bool {
    const start_index: usize = self.codepoints.items.len - needles.len;
    // The starting codepoint must be a grapheme
    if (self.graphemes.items[start_index] != 1) {
        return false;
    }

    if (cs == CaseSensitive.Yes) {
        return std.mem.endsWith(Codepoint, self.codepoints.items, needles);
    }

    if (self.codepoints.items.len < needles.len) {
        return false;
    }

    for (self.codepoints.items[start_index..], needles) |l, r| {
        if (letter.toUpper(l) != letter.toUpper(r)) {
            return false;
        }
    }

    return true;
}

pub fn endsWithStr(self: String, needles: String, cs: CaseSensitive) bool {
    return self.endsWithSlice(needles.codepoints.items, cs);
}

pub fn equals(self: String, input: []const u8, cs: CaseSensitive) !bool {
    const list = try toCodePoints(self.a, input);
    defer list.deinit();
    return self.equalsSlice(list.items, cs);
}

pub fn equalsSlice(self: String, slice: CodePointSlice, cs: CaseSensitive) bool {
    if (cs == CaseSensitive.Yes) {
        return std.mem.eql(Codepoint, self.codepoints.items, slice);
    }

    if (self.codepoints.items.len != slice.len) {
        return false;
    }

    for (self.codepoints.items, slice) |l, r| {
        if (letter.toUpper(l) != letter.toUpper(r)) {
            return false;
        }
    }

    return true;
}

pub fn equalsStr(self: String, other: String, cs: CaseSensitive) bool {
    return self.equalsSlice(other.codepoints.items, cs);
}

fn findCaseInsensitive(graphemes: []u1, haystack: CodePointSlice, needles: CodePointSlice) ?usize {
    var index: ?usize = null;
    const till: usize = haystack.len - needles.len + 1;
    // std.debug.print("{s}(): func start, till={}, haystack={}, needles={}\n",
    //     .{@src().fn_name, till, haystack.len, needles.len});
    for (0..till) |i| {
        index = i;
        for (needles, haystack[i .. i + needles.len]) |l, r| {
            if (letter.toUpper(l) != letter.toUpper(r)) {
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

pub fn findManyLinear(self: String, needles: CodePointSlice, start: ?Index, cs: CaseSensitive) ?Index {
    const cp_count = self.codepoints.items.len;
    if (needles.len > cp_count) {
        //out.print("needles > cp_count\n", .{}) catch return null;
        return null;
    }

    const from = start orelse Index.strStart();
    var pos = from.cp;
    var index: usize = undefined;
    while (pos < cp_count) {
        const haystack = self.codepoints.items[pos..];
        if (cs == CaseSensitive.Yes) {
            index = std.mem.indexOf(Codepoint, haystack, needles) orelse return null;
        } else {
            const graphemes = self.graphemes.items[pos..];
            index = findCaseInsensitive(graphemes, haystack, needles) orelse return null;
        }
        //out.print("{s} index={}\n", .{@src().fn_name, index}) catch return null;
        pos += index;
        const is_at_haystack_end = (pos >= (cp_count - 1));
        const next_cp_loc = pos + needles.len;
        if (is_at_haystack_end or next_cp_loc >= cp_count or (self.graphemes.items[next_cp_loc] == 1)) { // is at end
            const slice = self.graphemes.items[0..pos];
            const gr = countGraphemesLinear(slice);

            return Index{ .cp = pos, .gr = gr };
        }

        pos += 1;
    }

    return null;
}

pub fn findManySimd(self: String, needles: CodePointSlice, from_index: ?Index, comptime depth: u16) ?Index {
    const from = from_index orelse Index.strStart();
    const cp_count = self.codepoints.items.len;
    if ((needles.len == 0) or (needles.len > cp_count) or (from.cp >= cp_count)) {
        // Not sure if I should be checking for any of this.
        //std.debug.print("Bad params. Needles.len={}, haystack.len={}, from={?}\n",
        //.{ needles.len, cp_count, from });
        return null;
    }
    const haystack = self.codepoints.items[from.cp..];
    const graphemes = self.graphemes.items[from.cp..];
    var pos: usize = from.cp;
    const first_needle = needles[0];
    while (pos < cp_count) {
        const found_abs = self.findOneSimd(first_needle, pos, depth) orelse {
            //std.debug.print("{s}() found nothing\n", .{@src().fn_name});
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
                const gr = countGraphemesSimd(self.graphemes.items[0..found_abs]);
                return Index{ .cp = found_abs, .gr = gr };
            }
        }

        pos = found_abs + 1;
    }

    std.debug.print("{s} found nothing, at end of func\n", .{@src().fn_name});
    return null;
}

pub fn findOneSimd(self: String, needle: Codepoint, from: usize, comptime vec_len: u16) ?usize {
    const haystack = self.codepoints.items[from..];
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
    const items = self.codepoints.items;
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

inline fn isGrapheme(self: String, i: usize) bool {
    return self.graphemes.items[i] == 1;
}

pub fn New(a: Allocator, capacity: usize) !String {
    var obj = String{};
    obj.a = a;
    obj.graphemes = ArrayList(u1).init(a);
    obj.codepoints = ArrayList(Codepoint).init(a);
    if (capacity > 0) {
        try obj.graphemes.ensureTotalCapacity(capacity);
        try obj.codepoints.ensureTotalCapacity(capacity);
    }

    return obj;
}

pub fn From(a: Allocator, input: []const u8) !String {
    var obj = String{};
    obj.a = a;
    obj.graphemes = ArrayList(u1).init(a);
    obj.codepoints = ArrayList(Codepoint).init(a);
    try obj.init(input, false);

    return obj;
}

pub fn At(self: String, gr_index: usize) ?Index {
    return self.graphemeAddress(gr_index);
}

/// This operation is O(n)
pub fn graphemeIndex(codepoint_pos: usize, slice: GraphemeSlice) ?usize {
    return countGraphemes(slice[0 .. codepoint_pos + 1]);
}

pub fn graphemeAddress(self: String, grapheme_index: usize) ?Index {
    if (grapheme_index >= self.grapheme_count) {
        return null;
    }
    var current_grapheme: isize = -1;
    const slice = self.graphemes.items[0..];
    var cp_index: isize = -1;
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

pub fn graphemeMatchesAnyCodepoint(self: String, index: Index, slice: CodePointSlice) bool {
    const codepoints = self.codepoints.items;
    const graphemes = self.graphemes.items;
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

pub fn graphemesToUtf8(alloc: Allocator, input: CodePointSlice) !ArrayList(u8) {
    return utf8_from_slice(alloc, input);
}

// each char in the array must be one codepoint
pub fn indexOfCp(self: String, input: []const u8, from: Index, cs: CaseSensitive) ?Index {
    var arr = toCodePoints(self.a, input) catch return null;
    defer arr.deinit();
    if (cs == CaseSensitive.No) {
        toUpper3(arr.items);
    }
    return self.indexOfCp2(arr.items, from, cs);
}

pub fn indexOfCp2(self: String, input: CodePointSlice, from: Index, cs: CaseSensitive) ?Index {
    var grapheme_count: isize = @intCast(from.gr);
    for (self.codepoints.items[from.cp..], 0..) |cp, cp_index| {
        const at = from.cp + cp_index;
        const is_grapheme = (self.graphemes.items[at] == 1);
        if (!is_grapheme) {
            continue;
        }
        grapheme_count += 1;
        const l = if (cs == CaseSensitive.Yes) cp else toUpperCp(cp);
        for (input) |r| {
            if (l == r) {
                // Make sure the next codepoint is the end of the string or a new grapheme
                // so that we don't return a part of a multi-codepoint grapheme.
                const next = at + 1;
                if (next >= self.graphemes.items.len or self.graphemes.items[next] == 1) {
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
    const needles = String.toCodePoints(self.a, input) catch return null;
    defer needles.deinit();
    const from = from_index orelse Index.strStart();
    if (cs == CaseSensitive.Yes and self.codepoints.items.len >= SimdVecLen) {
        return self.findManySimd(needles.items, from, SimdVecLen);
    }

    return self.findManyLinear(needles.items, from, cs);
}

pub fn indexOf3(self: String, needles: CodePointSlice, from_index: ?Index, cs: CaseSensitive) ?Index {
    const from = from_index orelse Index.strStart();
    if (cs == CaseSensitive.Yes and self.codepoints.items.len >= SimdVecLen) {
        return self.findManySimd(needles, from, SimdVecLen);
    }
    return self.findManyLinear(needles, from, cs);
}

pub fn isEmpty(self: String) bool {
    return self.grapheme_count == 0;
}

pub fn lastIndexOf(self: String, needles: []const u8, from_index: ?Index) ?Index {
    const cp_needles = toCodePoints(self.a, needles) catch return null;
    defer cp_needles.deinit();
    return self.lastIndexOf2(cp_needles.items, from_index, null);
}

pub fn lastIndexOf2(self: String, needles: CodePointSlice, start: ?Index, comptime vector_len: ?u16) ?Index {
    const vec_len = vector_len orelse SimdVecLen;
    const from = start orelse self.strEnd();
    const cp_count = self.codepoints.items.len;
    if ((needles.len == 0) or (needles.len > cp_count) or (from.cp == 0)) {
        // Not sure if I should be checking for any of this.
        // std.debug.print("Bad args. Needles.len={}, haystack.len={}, from={}\n",
        // .{ needles.len, cp_count, from });
        return null;
    }
    const haystack = self.codepoints.items[0..from.cp];
    const graphemes = self.graphemes.items[0..from.cp];
    var pos: usize = from.cp;
    const first_needle = needles[0];
    while (pos > 0) {
        const found_index = self.findOneSimdFromEnd(first_needle, pos, vec_len) orelse {
            //std.debug.print("{s}() found nothing\n", .{@src().fn_name});
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
                const slice = self.graphemes.items[0..found_index];
                const gr = countGraphemesSimd(slice);
                return Index{ .cp = found_index, .gr = gr };
            }
        }

        pos = found_index; // the next search happens to the left of `found_index`
    }

    //std.debug.print("{s} found nothing, at end of func\n", .{@src().fn_name});
    return null;
}

pub fn init(self: *String, input: []const u8, clear: bool) !void {
    if (clear) {
        self.codepoints.clearAndFree();
        self.graphemes.clearAndFree();
        self.grapheme_count = 0;
    }

    if (input.len == 0)
        return;

    var cp_count: usize = 0;
    const approx = @max(input.len / 2, 2);
    try self.codepoints.ensureTotalCapacity(approx);
    try self.graphemes.ensureTotalCapacity(input.len); // because 1bit per cp
    var gc_iter = GraphemeIterator.init(input);
    while (gc_iter.next()) |grapheme| {
        self.grapheme_count += 1;
        var new_grapheme = true;
        const bytes = grapheme.slice(input);
        var cp_iter = zgl.CodePointIterator{ .bytes = bytes };
        while (cp_iter.next()) |obj| {
            cp_count += 1;
            try self.graphemes.append(if (new_grapheme) 1 else 0);
            if (new_grapheme) {
                new_grapheme = false;
            }
            try self.codepoints.append(obj.code);
        }
    }

    try self.codepoints.resize(cp_count);
    try self.graphemes.resize(cp_count);
}

/// inserts `what` at grapheme index `at(.gr)`
pub fn insert(self: *String, at_pos: ?Index, what: []const u8) !void {
    var input = try String.From(self.a, what);
    defer input.deinit();
    try self.insertStr(at_pos, input);
}

pub fn insertStr(self: *String, at_pos: ?Index, input: String) !void {
    const index = at_pos orelse return;
    try self.codepoints.insertSlice(index.cp, input.codepoints.items);
    try self.graphemes.insertSlice(index.cp, input.graphemes.items);
    self.grapheme_count += input.grapheme_count;
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

const print_format_str = "{s}{}{s}{s}|{s}|{s}{s}{s}{s} ";
const nl_chars = UNDERLINE_START ++ "(LF)" ++ UNDERLINE_END;
const cr_chars = UNDERLINE_START ++ "(CR)" ++ UNDERLINE_END;
const crnl_chars = UNDERLINE_START ++ "(CR/LF)" ++ UNDERLINE_END;
fn printCpBuf(alloc: Allocator, out: anytype, cp_buf: ArrayList(Codepoint), gr_index: isize) !void {
    if (cp_buf.items.len == 0)
        return;

    var codepoints_str = try String.New(alloc, 16);
    defer codepoints_str.deinit();
    var temp_str_buf: [32]u8 = undefined;
    
    for (cp_buf.items, 0..) |k, i| {
        const num_as_str = try std.fmt.bufPrint(&temp_str_buf, "{d}", .{k});
        try codepoints_str.append(num_as_str);
        const s = if (i < cp_buf.items.len - 1) "+" else " ";
        try codepoints_str.append(s);
    }

    var utf8: ArrayList(u8) = try utf8_from_slice(alloc, cp_buf.items);
    defer utf8.deinit();
    var visible: []const u8 = utf8.items;
    if (cp_buf.items.len == 1) {
        const cp = cp_buf.items[0];
        if (cp == 10) {
            visible = nl_chars;
        } else if (cp == 13) {
            visible = cr_chars;
        }
    } else if (cp_buf.items.len == 2) {
        if (cp_buf.items[0] == 13 and cp_buf.items[1] == 10) {
            visible = crnl_chars;
        }
    }
    out.print(print_format_str, .{ COLOR_BLUE, gr_index, COLOR_DEFAULT, COLOR_GREEN, visible, COLOR_DEFAULT, COLOR_YELLOW, codepoints_str, COLOR_DEFAULT });
    //codepoints_str.clearRetainingCapacity();
}

pub fn printCodepoints(self: String, out: anytype) !void {
    var temp_str_buf: [32]u8 = undefined;
    for (self.codepoints.items, 0..) |cp, i| {
        if (i > 255) {
            break;
        }
        const is_grapheme = (self.graphemes.items[i] == 1);
        const color = if (is_grapheme) COLOR_MAGENTA else COLOR_RED;
        const utf8 = try utf8_from_cp(self.a, cp);
        defer utf8.deinit();
        const num_as_str = try std.fmt.bufPrint(&temp_str_buf, "{d} ", .{cp});
        out.print(print_format_str, .{ COLOR_BLUE, i, COLOR_DEFAULT, color, utf8.items, COLOR_DEFAULT, COLOR_YELLOW, num_as_str, COLOR_DEFAULT });
    }
    out.print("\n", .{});
}

pub fn printGraphemes(self: String, out: anytype) !void {
    var cp_buf = std.ArrayList(Codepoint).init(self.a);
    defer cp_buf.deinit();
    var gr_index: isize = -1;

    for (self.codepoints.items, 0..) |cp, i| {
        if (i > 255) {
            break;
        }

        if (self.isGrapheme(i)) {
            gr_index += 1;
            try printCpBuf(self.a, out, cp_buf, gr_index);
            cp_buf.clearRetainingCapacity();
        }

        try cp_buf.append(cp);
    }

    gr_index += 1;
    try printCpBuf(self.a, out, cp_buf, gr_index);
    out.print("\n", .{});
}

pub fn countGraphemesRaw(input: []const u8) usize {
    var gr_iter = GraphemeIterator.init(input);
    var grapheme_count: usize = 0;
    while (gr_iter.next()) |grapheme| {
        _ = grapheme;
        grapheme_count += 1;
    }

    return grapheme_count;
}

pub fn remove(self: *String, needles: []const u8) !void {
    const from = self.indexOf(needles, 0, CaseSensitive.Yes);
    const count = countGraphemesRaw(needles);
    //std.debug.print("{s}(): grapheme count={}\n", .{@src().fn_name, count});
    try self.removeByIndex(from, count);
}

pub fn removeByIndex(self: *String, start_index: ?Index, gr_count_to_remove: usize) !void {
    const start = start_index orelse return;
    if (gr_count_to_remove == 0)
        return; // removing zero graphemes is not an error

    var cp_count: usize = 0;
    var gr_so_far: usize = 0;
    var break_at_next = false;
    for (self.graphemes.items[start.cp..]) |b| {
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

    const till = @min(self.codepoints.items.len, start.cp + cp_count);
    const len_in_cp = till - start.cp;
    try self.removeLowLevel(start.cp, len_in_cp);
}

pub fn removeLowLevel(self: *String, from_cp: usize, cp_count: usize) !void {
    const new_cps: []const Codepoint = &[_]Codepoint{};
    try self.codepoints.replaceRange(from_cp, cp_count, new_cps);

    const new_grs: []const u1 = &[_]u1{};
    try self.graphemes.replaceRange(from_cp, cp_count, new_grs);

    self.grapheme_count -= cp_count;
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
    try self.init(str, true);
}

/// returns the number of graphemes in string
pub fn size(self: String) usize {
    return self.grapheme_count;
}

// Each `sep` grapheme must be 1 codepoint long
pub fn split(self: String, sep: []const u8, cs: CaseSensitive, kep: KeepEmptyParts) !ArrayList(String) {
    _ = kep;
    var array = std.ArrayList(String).init(self.a);
    errdefer array.deinit();
    //const empty = [_]u8{' ', '\t', '\n', '\r'};

    var from = Index.strStart();
    while (self.indexOfCp(sep, from, cs)) |found| {
        std.debug.print("{s}(): found={}\n", .{ @src().fn_name, found });
        const s = try self.mid(from.gr, @intCast(found.gr - from.gr));
        try array.append(s);
        from = Index{ .cp = found.cp + 1, .gr = found.gr + 1 };
        if (from.cp >= self.codepoints.items.len) {
            break;
        }
    }

    if (from.cp - 1 < self.codepoints.items.len) {
        const s = try self.mid(from.gr, -1);
        try array.append(s);
    }

    return array;
}

pub fn startsWith(self: String, phrase: []const u8, cs: CaseSensitive) !bool {
    const needles = try String.toCodePoints(self.a, phrase);
    defer needles.deinit();
    return self.startsWithSlice(needles.items, cs);
}

pub fn printFind(self: String, needles: []const u8, from: usize, cs: CaseSensitive) ?Index {
    const index = self.indexOf(needles, from, cs);
    const needles_str = String.From(self.a, needles) catch return null;
    defer needles_str.deinit();
    std.debug.print("{s}(): \"{s}(len={})\"=>{?}, haystack_len={}\n", .{ @src().fn_name, needles, needles_str.size(), index, self.size() });
    //self.printGraphemes(std.debug) catch {};
    return index;
}

pub fn startsWithSlice(self: String, needles: CodePointSlice, cs: CaseSensitive) bool {
    if (self.graphemes.items.len > needles.len) {
        // make sure it ends on a grapheme boundary:
        if (self.graphemes.items[needles.len] != 1) {
            return false;
        }
    }

    if (cs == CaseSensitive.Yes) {
        return std.mem.startsWith(Codepoint, self.codepoints.items, needles);
    }

    if (self.codepoints.items.len < needles.len) {
        return false;
    }

    for (self.codepoints.items[0..needles.len], needles) |l, r| {
        if (letter.toUpper(l) != letter.toUpper(r)) {
            return false;
        }
    }

    return true;
}

pub fn startsWithStr(self: String, needles: String, cs: CaseSensitive) bool {
    return self.startsWithSlice(needles.codepoints.items, cs);
}

/// returns `Index` after the last grapheme, exec is O(1)
pub fn strEnd(self: String) Index {
    return Index{ .cp = self.codepoints.items.len, .gr = self.grapheme_count };
}

/// returns `Index` of the first item
pub fn strStart() Index {
    return Index{};
}

pub fn substring(self: String, start: usize, count: isize) !String {
    const how_many_gr: usize = if (count == -1) self.grapheme_count - start else @intCast(count);
    const index = self.graphemeAddress(start) orelse return Error.Index;
    // std.debug.print("{s}:{} addr.cp={} .gr={} of={}\n",
    //     .{@src().fn_name, @src().line, index.cp, index.gr, start});
    if (index.gr + how_many_gr > self.grapheme_count) {
        return Error.Index;
    }

    var gr_sofar: usize = 0;
    var cp_to_copy: usize = 0;
    for (self.graphemes.items[index.cp..], 0..) |g, i| {
        if (g == 1) {
            gr_sofar += 1;
            if (gr_sofar > how_many_gr) {
                break;
            }
        }
        cp_to_copy = i + 1;
    }

    var s = try String.New(self.a, cp_to_copy);
    errdefer s.deinit();
    s.grapheme_count = index.gr;
    const end: usize = index.cp + cp_to_copy;
    try s.codepoints.appendSlice(self.codepoints.items[index.cp..end]);
    try s.graphemes.appendSlice(self.graphemes.items[index.cp..end]);

    return s;
}

pub fn toUpper(self: *String) void {
    toUpper3(self.codepoints.items);
}

pub fn toUpper2(self: String) ![]u8 {
    const buf = try self.toString();
    defer buf.deinit();
    return try zgl.toUpperStr(self.a, buf.items);
}

pub fn toUpper3(list: CodePointSlice) void {
    for (list) |*k| {
        k.* = letter.toUpper(k.*);
    }
}

pub fn toUpperCp(cp: Codepoint) Codepoint {
    return letter.toUpper(cp);
}

pub fn trim(self: *String) !void {
    try self.trimLeft();
    try self.trimRight();
}

const CodepointsToTrim = [_]Codepoint{ ' ', '\t', '\n', '\r' };

pub fn trimLeft(self: *String) !void {
    const cp_count = self.codepoints.items.len;
    if (cp_count == 0) {
        return;
    }

    var found_count: usize = 0;
    var i: usize = 0;
    while (i < cp_count) : (i += 1) {
        if (self.graphemes.items[i] != 1)
            break;
        // is the grapheme one codepoint or larger?
        if ((i + 1) < cp_count) {
            if (self.graphemes.items[i + 1] != 1) {
                break; // the grapheme is >=2 codepoints large, full stop.
            }
        }
        const cp = self.codepoints.items[i];
        if (std.mem.indexOfScalar(u21, &CodepointsToTrim, cp)) |index| {
            _ = index;
            found_count += 1;
        }
    }

    if (found_count > 0) {
        try self.removeLowLevel(0, found_count);
    }
}

pub fn trimRight(self: *String) !void {
    const cp_count = self.codepoints.items.len;
    if (cp_count == 0) {
        return;
    }

    var found_count: usize = 0;
    var i = cp_count;
    while (i > 0) {
        i -= 1;
        if (self.graphemes.items[i] != 1)
            break;
        const cp = self.codepoints.items[i];
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

pub fn utf8_from_slice(a: Allocator, slice: CodePointSlice) !ArrayList(u8) {
    var buf = ArrayList(u8).init(a);
    errdefer buf.deinit();
    var tmp: [4]u8 = undefined;
    for (slice) |cp| {
        const len = try unicode.utf8Encode(cp, &tmp);
        try buf.appendSlice(tmp[0..len]);
    }

    return buf;
}

pub fn toString(self: String) !ArrayList(u8) {
    return utf8_from_slice(self.a, self.codepoints.items);
}

pub fn toCodePoints(a: Allocator, input: []const u8) !ArrayList(Codepoint) {
    var buf = ArrayList(Codepoint).init(a);
    errdefer buf.deinit();
    var cp_iter = zgl.CodePointIterator{ .bytes = input };
    while (cp_iter.next()) |obj| {
        try buf.append(obj.code);
    }

    return buf;
}

const COLOR_BLUE = "\x1B[34m";
const COLOR_DEFAULT = "\x1B[0m";
const COLOR_GREEN = "\x1B[32m";
const COLOR_RED = "\x1B[0;91m";
const COLOR_YELLOW = "\x1B[93m";
const COLOR_MAGENTA = "\x1B[35m";
const BLINK_START = "\x1B[5m";
const BLINK_END = "\x1B[25m";
const BOLD_START = "\x1B[1m";
const BOLD_END = "\x1B[0m";
const UNDERLINE_START = "\x1B[4m";
const UNDERLINE_END = "\x1B[0m";
