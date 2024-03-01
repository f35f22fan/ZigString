const std = @import("std");
const unicode = std.unicode;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const out = std.io.getStdOut().writer();

const zgl = @import("ziglyph");
const letter = zgl.letter;
const number = zgl.number;

const Grapheme = zgl.Grapheme;
const GraphemeIterator = Grapheme.GraphemeIterator;

pub const CodePoint = u21;
pub const CodePointSlice = []const CodePoint;
pub const GraphemeSlice = []const u1;
pub const String = @This();
pub const Error = error{ NotFound, BadArg };
const SimdVecLen: u16 = 32;

pub const CaseSensitive = enum(u8) {
    Yes,
    No,
};

pub const Index = struct {
    cp: usize = 0,
    gr: usize = 0,

    /// format implements the `std.fmt` format interface for printing types.
    pub fn format(self: Index, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        _ = try writer.print("Index(cp={},gr={})", .{self.cp, self.gr});
    }

    pub fn next(self: Index, s: String) ?Index {
        const next_index = self.cp + 1;
        if (next_index >= s.codepoints.items.len)
            return null;

        const slice = s.graphemes.items[next_index..];
        for (slice, next_index..) |bit, index| {
            if (bit == 1) {
                return Index{ .cp = index, .gr = self.gr + 1 };
            }
        }

        return null;
    }

    pub fn prev(self: Index, s: String) ?Index {
        const cp_count = s.codepoints.items.len;
        if (self.cp == 0 or self.cp > cp_count)
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
};

pub const Iterator = struct {
    item: ?Index = null,
    s: String,
    first_run: bool = true,

// rewrite Iterator to clearly state when 1st item must be included.
    pub fn next(self: *Iterator) ?Index {
        if (self.item) |item| {
            if (self.first_run) {
                self.first_run = false;
                return item;
            }
            self.item = item.next(self.s);
        } else {
            self.item = String.strStart();
        }

        if (self.first_run)
            self.first_run = false;
        
        return self.item;
    }

    pub fn prev(self: *Iterator) ?Index {
        if (self.item) |item| {
            self.item = item.prev(self.s);
        } else {
            self.item = self.s.strEnd();
        }
        return self.item;
    }
};

const TimeExt = "mc";
inline fn getTime() i128 {
    return std.time.microTimestamp();
}

codepoints: ArrayList(CodePoint) = undefined,
graphemes: ArrayList(u1) = undefined,
grapheme_count: usize = 0,
a: Allocator = undefined,

inline fn countGraphemesLinear(slice: GraphemeSlice) usize {
    var count: usize = 0;
    for (slice) |n| {
        if (n == 1)
            count += 1;
    }

    return count;
}

fn countGraphemesSimd(slice: GraphemeSlice) usize {
    const vec_len: u16 = SimdVecLen;
    const needle: u1 = 1;
    var pos: usize = 0;
    var count: usize = 0;
    const vec_needles: @Vector(vec_len, u1) = @splat(needle);
    while (pos < slice.len) {
        if ((slice.len - pos) < vec_len) { // do it manually
            for (slice[pos..]) |k| {
                if (k == 1)
                    count += 1;
            }
            break;
        }
        const line: @Vector(vec_len, u1) = slice[pos..][0..vec_len].*;
        const matches = line == vec_needles;
        count += std.simd.countTrues(matches);
        pos += vec_len;
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

pub fn endsWith(self: String, phrase: []const u8) !bool {
    const needles = try toCodePoints(self.a, phrase);
    defer needles.deinit();
    return self.endsWithSlice(needles.items);
}

pub fn endsWithSlice(self: String, needles: CodePointSlice) bool {
    const items = self.codepoints.items;
    if (items.len < needles.len or !std.mem.endsWith(CodePoint, items, needles))
        return false;

    const start_index: usize = items.len - needles.len;
    return self.graphemes.items[start_index] == 1;
}

pub fn endsWithStr(self: String, needles: String) bool {
    return self.endsWithSlice(needles.codepoints.items);
}

pub fn equals(self: String, input: []const u8, cs: CaseSensitive) !bool {
    const list = try toCodePoints(self.a, input);
    defer list.deinit();
    return self.equalsSlice(list.items, cs);
}

pub fn equalsSlice(self: String, slice: CodePointSlice, cs: CaseSensitive) bool {
    if (self.codepoints.items.len != slice.len)
        return false;
    const do_convert = cs == CaseSensitive.No;

    for (self.codepoints.items, slice) |l, r| {
        if (do_convert) {
            if (letter.toUpper(l) != letter.toUpper(r))
                return false;
        } else {
            if (l != r)
                return false;
        }
    }

    return true;
}

pub fn equalsStr(self: String, other: String, cs: CaseSensitive) bool {
    return self.equalsSlice(other.codepoints.items, cs);
}

pub fn findCodePointIndex(self: String, grapheme_index: usize) ?usize {
    var count: usize = 0;
    for (self.graphemes.items, 0..) |bit, cp_index| {
        if (bit == 1)
            count += 1;

        if (count == grapheme_index+1)
            return cp_index;
    }

    //out.print("{s}() found nothing!, current_gi={}, input_index={}\n", .{ @src().fn_name, current_gi, grapheme_index }) catch {};
    return null;
}

pub fn findManyLinear(self: String, needles: CodePointSlice, start: ?Index) ?Index {
    const cp_count = self.codepoints.items.len;
    if (needles.len > cp_count) {
        out.print("needles > cp_count\n", .{}) catch return null;
        return null;
    }

    const from = start orelse Index.strStart();
    var pos = from.cp;
    while (pos < cp_count) {
        const haystack = self.codepoints.items[pos..];
        const index = std.mem.indexOf(CodePoint, haystack, needles) orelse return null;
        //out.print("{s} index={}\n", .{@src().fn_name, index}) catch return null;
        pos += index;
        const is_at_haystack_end = (pos == (cp_count - 1));
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
        var found_abs = self.findOneSimd(first_needle, pos, depth) orelse {
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

pub fn findOneSimd(self: String, needle: CodePoint, from: usize, comptime vec_len: u16) ?usize {
    const haystack = self.codepoints.items[from..];
    const vector_needles: @Vector(vec_len, CodePoint) = @splat(needle);
    // {0, 1, 2, 3, 4, 5, 6, 7, ..vec_len-1?}
    const vec_indices = std.simd.iota(CodePoint, vec_len);
    // Code points greater than 0x10FFFF are invalid (Unicode standard)
    const nulls: @Vector(vec_len, CodePoint) = @splat(0x10FFFF + 1);
    var pos: usize = 0;

    while (pos < haystack.len) {
        if ((haystack.len - pos) < vec_len) {
            // fallback to a normal scan when our input (or what's left of
            // it is smaller than our vec_len)
            const ret = std.mem.indexOfScalarPos(CodePoint, haystack, pos, needle);
            const index = if (ret) |k| (k + from) else null;
            // out.print("{s} found={?}(from={}), fallback to normal scan\n",
            // .{@src().fn_name, index, from}) catch {};

            return index;
        }

        const h: @Vector(vec_len, CodePoint) = haystack[pos..][0..vec_len].*;
        const matches = h == vector_needles;

        if (@reduce(.Or, matches)) { // does it have any true value, if so,
            // we have a match, we just need to find its index
            const result = @select(CodePoint, matches, vec_indices, nulls);

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

pub fn findOneSimdFromEnd(self: String, needle: CodePoint, start: ?usize, comptime vector_len: ?u16) ?usize {
    const items = self.codepoints.items;
    const from = start orelse items.len;
    const haystack = items[0..from];
    const vec_len = vector_len orelse SimdVecLen;
    const vector_needles: @Vector(vec_len, CodePoint) = @splat(needle);
    // {0, 1, 2, 3, 4, 5, 6, 7, ..vec_len-1}
    const vec_indices = std.simd.iota(CodePoint, vec_len);
    // Code points greater than 0x10FFFF are invalid (Unicode standard)
    const nulls: @Vector(vec_len, CodePoint) = @splat(0x0); //0x10FFFF + 1);
    var pos: usize = haystack.len;

    while (pos > 0) {
        if (pos < vec_len) {
            const ret = std.mem.lastIndexOfScalar(CodePoint, haystack[0..pos], needle);
            return if (ret) |k| k else null;
        }

        const vector_loc = pos - vec_len;
        const h: @Vector(vec_len, CodePoint) = haystack[vector_loc..][0..vec_len].*;
        const matches = h == vector_needles;

        if (@reduce(.Or, matches)) {
            const data_vec = @select(CodePoint, matches, vec_indices, nulls);
            const index = @reduce(.Max, data_vec);
            return index + vector_loc;
        }

        pos -= vec_len;
    }

    return null;
}

/// format implements the `std.fmt` format interface for printing types.
pub fn format(self: String, comptime fmt: []const u8,
options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;
    const buf = self.toString() catch return;
    defer buf.deinit();
    _ = try writer.print("{s}", .{buf.items});
}

pub fn From(a: Allocator, input: []const u8) !String {
    var obj = String{};
    obj.a = a;
    obj.graphemes = ArrayList(u1).init(a);
    obj.codepoints = ArrayList(CodePoint).init(a);
    try obj.init(input, false);

    return obj;
}

/// This operation is O(n)
pub fn getGraphemeIndex(codepoint_pos: usize, slice: GraphemeSlice) ?usize {
    return countGraphemesSimd(slice[0..codepoint_pos+1]);
}

pub fn grIsAnyCp(self: String, index: Index, slice: CodePointSlice) bool {
    const items = self.codepoints.items;
    const graphemes = self.graphemes.items;
    for (slice) |cp| {
        if (items[index.cp] != cp or graphemes[index.cp] != 1) {
            continue;
        }

// Here we're just making sure this grapheme is 1 codepoint length
// to respect grapheme cluster boundaries.
        const at_end = index.cp == items.len - 1;
        if (at_end or graphemes[index.cp + 1] == 1)
            return true;
    }

    return false;
}

pub fn iterator(self: String, from_gr: ?usize) !Iterator {
    if (from_gr) |from| {
        const index = self.seek(from) orelse String.strStart();
        //  try out.print("String.iterator() index cp={}, gr={}, from={}\n",
        //  .{index.cp, index.gr, from});
        return Iterator {.s = self, .item = index};
    } else {
        return Iterator {.s = self };
    }
}

/// The type of `from_index` is `Index` object of wanted grapheme.
/// i.e. to get 3rd grapheme's index object in a string call str.seek(3);
pub fn indexOf(self: String, input: []const u8,
from_index: ?Index) ?Index {
    const needles = String.toCodePoints(self.a, input) catch return null;
    defer needles.deinit();
    const from = from_index orelse Index.strStart();
    if (self.codepoints.items.len >= SimdVecLen) {
        return self.findManySimd(needles.items, from, SimdVecLen);
    }

    return self.findManyLinear(needles.items, from);
}

pub fn indexOf2(self: String, needles: CodePointSlice,
from_index: ?Index) ?Index {
    const from = from_index orelse return null;
    if (self.codepoints.items.len >= SimdVecLen) {
        return self.findManySimd(needles, from, SimdVecLen);
    }
    return self.findManyLinear(needles, from);
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
        var found_index = self.findOneSimdFromEnd(first_needle, pos, vec_len) orelse {
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
pub fn insert(self: *String, at: ?Index, what: []const u8) !void {
    var input = try String.From(self.a, what);
    defer input.deinit();
    try self.insertStr(at, input);
}

pub fn insertStr(self: *String, at: ?Index, input: String) !void {
    const index = at orelse return;
    try self.codepoints.insertSlice(index.cp, input.codepoints.items);
    try self.graphemes.insertSlice(index.cp, input.graphemes.items);
    self.grapheme_count += input.grapheme_count;
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

pub fn printCodePoints(self: String) !void {
    try out.print("Codepoints:\n", .{});
    for (self.codepoints.items, 0..) |cp, i| {
        if (i > 255) {
            out.print("\n(... STRING TOO LONG TO PRINT ALL CODEPOINTS!)\n", .{}) catch break;
            break;
        }
        const is_grapheme = (self.graphemes.items[i] == 1);
        const br_open: u21 = if (is_grapheme) '[' else '(';
        const br_close: u21 = if (is_grapheme) ']' else ')';
        try out.print("{u}{}{u}'{u}'0x{X}  ", .{ br_open, i, br_close, cp, cp });
    }
    try out.print("\n", .{});
}

pub fn remove(self: *String, start_index: ?Index, gr_count_to_remove: usize) !void {
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

    try out.print("{s}() start.cp={},.gr={}, len_in_cp={}, till={}, gr_count_to_remove={}\n", .{ @src().fn_name, start.cp, start.gr, len_in_cp, till, gr_count_to_remove });

    var new_items: []const CodePoint = &[_]CodePoint{};
    try self.codepoints.replaceRange(start.cp, len_in_cp, new_items);

    const new_items_gr: []const u1 = &[_]u1{};
    try self.graphemes.replaceRange(start.cp, len_in_cp, new_items_gr);

    self.grapheme_count -= gr_so_far;
}

pub fn removeLowLevel(self: *String, from_cp: usize, cp_count: usize) !void {
    var new_cps: []const CodePoint = &[_]CodePoint{};
    try self.codepoints.replaceRange(from_cp, cp_count, new_cps);

    const new_grs: []const u1 = &[_]u1{};
    try self.graphemes.replaceRange(from_cp, cp_count, new_grs);
    
    self.grapheme_count -= cp_count;
}

pub fn replace(self: *String, start_index: ?Index, gr_count_to_remove: usize, replacement: []const u8) !void {
    try self.remove(start_index, gr_count_to_remove);
    try self.insert(start_index, replacement);
}

pub fn replaceStr(self: *String, start_index: ?Index, gr_count_to_remove: usize, replacement: String) !void {
    try self.remove(start_index, gr_count_to_remove);
    try self.insertStr(start_index, replacement);
}

pub fn reset(self: *String, str: []const u8) !void {
    try self.init(str, true);
}

/// Returns an `Index` object for grapheme at index `grapheme_index`
pub fn seek(self: String, grapheme_index: usize) ?Index {
    if (grapheme_index == 0)
        return Index{};
    const cp = self.findCodePointIndex(grapheme_index) orelse return null;
    return Index{ .cp = cp, .gr = grapheme_index };
}

pub fn startsWith(self: String, phrase: []const u8) !bool {
    const needles = try String.toCodePoints(self.a, phrase);
    defer needles.deinit();
    return self.startsWithSlice(needles.items);
}

pub fn startsWithSlice(self: String, needles: CodePointSlice) bool {
    if (!std.mem.startsWith(CodePoint, self.codepoints.items, needles)) {
        return false;
    }

    // make sure it ends on a grapheme boundary:
    const remaining = self.graphemes.items[(needles.len - 1)..];
    return remaining.len == 0 or remaining[0] == 1;
}

pub fn startsWithStr(self: String, needles: String) bool {
    return self.startsWithSlice(needles.codepoints.items);
}

/// returns `Index` after the last grapheme, exec is O(1)
pub fn strEnd(self: String) Index {
    return Index{ .cp = self.codepoints.items.len, .gr = self.grapheme_count };
}

pub fn strStart() Index {
    return Index {};
}

/// returns `Index` after the last grapheme minus `skip_graphemes`, exec is O(n)
pub fn fromEnd(self: String, skip_graphemes: ?usize) ?Index {
    if (skip_graphemes) |skip| {
        if (skip != 0)
            return self.seek(self.grapheme_count - skip);
    }
    return Index{ .cp = self.codepoints.items.len, .gr = self.grapheme_count };
}

pub fn toUpper(self: *String) void {
    toUpper3(self.codepoints.items);
}

pub fn toUpper2(self: String) ![]u8 {
    const buf = try self.toString();
    defer buf.deinit();
    return try zgl.toUpperStr(self.a, buf.items);
}

pub fn toUpper3(list: *CodePointSlice) void {
    for (list) |*v| {
        v.* = letter.toUpper(v.*);
    }
}

pub fn trim(self: *String) !void {
    try self.trimLeft();
    //const cp: CodePoint = ' ';// whitespace
    

}

pub fn trimLeft(self: *String) !void {
    const cp_to_remove = [_]CodePoint{' ', '\t', '\n', '\r'};
    const str = self.*;
    var from = Index.strStart();
    var found: usize = 0;
    while (from.next(str)) |index| {
        if (self.grIsAnyCp(index, &cp_to_remove)) {
            found += 1;
        } else {
            break;
        }
    }

    if (found > 0)
        try self.removeLowLevel(from.cp, found);
}

pub fn utf8_from_cp(a: Allocator, cp: CodePoint) !ArrayList(u8) {
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

pub fn toCodePoints(a: Allocator, input: []const u8) !ArrayList(CodePoint) {
    var buf = ArrayList(CodePoint).init(a);
    errdefer buf.deinit();
    var cp_iter = zgl.CodePointIterator{ .bytes = input };
    while (cp_iter.next()) |obj| {
        try buf.append(obj.code);
    }

    return buf;
}
