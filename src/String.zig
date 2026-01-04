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
const Graphemes = @import("Graphemes");
const LetterCasing = @import("LetterCasing");
const Normalize = @import("Normalize");
const CaseFolding = @import("CaseFolding");
const GeneralCategories = @import("GeneralCategories");

pub const Codepoint = u21;
pub const CpSlice = []Codepoint;
pub const ConstCpSlice = []const Codepoint;
pub const GraphemeSlice = []const u1;
pub const Error = error{ NotFound, BadArg, Index, Alloc, OutOfBounds, Other };
const SimdVecLen: u16 = 32;

pub const Find = struct {
    from: usize = 0,
    cs: CaseSensitive = CaseSensitive.Yes,
};

pub const From = enum(u8) {
    Left,
    Right,
};

pub const Args = struct {
    from: Index = Index.strStart(),
    cs: CaseSensitive = CaseSensitive.Yes,
    look_ahead: bool = true,

    pub fn From(self: Args, at: Index) Args {
        return Args{ .cs = self.cs, .from = at, .look_ahead = self.look_ahead };
    }
};

pub const RetainCapacity = enum(u8) {
    Yes,
    No,
};

pub const KeepEmptyParts = enum(u8) {
    Yes,
    No,
};

pub const CaseSensitive = enum(u8) {
    Yes,
    No,
};

pub const Theme = enum(u8) {
    Light,
    Dark,
};

const Clear = enum(u8) {
    Yes,
    No,
};

pub const Flush = enum(u8) {
    Yes,
    No,
};

const Attr = enum(u8) {
    Ignore,
    Codepoint,
    Grapheme,
};
const SeeAs = enum(u8) { CodepointOnly, PartOfGrapheme };

pub const Charset = enum(u8) {
    Ascii,
    Unicode,
};

pub const Grapheme = struct {
    len: u32 = 0,
    idx: Index,
    s: *const String,

    pub fn From(input: *const String, at: Index) ?Grapheme {
        const data = input.d orelse return null;
        if (at.cp >= data.codepoints_.items.len)
            return null;

        var g = Grapheme{
            .s = input,
            .idx = at,
        };

        for (data.graphemes_.items[at.cp..], 0..) |bit, i| {
            if (i == 0) {
                g.len += 1;
            } else {
                if (bit == 1)
                    break;
                g.len += 1;
            }
        }

        return g;
    }

    pub fn getSlice(self: *const Grapheme) ?CpSlice {
        const data = self.s.d orelse return null;
        return data.codepoints_.items[self.idx.cp..(self.idx.cp + self.len)];
    }

    pub fn getCodepoint(self: Grapheme) ?Codepoint {
        if (self.len != 1) {
            return null;
        }
        const sd = self.s.d orelse return null;
        return sd.codepoints_.items[self.idx.cp];
    }

    pub fn eq(self: Grapheme, rhs: Grapheme, cs: CaseSensitive) bool {
        const l = self.getSlice() orelse return false;
        const r = rhs.getSlice() orelse return false;
        if (cs == .Yes) {
            return std.mem.eql(Codepoint, l, r);
        }

        for (l, r) |a, b| {
            if (toLowerCp(a) != toLowerCp(b)) {
                return false;
            }
        }

        return true;
    }

    pub fn eqAscii(self: Grapheme, input: []const u8) bool {
        if (input.len != 1) {
            return false;
        }

        return self.eqCp(input[0]);
    }

    pub fn eqUtf8(self: Grapheme, input: []const u8) bool {
        if (input.len == 1) {
            const cp = toCp(input) catch return false;
            return self.eqCp(cp);
        } else {
            var buf = toCodepoints(ctx.a, input) catch return false;
            defer buf.deinit(ctx.a);
            return self.eqSlice(buf.items);
        }
    }

    pub fn eqCp(self: Grapheme, cp: Codepoint) bool {
        const str_slice = self.getSlice() orelse return false;
        return (str_slice.len == 1) and (str_slice[0] == cp);
    }

    pub fn eqSlice(self: Grapheme, input: ConstCpSlice) bool {
        const str_slice = self.getSlice() orelse return (input.len == 0);
        if (input.len != str_slice.len)
            return false;

        for (input, str_slice) |a, b| {
            if (a != b)
                return false;
        }

        return true;
    }

    pub fn format(self: *const Grapheme, writer: *std.Io.Writer) !void {
        const str_slice = self.getSlice() orelse return;
        var utf8 = String.utf8_from_slice(ctx.a, str_slice) catch return;
        defer utf8.deinit(ctx.a);
        // _ = try writer.print("{s}", .{utf8.items});
        try printBytes(utf8, writer, 0);
    }

    fn isAsciiAWordChar(cp: Codepoint) bool {
        return (cp >= 'A' and cp <= 'Z') or (cp >= 'a' and cp <= 'z') or
            (cp >= '0' and cp <= '9') or (cp == '_');
    }

    pub fn isWordChar(self: Grapheme, charset: Charset) bool {
        const cp = self.getCodepoint() orelse return false;
        const ascii_match = isAsciiAWordChar(cp);

        if (charset == .Ascii) {
            return ascii_match;
        }

        return ascii_match or ctx.gencat.isLetter(cp);
    }

    pub fn isNumber(self: Grapheme) bool {
        const cp = self.getCodepoint() orelse return false;
        return cp >= '0' and cp <= '9';
    }

    pub fn isWhitespace(self: Grapheme) bool {
        const cp = self.getCodepoint() orelse return false;

        return cp == ' ' or cp == '\t' or cp == '\n' or cp == '\r';
    }

    pub fn slice(self: Grapheme) Slice {
        const end = Index{ .cp = self.idx.cp + self.len, .gr = self.idx.gr + 1 };
        return self.s.slice(self.idx, end);
    }

    pub fn toOwned(self: Grapheme) !ArrayList(Codepoint) {
        var a = ArrayList(Codepoint).init(ctx.a);
        const sd = self.s.d orelse return a;
        const str_slice = sd.codepoints_.items[0..];
        for (0..self.len) |k| {
            try a.append(str_slice[k]);
        }

        return a;
    }

    pub fn toString(self: Grapheme) !String {
        var s = String{};
        try s.addGrapheme(self);
        return s;
    }

    pub fn within(self: Grapheme, range: GraphemeRange, cs: CaseSensitive) bool {
        var cp = self.getCodepoint() orelse return false;
        if (cs == .Yes) {
            const result = cp >= range.a and cp <= range.b;
            return result;
        }

        cp = String.toLowerCp(cp);
        const a1 = String.toLowerCp(range.a);
        const b1 = String.toLowerCp(range.b);

        return cp >= a1 and cp <= b1;
    }
};

pub const GraphemeRange = struct {
    a: Codepoint,
    b: Codepoint,

    pub fn New(a: Codepoint, b: Codepoint) GraphemeRange {
        return .{ .a = a, .b = b };
    }

    pub fn format(self: GraphemeRange, writer: *std.Io.Writer) !void {
        try writer.print("Range{{{}-{}}}", .{ self.a, self.b });
    }
};

pub const Direction = enum(u8) { Forward, Back };

pub fn Iterator(comptime T: type) type {
    return struct {
        const Self = @This();
        items: []T,
        at: usize = 0,
        first_time: bool = true,

        pub fn New(a: []T) Self {
            return Iterator(T){
                .items = a,
            };
        }

        pub fn add(self: *Self, n: usize) void {
            self.at += n;
        }

        pub fn continueFrom(self: *Self, idx: usize) void {
            self.at = idx;
            self.first_time = true;
        }

        pub fn current(self: Self) ?T {
            if (self.at >= self.size())
                return null;
            return self.items[self.at];
        }

        pub fn go(self: *Self, dir: Direction) ?*T {
            return if (dir == .Back) self.prevPtr() else self.nextPtr();
        }

        pub fn hasMore(self: *const Self, dir: Direction) bool {
            return if (dir == .Forward) self.at + 1 < self.items.len else self.at > 0;
        }

        inline fn nextIdx(self: *Self) ?usize {
            if (self.first_time) {
                self.first_time = false;
                return if (self.at >= self.size()) null else self.at;
            } else {
                if (self.at + 1 >= self.size()) {
                    return null;
                }
                self.at += 1;
                return self.at;
            }
        }

        pub fn nextPtr(self: *Self) ?*T {
            if (self.nextIdx()) |idx| {
                return &self.items[idx];
            }

            return null;
        }

        pub fn next(self: *Self) ?T {
            if (self.nextIdx()) |idx| {
                return self.items[idx];
            }

            return null;
        }

        pub fn peekFirst(self: *Self) ?*T {
            return if (self.items.len == 0) null else &self.items[0];
        }

        pub fn peekLast(self: *Self) ?*T {
            return if (self.items.len == 0) null else &self.items[self.items.len - 1];
        }

        pub fn peekNext(self: Self) ?*T {
            const at = self.at + 1;
            return if (at >= self.items.len) null else &self.items[at];
        }

        pub fn peekPrev(self: Self) ?*T {
            if (self.at == 0 or (self.at - 1) >= self.size()) {
                return null;
            }

            return &self.items[self.at - 1];
        }

        inline fn prevIdx(self: *Self) ?usize {
            if (self.first_time) {
                self.first_time = false;
                return self.at;
            } else {
                if (self.at == 0)
                    return null;
                self.at -= 1;
                return self.at;
            }
        }

        pub fn prevPtr(self: *Self) ?*T {
            // const was_at = self.at;
            // const was_ft = self.first_time;
            const idx = self.prevIdx();
            // mtl.debug(@src(), "was_at:{}, is_at:{?}, was_first_time:{}, is_first_time:{}", .{was_at, idx, was_ft, self.first_time});

            if (idx) |pos| {
                return &self.items[pos];
            }

            return null;
        }

        pub fn prev(self: *Self) ?T {
            if (self.prevIdx()) |idx| {
                return self.items[idx];
            }

            return null;
        }

        inline fn size(self: Self) usize {
            return self.items.len;
        }

        pub fn toStart(self: *Self) void {
            self.at = 0;
            self.first_time = true;
        }

        pub fn toEnd(self: *Self) void {
            self.at = if (self.size() == 0) 0 else self.size() - 1;
            self.first_time = true;
        }
    };
}

pub const StringIterator = struct {
    first_time: bool = true,
    position: Index,
    str: *const String,
    start_cp: ?usize = null,
    end_cp: ?usize = null,

    pub fn New(str: *const String, from: ?Index) StringIterator {
        const idx = if (from) |i| i else Index.strStart();
        return StringIterator{ .str = str, .position = idx };
    }

    pub fn NewFromSlice(s: Slice, from: ?Index) StringIterator {
        const idx = if (from) |i| i else s.start;
        return StringIterator{ .str = s.str, .position = idx, .start_cp = s.start.cp, .end_cp = s.end.cp };
    }

    pub fn continueFrom(self: *StringIterator, idx: Index) void {
        self.position = idx;
        self.first_time = true;
    }

    pub fn go(self: *StringIterator, dir: Direction) ?Grapheme {
        return if (dir == .Forward) self.next() else self.prev();
    }

    pub fn nextIndex(self: *StringIterator) ?Index {
        if (self.first_time) {
            self.first_time = false;
            return self.position;
        }

        const data = self.str.d orelse return null;
        if (self.position.next(data.codepoints_.items[0..], data.graphemes_.items[0..], self.end_cp)) {
            return self.position;
        }

        return null;
    }

    pub fn next(self: *StringIterator) ?Grapheme {
        const index = self.nextIndex() orelse return null;
        return self.str.charAtIndex(index);
    }

    pub fn nextFrom(self: *StringIterator, idx: Index) ?Grapheme {
        self.first_time = false;
        self.position = idx;
        return self.next();
    }

    pub fn prev(self: *StringIterator) ?Grapheme {
        const index = self.prevIndex() orelse return null;
        return self.str.charAtIndex(index);
    }

    pub fn prevIndex(self: *StringIterator) ?Index {
        if (self.first_time) {
            self.first_time = false;
            return self.position;
        }

        const data = self.str.d orelse return null;
        if (self.position.prev(data.codepoints_.items, data.graphemes_.items[0..], self.start_cp)) {
            return self.position;
        }

        return null;
    }

    pub fn prevFrom(self: *StringIterator, idx: Index) ?Grapheme {
        self.first_time = false;
        self.position = idx;
        return self.prev();
    }

    pub fn stepBack(self: *StringIterator) void {
        _ = self.prevIndex();
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

    pub fn addString(self: *Index, input: String) void {
        self.gr += input.size();
        self.cp += input.size_cp();
    }

    pub fn addRaw(self: Index, how_much: usize) Index {
        return Index{ .cp = self.cp + how_much, .gr = self.gr + how_much };
    }

    pub fn atZero(self: Index) bool {
        return self.cp == 0 and self.gr == 0;
    }

    pub fn clone(self: Index) Index {
        return Index{ .cp = self.cp, .gr = self.gr };
    }

    pub fn eq(self: Index, rhs: ?Index) bool {
        if (rhs) |b| {
            return self.cp == b.cp and self.gr == b.gr;
        }

        return false;
    }

    pub fn eqCpGr(self: Index, cp: usize, gr: usize) bool {
        return self.cp == cp and self.gr == gr;
    }

    pub fn format(self: *const Index, writer: *std.Io.Writer) !void {
        _ = try writer.print("{{{}:{}}}", .{ self.cp, self.gr });
    }

    pub fn goLeftBy(self: *Index, gr: Grapheme) void {
        self.cp -= gr.len;
        self.gr -= 1;
    }

    pub fn goRightBy(self: *Index, gr: Grapheme) void {
        self.cp += gr.len;
        self.gr += 1;
    }

    pub fn isPast(self: Index, s: *const String) bool {
        const d = s.d orelse return false;
        return self.gr >= d.grapheme_count;
    }

    pub fn isPastSlice(self: Index, s: Slice) bool {
        return self.gr >= s.end.gr;
    }

    // go back by this grapheme
    pub fn minusGrapheme(self: *const Index, g: Grapheme) Index {
        return .{ .cp = self.cp - g.len, .gr = self.gr - 1 };
    }

    fn next(self: *Index, codepoints: ConstCpSlice, graphemes: GraphemeSlice, limit: ?usize) bool {
        if (self.cp >= codepoints.len) {
            return false;
        }

        const saved_cp = self.cp;
        self.cp += 1;
        for (graphemes[(self.cp)..], 0..) |gr_bit, i| {
            if (gr_bit == 1) {
                self.cp += i;
                if (limit) |lim| {
                    if (self.cp >= lim) {
                        self.cp = saved_cp;
                        return false;
                    }
                }

                self.gr += 1;
                return true;
            }
        }

        self.cp = saved_cp;

        return false;
    }

    pub fn nextIndex(self: *const Index, s: *const String) ?Index {
        var mut_idx: Index = self.*;
        const data = s.d orelse return null;
        if (mut_idx.next(data.codepoints_.items[0..], data.graphemes_.items[0..], null)) {
            return mut_idx;
        }

        return null;
    }

    // advance past this grapheme
    pub fn plusGrapheme(self: *const Index, g: Grapheme) Index {
        return .{ .cp = self.cp + g.len, .gr = self.gr + 1 };
    }

    pub fn plus(self: Index, input: Index) Index {
        return Index{ .cp = self.cp + input.cp, .gr = self.gr + input.gr };
    }

    pub fn plusN(self: Index, n: usize) Index {
        // usable and fast when dealing with ASCII
        return Index{ .cp = self.cp + n, .gr = self.gr + n };
    }

    pub fn plusStr(self: Index, input: String) Index {
        const d = input.d orelse return self;
        return Index {.cp = self.cp + d.codepoints_.items.len, .gr = self.gr + d.grapheme_count };
    }

    fn prev(self: *Index, codepoints: ConstCpSlice, graphemes: GraphemeSlice, limit: ?usize) bool {
        if (self.cp == 0 or self.cp > codepoints.len)
            return false;

        var i: isize = @intCast(self.cp);
        i -= 1;
        while (i >= 0) : (i -= 1) {
            const b = graphemes[@intCast(i)];
            if (b == 1) {
                if (limit) |lim| {
                    const ilim: isize = @intCast(lim);
                    if (i < ilim) {
                        return false;
                    }
                }
                self.cp = @intCast(i);
                self.gr -= 1;
                return true;
            }
        }

        return false;
    }

    fn prevIndex(self: *Index, s: *const String) ?Index {
        const data = s.d orelse return null;
        var mut_idx: Index = self.*;
        if (mut_idx.prev(data.codepoints_.items, data.graphemes_.items[0..], null)) {
            return mut_idx;
        }

        return null;
    }

    pub fn subtract(self: *Index, by: Index) void {
        self.cp -= by.cp;
        self.gr -= by.gr;
    }

    pub fn strStart() Index {
        return Index{};
    }

    pub fn N(n: usize) Index {
        return .{.cp = n, .gr = n};
    }
};

pub fn printBytes(buf: ArrayList(u8), writer: *std.Io.Writer, context: i32) !void {
    const fmtstr = "{s}{s}{s}{s}{s}";

    if (context == 1) { // colored
        try writer.print(fmtstr, .{ mtl.COLOR_YELLOW, mtl.BGCOLOR_BLACK, buf.items, mtl.BGCOLOR_DEFAULT, mtl.COLOR_DEFAULT });
    } else if (context == 2) { // highlighted
        try writer.print(fmtstr, .{ mtl.COLOR_BLACK, mtl.BGCOLOR_YELLOW, buf.items, mtl.BGCOLOR_DEFAULT, mtl.COLOR_DEFAULT });
    } else { // no color, default
        try writer.print("{s}", .{buf.items});
    }
}

pub const Slice = struct {
    // `start` and `end` contain absolute positions, that is relative to
    // the `str` the `Slice` points to.
    // The exception is that, for convenience, the default argument for
    // `Index` in `Slice` function params is interpreted as the start of
    // the `Slice`, whereas in `String` as the start of the `String`.

    start: Index = .{},
    end: Index = .{},
    str: *const String,

    pub fn format(self: Slice, writer: *std.Io.Writer) !void {
        return self._(0).format(writer);
    }

    pub fn _(self: *const Slice, context: i32) Slice_ {
        return .{ .slice = self, .context = context };
    }

    const Slice_ = struct {
        context: i32,
        slice: *const Slice,
        pub fn format(self: Slice_, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            var buf = self.slice.toUtf8(ctx.a) catch return;
            defer buf.deinit(ctx.a);
            try printBytes(buf, writer, self.context);
        }
    };

    pub fn afterLast(self: Slice) Index { // returns index past last grapheme
        return self.end;
    }

    pub fn beforeLast(self: Slice) Index {
        // returns index before last grapheme
        const data = self.str.d orelse return .{};
        var i: usize = self.size_cp();
        if (i == 0) {
            return .{};
        }

        const gr_slice = self.graphemes(data);
        while (i > 0) {
            i -= 1;
            if (gr_slice[i] == 1) {
                break;
            }
        }

        return Index{ .cp = self.start.cp + i, .gr = self.end.gr - 1 };
    }

    pub fn charAt(self: Slice, at: usize) ?Grapheme {
        const index = self.findIndex(at) orelse return null;
        const g = self.charAtIndex(index);
        return g;
    }

    pub fn charAtIndex(self: Slice, at: Index) ?Grapheme {
        return Grapheme.From(self.str, at);
    }

    pub fn charAtIndexOneCp(self: *const Slice, at: Index) ?Codepoint {
        // Sometimes it only makes sense to operate with one codepoint graphemes,
        // like with interpreting ranges, like A-Z, or 0-9. This method makes sure
        // the grapheme at index `at` is one codepoint, and if so returns this codepoint.
        var from = at;
        if (at.cp == 0 and self.start.cp != 0) {
            from = self.start;
        }
        const data = self.str.d orelse return null;
        return charAtIndexOneCp_real(data.codepoints(), data.graphemes(), from);
    }

    inline fn codepoints(self: *const Slice, data: Data) ConstCpSlice {
        return data.codepoints_.items[self.start.cp..self.end.cp];
    }

    pub fn endsWith(self: Slice, rhs: Slice) ?Index {
        // Returns the start of the position from where they match, otherwise null.
        // This is more useful than just returning a bool because you don't have to
        // recompute the Index at this position if you need it.
        if (self.size() < rhs.size()) {
            return null;
        }

        var self_iter = self.iteratorFromEnd();
        var rhs_iter = rhs.iteratorFromEnd();
        while (rhs_iter.prev()) |gr| {
            const self_gr = self_iter.prev() orelse return null;
            if (!self_gr.eq(gr, .Yes)) {
                return null;
            }
        }

        return self_iter.position;
    }

    pub fn eq(self: Slice, other: String) bool {
        return self.equals(other, .{});
    }

    pub fn equals(self: Slice, other: String, cmp: Comparison) bool {
        const other_data = other.d orelse return false;
        return self.equalsCpSlice(other_data.codepoints_.items, cmp);
    }

    pub fn equalsAscii(self: Slice, input: []const u8, cmp: Comparison) bool {
        var buf = toCodepointsFromAscii(ctx.a, input) catch return false;
        defer buf.deinit(ctx.a);
        return self.equalsCpSlice(buf.items, cmp);
    }

    pub fn equalsCpSlice(self: Slice, cp_slice: CpSlice, cmp: Comparison) bool {
        const my_cp_slice = self.getCpSlice() orelse return (cp_slice.len == 0);
        return equalsCodepointSlice_real(my_cp_slice, cp_slice, cmp);
    }

    pub fn equalsSlice(self: Slice, input: Slice, cmp: Comparison) bool {
        const cps = self.getCpSlice() orelse return false;
        const input_cps = input.getCpSlice() orelse return false;
        return equalsCodepointSlice_real(cps, input_cps, cmp);
    }

    pub fn equalsUtf8(self: Slice, input: []const u8, cmp: Comparison) bool {
        var buf = toCodepoints(ctx.a, input) catch return false;
        defer buf.deinit(ctx.a);
        return self.equalsCpSlice(buf.items, cmp);
    }

    pub fn findIndex(self: Slice, grapheme_index: usize) ?Index {
        // `grapheme_index` is relative to slice
        // but returned `Index` contains the absolute position.
        const data = self.str.d orelse return null;
        if (grapheme_index >= self.size()) {
            return if (grapheme_index == self.size()) self.afterLast() else null;
        }

        const idx = findIndex_real(self.graphemes(data), grapheme_index) orelse return null;
        return self.start.plus(idx);
    }

    pub fn findIndexFromEnd(self: Slice, count: usize) ?Index {
        var iter = StringIterator.New(self.str, self.afterLast());
        var ret_index: ?Index = null;
        for (0..count) |i| {
            _ = i;
            ret_index = iter.prevIndex() orelse return null;
        }

        return ret_index;
    }

    fn getCpSlice(self: Slice) ?ConstCpSlice {
        const data = self.str.d orelse return null;
        return self.codepoints(data);
    }

    inline fn graphemes(self: Slice, data: Data) GraphemeSlice {
        return data.graphemes_.items[self.start.cp..self.end.cp];
    }

    pub fn indexOf(self: Slice, input: String, args: Args) ?Index {
        return self.indexOfSlice(input.asSlice(), args);
    }

    pub fn indexOfAscii(self: Slice, input: []const u8, args: Args) ?Index {
        var needles = String.New(input) catch return null;
        defer needles.deinit();
        return self.indexOfSlice(needles.asSlice(), args);
    }

    pub fn indexOfSlice(self: Slice, input: Slice, args: Args) ?Index {
        const data = self.str.d orelse return null;
        const input_codepoints = input.getCpSlice() orelse return null;
        var a = args;
        if (a.from.cp == 0 and self.start.cp != 0) {
            a.from = self.start;
        }

        a.from.subtract(self.start);
        const idx = indexOfCpSlice_real(self.codepoints(data), self.graphemes(data), input_codepoints, a) orelse return null;

        return idx.plus(self.start);
    }

    pub fn indexOfUtf8(self: Slice, input: []const u8, args: Args) ?Index {
        const data = self.str.d orelse return null;
        var a = args;
        if (a.from.cp == 0 and self.start.cp != 0) {
            a.from = self.start;
        }

        return indexOfUtf8_real(data.codepoints(), data.graphemes(), input, a);
    }

    pub fn isDigit(self: Slice, at: Index) bool {
        return self.str.isDigit(at);
    }

    pub fn isEmpty(self: Slice) bool {
        return self.start.gr == self.end.gr;
    }

    pub fn isWhitespace(self: Slice, at: Index) bool {
        return self.str.isWhitespace(at);
    }

    pub fn isWordBoundary(self: Slice, at: Index, charset: Charset) bool {
        return self.str.isWordBoundary(at, charset);
    }

    pub fn isWordChar(self: Slice, at: Index, charset: Charset) bool {
        return self.str.isWordChar(at, charset);
    }

    pub fn iterator(self: Slice) StringIterator {
        return StringIterator.NewFromSlice(self, null);
    }

    pub fn iteratorFrom(self: Slice, from: Index) StringIterator {
        return StringIterator.NewFromSlice(self, from);
    }

    pub fn iteratorFromEnd(self: Slice) StringIterator {
        return self.iteratorFrom(self.beforeLast());
    }

    pub fn lastChar(self: Slice) ?Grapheme {
        const idx = self.beforeLast();
        return self.charAtIndex(idx);
    }

    fn lastIndexGeneric(self: Slice, comptime T: type, needles: []const T, args: Args) ?Index {
        const data = self.str.d orelse return null;
        const idx = lastIndexGeneric_real(self.codepoints(data), self.graphemes(data), self.size(), T, needles, args) orelse return null;
        return self.start.plus(idx);
    }

    pub fn lastIndexOf(self: Slice, needles_str: String, args: Args) ?Index {
        const ndata = needles_str.d orelse return null;
        const needles = ndata.codepoints_.items[0..];
        return self.lastIndexGeneric(Codepoint, needles, args);
    }

    pub fn lastIndexOfAscii(self: *const Slice, needles: []const u8, args: Args) ?Index {
        return self.lastIndexGeneric(u8, needles, args);
    }

    pub fn lastIndexOfCp(self: Slice, needle: Codepoint, args: Args) ?Index {
        const data = self.str.d orelse return null;
        const idx = lastIndexOfCp_real(self.codepoints(data), self.graphemes(data), self.size(), needle, args) orelse return null;

        return self.start.plus(idx);
    }

    pub fn lastIndexOfUtf8(self: Slice, needles: []const u8, args: Args) ?Index {
        if (needles.len == 1) {
            return self.lastIndexOfCp(needles[0], args);
        }

        const s = String.New(needles) catch return null;
        defer s.deinit();
        return self.lastIndexOf(s, args);
    }

    pub fn leftSlice(self: Slice, from: Index) Slice {
        return Slice{ .str = self.str, .start = .{}, .end = from };
    }

    pub fn matches(self: Slice, input: String, args: Args) ?Index {
        return self.matchesSlice(input.asSlice(), args);
    }

    pub fn matchesAscii(self: Slice, input: []const u8, args: Args) ?Index {
        var a = args;
        if (a.from.cp == 0 and self.start.cp != 0) {
            a.from = self.start;
        }

        // mtl.debug(@src(), "ARGS: {}", .{a});
        const data = self.str.d orelse return null;
        return matchesAscii_real(data.codepoints(), data.graphemes(), input, a);
    }

    pub fn matchesSlice(self: Slice, input: Slice, args: Args) ?Index {
        var a = args;
        if (a.from.cp == 0 and self.start.cp != 0) {
            a.from = self.start;
        }

        const data = self.str.d orelse return null;
        return matches_real(data.codepoints(), data.graphemes(), input, a);
    }

    pub fn matchesUtf8(self: Slice, input: []const u8, args: Args) ?Index {
        const s = String.New(input) catch return null;
        defer s.deinit();
        return self.matches(s, args);
    }

    pub fn mid(self: Slice, from: Index) Slice {
        return Slice{ .str = self.str, .start = from, .end = self.afterLast() };
    }

    pub fn next(self: Slice, idx: Index) ?Grapheme {
        const next_idx = self.nextIndex(idx) orelse return null;
        return self.charAtIndex(next_idx);
    }

    pub fn nextIndex(self: Slice, idx: Index) ?Index {
        const data = self.str.d orelse return null;
        var mut_idx: Index = idx;
        if (!mut_idx.next(data.codepoints(), data.graphemes(), null)) {
            return null;
        }

        return mut_idx;
    }

    pub fn offset(self: Slice, by: usize) Index {
        return Index {.cp = self.cp + by, .gr = self.gr + by};
    }

    pub fn prev(self: *const Slice, idx: Index) ?Grapheme {
        const prev_idx = self.prevIndex(idx) orelse return null;
        return self.charAtIndex(prev_idx);
    }

    pub fn prevIndex(self: Slice, idx: Index) ?Index {
        const data = self.str.d orelse return null;
        var mut_idx: Index = idx;
        if (!mut_idx.prev(data.codepoints(), data.graphemes(), null)) {
            return null;
        }

        return mut_idx;
    }

    pub fn printCodepoints(self: Slice, src: std.builtin.SourceLocation) !void {
        const data = self.str.d orelse return;
        try printCodepoints_real(self.codepoints(data), self.graphemes(data), src, self.start);
    }

    pub fn printGraphemes(self: Slice, src: std.builtin.SourceLocation) !void {
        const data = self.str.d orelse return;
        try printGraphemes_real(self.codepoints(data), self.graphemes(data), src, self.start);
    }

    pub fn shrinkRaw(self: *Slice, by: usize, from: From) void {
        if (from == .Left) {
            self.start.cp += by;
            self.start.gr += by;
        } else {
            self.end.cp -= by;
            self.end.gr -= by;
        }
    }

    pub fn size(self: Slice) usize {
        // returns the number of graphemes
        return self.end.gr - self.start.gr;
    }

    pub fn size_cp(self: Slice) usize {
        // return the number of codepoints
        return self.end.cp - self.start.cp;
    }

    pub fn slice(self: Slice, start: Index, end: Index) Slice {
        return Slice{
            .str = self.str,
            .start = if (start.atZero()) self.start else start,
            .end = if (end.atZero()) self.end else end,
        };
    }

    pub fn splitPairAscii(self: Slice, sep: []const u8) ![2]Slice {
        if (self.indexOfAscii(sep, .{})) |idx| {
            return self.splitPairAt(idx, Index.N(sep.len));
        }

        return error.Other;
    }

    pub fn splitPairAt(self: Slice, at: Index, advance: ?Index) ![2]Slice {
        // Example: "one\ntwo" will be split into "one" and "two" without the "\n".
        const slice1: Slice = self.slice(.{}, at);
        const adv = if (advance) |a| a else Index.N(1);
        const idx2 = at.plus(adv);
        const slice2 = self.slice(idx2, self.afterLast());
        return .{slice1, slice2};
    }

    pub fn startsWithAscii(self: Slice, needles: []const u8, cmp: Comparison) bool {
        return self.matchesAscii(needles, .{.cs = cmp.cs}) != null;
    }

    pub fn toString(self: Slice) !String {
        return self.str.betweenIndices(self.start, self.end);
    }

    pub fn toUtf8(self: Slice, a: Allocator) !ArrayList(u8) {
        const ret: ArrayList(u8) = .empty;
        const data = self.str.d orelse return ret;
        return utf8_from_slice(a, self.codepoints(data));
    }

    pub fn trim(self: *Slice) void {
        self.trimLeft();
        self.trimRight();
        // return s2;
    }

    pub fn trimLeft(self: *Slice) void {
        const data = self.str.d orelse return;// self;
        const cps = self.codepoints(data);
        if (cps.len == 0) {
            return;// self;
        }

        var remove_count: usize = 0;
        for (0..cps.len) |i| {
            if (!data.isOneCodepointGrapheme(self.start.cp + i))
                break;
            const cp = cps[i];
            if (std.mem.indexOfScalar(u21, &CodepointsToTrim, cp)) |index| {
                _ = index;
                remove_count += 1;
            } else {
                break;
            }
        }

        if (remove_count > 0) {
            const cp = self.start.cp + remove_count;
            const gr = self.start.gr + remove_count;
            const start: Index = .{.cp=cp, .gr=gr};
            self.start = start;
            // return .{.str = self.str, .start = start, .end = self.end};
        }

        // return self;
    }

    pub fn trimRight(self: *Slice) void {
        const data = self.str.d orelse return;// self;
        const cps = self.codepoints(data);
        const cp_count = cps.len;
        if (cp_count == 0) {
            return;// self;
        }

        const grs = self.graphemes(data);
        var remove_count: usize = 0;
        for (1..cp_count) |i| {
            const ri = (cp_count - i);
            if (grs[ri] == 0)
                break;
            
            const cp = cps[ri];
            if (std.mem.indexOfScalar(u21, &CodepointsToTrim, cp)) |index| {
                _ = index;
                remove_count += 1;
            } else {
                break;
            }
        }

        if (remove_count > 0) {
            const cp = self.end.cp - remove_count;
            const gr = self.end.gr - remove_count;
            const end: Index = .{.cp=cp, .gr=gr};
            self.end = end;
            // return .{.str = self.str, .start = self.start, .end = end};
        }

        // return self;
    }
};

const TimeExt = "mc";
inline fn getTime() i128 {
    return std.time.microTimestamp();
}

pub const Context = struct {
    a: Allocator = undefined,
    graphemes: Graphemes,
    letter_casing: LetterCasing = undefined,
    case_folding: CaseFolding = undefined,
    normalize: Normalize = undefined,
    gencat: GeneralCategories = undefined,

    pub fn New(alloc: Allocator) !Context {
        const normalize = try Normalize.init(alloc);
        var context = Context{
            .a = alloc,
            .graphemes = try Graphemes.init(alloc),
            .letter_casing = try LetterCasing.init(alloc),
            .normalize = normalize,
            .case_folding = try CaseFolding.initWithNormalize(alloc, normalize),
            .gencat = try GeneralCategories.init(alloc),
        };

        _ = &context;

        return context;
    }

    pub fn deinit(self: *Context) void {
        self.graphemes.deinit(self.a);
        self.letter_casing.deinit(ctx.a);
        self.case_folding.deinit(ctx.a);
        self.normalize.deinit(ctx.a);
        self.gencat.deinit(ctx.a);
    }
};

pub threadlocal var ctx: Context = undefined;

const Data = struct {
    codepoints_: ArrayList(Codepoint) = undefined,
    graphemes_: ArrayList(u1) = undefined,
    grapheme_count: usize = 0,

    pub fn Clone(self: Data) !Data {
        return Data{
            .codepoints_ = try self.codepoints_.clone(ctx.a),
            .graphemes_ = try self.graphemes_.clone(ctx.a),
            .grapheme_count = self.grapheme_count,
        };
    }

    pub fn CloneFrom(self: Data, from_index: Index) !Data {
        var d = Data{};
        d.codepoints_ = .empty;
        d.graphemes_ = .empty;
        d.grapheme_count = self.grapheme_count - from_index.gr;

        try d.codepoints_.appendSlice(ctx.a, self.codepoints_.items[from_index.cp..]);
        try d.graphemes_.appendSlice(ctx.a, self.graphemes_.items[from_index.cp..]);

        return d;
    }

    pub fn codepoints(self: *const Data) ConstCpSlice {
        return self.codepoints_.items[0..];
    }

    pub fn graphemes(self: *const Data) GraphemeSlice {
        return self.graphemes_.items[0..];
    }

    inline fn isOneCodepointGrapheme(self: Data, i: usize) bool {
        if (self.graphemes_.items[i] != 1)
            return false;

        // is the grapheme one codepoint or larger?
        if ((i + 1) < self.codepoints_.items.len) {
            return (self.graphemes_.items[i + 1] == 1);
        }

        return true;
    }

    inline fn startOfGrapheme(self: Data, i: usize) bool {
        return self.graphemes_.items[i] == 1;
    }
};

d: ?Data = null,

pub fn Empty() String {
    return String{};
}

pub fn New(input: []const u8) !String {
    var s = String{};
    _ = s.initEmpty();
    try s.init(input, Clear.No);
    return s;
}

fn FromCpGr(codepoints: ConstCpSlice, graphemes: GraphemeSlice) !String {
    var s = String{};
    _ = s.initEmpty();
    var data = s.dataMut();
    try data.codepoints_.appendSlice(ctx.a, codepoints);
    try data.graphemes_.appendSlice(ctx.a, graphemes);
    data.grapheme_count = countGraphemes(graphemes);

    return s;
}

pub fn NewAscii(input: []const u8) !String {
    var s = String{};
    try s.addAscii(input);
    return s;
}

pub fn Init(a: Allocator) !void {
    String.ctx = try Context.New(a);
}

pub fn Deinit() void {
    String.ctx.deinit();
}

pub fn deinit(self: String) void {
    var sd = self.d orelse return;
    sd.codepoints_.deinit(ctx.a);
    sd.graphemes_.deinit(ctx.a);
}

pub fn add(self: *String, other: String) !void {
    const from_ptr = other.d orelse return;
    var data = self.dataMut();
    try data.codepoints_.appendSlice(ctx.a, from_ptr.codepoints_.items);
    try data.graphemes_.appendSlice(ctx.a, from_ptr.graphemes_.items);
    data.grapheme_count += from_ptr.grapheme_count;
}

pub fn addAscii(self: *String, letters: []const u8) !void {
    var data = self.dataMut();
    var new_codepoints = try data.codepoints_.addManyAsSlice(ctx.a, letters.len);

    for (letters, 0..) |letter, i| {
        new_codepoints[i] = letter;
    }

    try data.graphemes_.appendNTimes(ctx.a, 1, letters.len);
    data.grapheme_count += letters.len;
}

pub fn insertAscii(self: *String, at: Index, letters: []const u8) !void {
    var data = self.dataMut();
    const new_codepoints = try data.codepoints_.addManyAt(ctx.a, at.cp, letters.len);
    for (letters, new_codepoints) |letter, *cp| {
        cp.* = letter;
    }

    const new_graphemes = try data.graphemes_.addManyAt(ctx.a, at.cp, letters.len);
    for (new_graphemes) |*g| {
        g.* = 1;
    }

    data.grapheme_count += letters.len;
}

pub fn addChar(self: *String, cp: Codepoint) !void {
    var data = self.dataMut();
    try data.codepoints_.append(ctx.a, cp);
    try data.graphemes_.append(ctx.a, 1);
    data.grapheme_count += 1;
}

pub fn addConsume(self: *String, other: String) !void {
    defer other.deinit();
    try self.add(other);
}

pub fn addGrapheme(self: *String, gr: Grapheme) !void {
    const gr_slice = gr.getSlice() orelse return String.Error.Other;
    var data = self.dataMut();
    data.grapheme_count += 1;
    for (gr_slice, 0..) |cp, i| {
        try data.codepoints_.append(ctx.a, cp);
        try data.graphemes_.append(ctx.a, if (i == 0) 1 else 0);
    }
}

pub fn addSlice(self: *String, new_slice: Slice) !void {
    try self.addStringSlice(new_slice.str, new_slice.start, new_slice.end);
}

pub fn addStringSlice(self: *String, input: *const String, start: Index, end: Index) !void {
    const from_ptr = input.d orelse return;
    if (end.cp > from_ptr.codepoints_.items.len) {
        return error.OutOfBounds;
    }
    var data = self.dataMut();
    try data.codepoints_.appendSlice(ctx.a, from_ptr.codepoints_.items[start.cp..end.cp]);
    try data.graphemes_.appendSlice(ctx.a, from_ptr.graphemes_.items[start.cp..end.cp]);
    data.grapheme_count += end.gr - start.gr;
}

pub fn addUtf8(self: *String, what: []const u8) !void {
    if (what.len == 1) {
        try self.addChar(what[0]);
    } else {
        try self.addConsume(try String.New(what));
    }
}

pub fn afterLast(self: String) Index { // returns index past last grapheme
    const sd = self.d orelse return .{};
    return Index{ .cp = sd.codepoints_.items.len, .gr = sd.grapheme_count };
}

pub fn asSlice(self: *const String) Slice {
    return Slice{ .str = self, .start = .{}, .end = self.afterLast() };
}

pub fn beforeLast(self: String) Index { // returns index before last grapheme
    const sd = self.d orelse return strStart();
    var i: usize = sd.codepoints_.items.len;
    if (i == 0) {
        return .{};
    }

    while (i > 0) {
        i -= 1;
        if (sd.graphemes_.items[i] == 1) {
            break;
        }
    }

    return Index{ .cp = i, .gr = sd.grapheme_count - 1 };
}

pub fn between(self: String, start: usize, end: usize) !String {
    return self.substring(start, @intCast(end - start));
}

pub fn betweenIndices(self: String, start: Index, end: Index) !String {
    var result = String{};
    var to = result.dataMut();
    const from = self.dataConst() orelse return result;
    try to.codepoints_.appendSlice(ctx.a, from.codepoints_.items[start.cp..end.cp]);
    try to.graphemes_.appendSlice(ctx.a, from.graphemes_.items[start.cp..end.cp]);
    to.grapheme_count = end.gr - start.gr;

    return result;
}

pub fn changeToAsciiExtension(self: *String, ext: []const u8) !void {
    // Simple implementation, for now doesn't account for .tar.* types of extensions
    if (self.lastIndexOfAscii(".", .{})) |idx| {
        self.dropRight(idx, RetainCapacity.Yes);
    }
    try self.addAscii(ext);
}

pub fn charAt(self: *const String, at: usize) ?Grapheme {
    const index = self.findIndex(at) orelse return null;
    return self.charAtIndex(index);
}

pub fn charAtIndex(self: *const String, at: Index) ?Grapheme {
    return Grapheme.From(self, at);
}

/// Sometimes it only makes sense to operate with one codepoint graphemes,
/// like with interpreting ranges, like A-Z, or 0-9. This method makes sure
/// the grapheme at index `at` is one codepoint, and if so returns this codepoint.
pub fn charAtIndexOneCp(self: *const String, at: Index) ?Codepoint {
    const data = self.d orelse return null;
    return charAtIndexOneCp_real(data.codepoints_.items[0..], data.graphemes_.items[0..], at);
}

pub fn codepointsPtr(self: *const String) ?ConstCpSlice {
    if (self.getConstPointer()) |sd| {
        return sd.codepoints_.items;
    }

    return null;
}

pub fn clearAndFree(self: *String) void {
    var data = self.dataMut();
    data.codepoints_.clearAndFree(ctx.a);
    data.graphemes_.clearAndFree(ctx.a);
    data.grapheme_count = 0;
}

pub fn clearRetainingCapacity(self: *String) void {
    var data = self.dataMut() catch return;
    data.codepoints.clearRetainingCapacity();
    data.graphemes.clearRetainingCapacity();
    data.grapheme_count = 0;
}

pub fn Clone(self: String) !String {
    var sd = self.d orelse return String{};
    return String{
        .d = try sd.Clone(),
    };
}

pub fn CloneWith(self: String, rhs: String) !String {
    var s = try self.Clone();
    try s.add(rhs);
    return s;
}

inline fn countGraphemes(gr_slice: GraphemeSlice) usize {
    if (gr_slice.len > SimdVecLen * 16) {
        return countGraphemesSimd(gr_slice);
    }
    return countGraphemesLinear(gr_slice);
}

inline fn countGraphemesLinear(gr_slice: GraphemeSlice) usize {
    var count: usize = 0;
    for (gr_slice) |n| {
        if (n == 1)
            count += 1;
    }

    return count;
}

fn countGraphemesSimd(gr_slice: GraphemeSlice) usize {
    const needle: u1 = 1;
    var pos: usize = 0;
    var count: usize = 0;
    const vec_needles: @Vector(SimdVecLen, u1) = @splat(needle);
    while (pos < gr_slice.len) {
        if ((gr_slice.len - pos) < SimdVecLen) { // do it manually
            for (gr_slice[pos..]) |k| {
                if (k == 1)
                    count += 1;
            }
            break;
        }
        const line: @Vector(SimdVecLen, u1) = gr_slice[pos..][0..SimdVecLen].*;
        const does_match = line == vec_needles;
        count += std.simd.countTrues(does_match);
        pos += SimdVecLen;
    }

    return count;
}

pub fn countGraphemesRaw(alloc: Allocator, input: []const u8) usize {
    const gd = Graphemes.GraphemeData.init(alloc) catch return 0;
    defer gd.deinit();
    var gr_iter = Graphemes.Iterator.init(input, &gd);
    var grapheme_count: usize = 0;
    while (gr_iter.next()) |grapheme| {
        _ = grapheme;
        grapheme_count += 1;
    }

    return grapheme_count;
}

pub fn dataConst(self: *const String) ?*const Data {
    if (self.d) |*k| {
        return k;
    }
    return null;
}

inline fn dataMut(self: *String) *Data {
    if (self.d) |*k| {
        return k;
    }

    return self.initEmpty();
}

pub fn dropLeft(self: *String, from: Index) void {
    var data = self.dataMut();
    const no_codepoints: []const Codepoint = &[_]Codepoint{};
    data.codepoints_.replaceRangeAssumeCapacity(0, from.cp, no_codepoints);

    const no_graphemes: []const u1 = &[_]u1{};
    data.graphemes_.replaceRangeAssumeCapacity(0, from.cp, no_graphemes);

    data.grapheme_count -= from.gr;
}

pub fn dropRight(self: *String, from: Index, ret: RetainCapacity) void {
    var data = self.dataMut();
    if (ret == RetainCapacity.Yes) {
        data.codepoints_.shrinkRetainingCapacity(from.cp);
        data.graphemes_.shrinkRetainingCapacity(from.cp);
    } else {
        data.codepoints_.shrinkAndFree(ctx.a, from.cp);
        data.graphemes_.shrinkAndFree(ctx.a, from.cp);
    }
    data.grapheme_count = from.gr;
}

const Comparison = struct {
    cs: CaseSensitive = .Yes,
};

pub fn endsWithUtf8(self: String, phrase: []const u8, cmp: Comparison) bool {
    var needles = toCodepoints(ctx.a, phrase) catch return false;
    defer needles.deinit(ctx.a);
    return self.endsWithCodepointSlice(needles.items, cmp);
}

pub fn endsWithAscii(self: String, letters: []const u8, cmp: Comparison) bool {
    if (letters.len == 1) {
        return self.endsWithCp(letters[0]);
    }

    const data = self.d orelse return false;
    const sensitive = cmp.cs == .Yes;

    const cp_slice = data.codepoints_.items[0..];
    if (cp_slice.len < letters.len) {
        return false;
    }
    const case_bit: u8 = ~@as(u8, 32);
    for (cp_slice[cp_slice.len - letters.len .. cp_slice.len], letters) |l, r| {
        const a = if (sensitive) l else (l & case_bit);
        const b = if (sensitive) r else (r & case_bit);
        if (a != b) {
            return false;
        }
    }

    return true;
}

/// returns true if the codepoint is a whole grapheme
pub fn endsWithCp(self: String, cp: Codepoint) bool {
    const sd = self.d orelse return false;
    const cp_slice = sd.codepoints_.items[0..];
    if (cp_slice.len == 0 or cp_slice[cp_slice.len - 1] != cp)
        return false;
    const glist = sd.graphemes_.items[0..];
    return glist[glist.len - 1] == 1;
}

pub fn endsWithCodepointSlice(self: String, needles: CpSlice, cmp: Comparison) bool {
    if (needles.len == 1 and cmp.cs == .Yes) {
        return self.endsWithCp(needles[0]);
    }
    const sd = self.d orelse return false;
    const start_index: usize = sd.codepoints_.items.len - needles.len;
    // The starting codepoint must be a grapheme
    if (sd.graphemes_.items[start_index] != 1) {
        return false;
    }

    if (cmp.cs == .Yes) {
        return std.mem.endsWith(Codepoint, sd.codepoints_.items, needles);
    }

    if (sd.codepoints_.items.len < needles.len) {
        return false;
    }

    for (sd.codepoints_.items[start_index..], needles) |l, r| {
        if (ctx.letter_casing.toUpper(l) != ctx.letter_casing.toUpper(r)) {
            return false;
        }
    }

    return true;
}

pub fn endsWith(self: String, needles: String, cmp: Comparison) bool {
    const sdn = needles.d orelse return false;
    return self.endsWithCodepointSlice(sdn.codepoints_.items, cmp);
}

pub fn ensureTotalCapacity(self: *String, cp_count: usize) !void {
    var data = self.dataMut();
    try data.graphemes_.ensureTotalCapacity(cp_count);
    try data.codepoints_.ensureTotalCapacity(cp_count);
}

pub fn eqUtf8(self: String, input: []const u8) bool {
    return self.equalsUtf8(input, .{});
}

pub fn eq(self: String, other: String) bool {
    return self.equals(other, .{});
}

pub fn equals(self: String, other: String, cmp: Comparison) bool {
    const sdo = other.d orelse return false;
    return self.equalsCpSlice(sdo.codepoints_.items, cmp);
}

pub fn equalsAscii(self: String, input: []const u8, cmp: Comparison) bool {
    const data = self.d orelse return (input.len == 0);
    return matchesAscii_real(data.codepoints_.items[0..], data.graphemes_.items[0..], input, .{ .cs = cmp.cs }) != null;
}

pub fn equalsCpSlice(self: String, cp_slice: CpSlice, cmp: Comparison) bool {
    const data = self.d orelse return (cp_slice.len == 0);
    return equalsCodepointSlice_real(data.codepoints_.items[0..], cp_slice, cmp);
}

pub fn equalsUtf8(self: String, input: []const u8, cmp: Comparison) bool {
    var list = toCodepoints(ctx.a, input) catch return false;
    defer list.deinit(ctx.a);
    return self.equalsCpSlice(list.items, cmp);
}

fn findCaseless(graphemes: GraphemeSlice, haystack: ConstCpSlice, needles: ConstCpSlice) ?usize {
    var index: ?usize = null;
    const till: usize = haystack.len - needles.len + 1;
    for (0..till) |i| {
        index = i;
        for (needles, haystack[i .. i + needles.len]) |l, r| {
            if (ctx.letter_casing.toUpper(l) != ctx.letter_casing.toUpper(r)) {
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
    const data = self.d orelse return null;
    return findManyLinear_real(data.codepoints_.items[0..], data.graphemes_.items[0..], needles, start, cs);
}

pub fn findManySimd(self: String, needles: ConstCpSlice, from_index: ?Index, comptime depth: u16) ?Index {
    const data = self.d orelse return null;
    return findManySimd_real(data.codepoints_.items[0..], data.graphemes_.items[0..], needles, from_index, depth);
}

pub fn findOneSimd(self: String, needle: Codepoint, from: usize, comptime vec_len: u16) ?usize {
    const sd = self.d orelse return null;
    return findOneSimd_real(sd.codepoints_.items[0..], needle, from, vec_len);
}

pub fn findOneSimdFromEnd(self: String, needle: Codepoint, start: ?usize, comptime vector_len: ?u16) ?usize {
    const data = self.d orelse return null;
    return findOneSimdFromEnd_real(data.codepoints_.items[0..], needle, start, vector_len);
}

pub fn format(self: *const String, writer: *std.Io.Writer) !void {
    return self._(0).format(writer);
}

pub fn _(self: *const String, context: i32) String_ {
    return .{ .s = self, .context = context };
}

const String_ = struct {
    context: i32,
    s: *const String,
    pub fn format(self: String_, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        var buf = self.s.toUtf8(ctx.a) catch return;
        defer buf.deinit(ctx.a);
        try printBytes(buf, writer, self.context);
    }
};

inline fn getConstPointer(self: *const String) ?*const Data {
    if (self.d) |*k| {
        return k;
    }

    mtl.debug(@src(), "Returning null Data ptr", .{});
    return null;
}

pub fn findIndex(self: String, grapheme_index: usize) ?Index {
    const data = self.d orelse return null;
    if (grapheme_index >= data.grapheme_count) {
        return if (grapheme_index == data.grapheme_count) self.afterLast() else null;
    }

    return findIndex_real(data.graphemes_.items[0..], grapheme_index);
}

pub fn findIndexFrom(self: String, from: Index, grapheme_index: usize) ?Index {
    const data = self.d orelse return null;
    const gr_index: usize = from.gr + grapheme_index;
    if (gr_index >= data.grapheme_count) {
        return if (gr_index == data.grapheme_count) self.afterLast() else null;
    }

    return findIndexFrom_real(data.graphemes_.items[0..], from, grapheme_index);
}

pub fn findIndexByCp(self: String, codepoint_index: usize) ?Index {
    const sd = self.d orelse return null;
    if (countGraphemes(sd.graphemes_.items[0 .. codepoint_index + 1])) |g| {
        return Index{ .cp = codepoint_index, .gr = g };
    }

    return null;
}

pub fn graphemesToUtf8(alloc: Allocator, input: CpSlice) !ArrayList(u8) {
    return utf8_from_slice(alloc, input);
}

pub fn indexOf(self: String, input: String, find: Args) ?Index {
    const sd = input.d orelse return null;
    return self.indexOfCpSlice(sd.codepoints_.items, find);
}

pub fn indexOfAscii(self: String, input: []const u8, find: Args) ?Index {
    var buf = toCodepointsFromAscii(ctx.a, input) catch return null;
    defer buf.deinit(ctx.a);
    return self.indexOfCpSlice(buf.items, find);
}

pub fn indexOfUtf8(self: String, input: []const u8, args: Args) ?Index {
    const data = self.d orelse return null;
    return indexOfUtf8_real(data.codepoints_.items[0..], data.graphemes_.items[0..], input, args);
}

pub fn indexOfUtf8_2(self: String, input: []const u8, find: Find) ?Index {
    if (find.from == 0) {
        return self.indexOfUtf8(input, .{ .cs = find.cs });
    }
    const index = self.findIndex(find.from) orelse return null;
    return self.indexOfUtf8(input, .{ .from = index, .cs = find.cs });
}

pub fn indexOfCpSlice(self: String, needles: CpSlice, args: Args) ?Index {
    const data = self.d orelse return null;
    return indexOfCpSlice_real(data.codepoints_.items[0..], data.graphemes_.items[0..], needles, args);
}

fn initEmpty(self: *String) *Data {
    if (self.d) |*p| {
        return p;
    }

    var k = Data{
        .graphemes_ = .empty,
        .codepoints_ = .empty,
        .grapheme_count = 0,
    };

    self.d = k;
    return if (self.d) |*p| p else &k; // a hack, we know that self.d is always set
}

inline fn endsWithGrapheme(a: []const u1, end: usize) bool {
    if (a.len < end)
        return false;
    if (a.len == end)
        return true; // goes till the end, which implies it ends with a grapheme

    return a[end] == 1; // the next one is a grapheme, therefore the previous sequence ends with a grapheme
}

pub fn init(self: *String, input: []const u8, clear: Clear) !void {
    if (clear == Clear.Yes) {
        self.clearAndFree();
    }

    if (input.len == 0)
        return;

    var data: *Data = self.dataMut();
    const approx = @max(input.len / 2, 2);
    try data.codepoints_.ensureTotalCapacity(ctx.a, approx);
    try data.graphemes_.ensureTotalCapacity(ctx.a, approx);
    var gc_iter = ctx.graphemes.iterator(input);
    while (gc_iter.next()) |grapheme| {
        data.grapheme_count += 1;
        var new_grapheme = true;
        const bytes = grapheme.bytes(input);
        var cp_iter = zg_codepoint.Iterator{ .bytes = bytes };
        while (cp_iter.next()) |obj| {
            try data.graphemes_.append(ctx.a, if (new_grapheme) 1 else 0);
            if (new_grapheme) {
                new_grapheme = false;
            }
            try data.codepoints_.append(ctx.a, obj.code);
        }
    }
}

pub fn insertUtf8(self: *String, at_gr_pos: ?Index, what: []const u8) !void {
    const input = try String.New(what);
    defer input.deinit();
    try self.insert(at_gr_pos, input);
}

pub fn insert(self: *String, at_pos: ?Index, input: String) !void {
    if (input.isEmpty())
        return;
    const index = at_pos orelse return;
    var data = self.dataMut();
    const sdo = input.d orelse return Error.Alloc;
    try data.codepoints_.insertSlice(ctx.a, index.cp, sdo.codepoints_.items);
    try data.graphemes_.insertSlice(ctx.a, index.cp, sdo.graphemes_.items);
    data.grapheme_count += sdo.grapheme_count;
}

pub fn isBetween(self: String, l: []const u8, r: []const u8) ?String {
    if (l.len != 1 or r.len != 1) {
        var a = toCodepoints(ctx.a, l) catch return null;
        defer a.deinit(ctx.a);
        var b = toCodepoints(ctx.a, r) catch return null;
        defer b.deinit(ctx.a);
        return self.isBetweenSlices(a.items, b.items);
    }
    const a = toCp(l) catch return null;
    const b = toCp(r) catch return null;
    return self.isBetweenCp(a, b);
}

pub fn isBetweenCp(self: String, l: Codepoint, r: Codepoint) ?String {
    if (!self.startsWithCp(l) or !self.endsWithCp(r))
        return null;
    return self.betweenIndices(.{ .cp = 1, .gr = 1 }, self.beforeLast()) catch return null;
}

pub fn isBetweenSlices(self: String, l: CpSlice, r: CpSlice) ?String {
    if (!self.startsWithSlice(l, .{}) or !self.endsWithCodepointSlice(r, .{}))
        return null;
    return self.between(l.len, self.size() - r.len) catch return null;
}

pub fn isEmpty(self: String) bool {
    return if (self.d) |sd| sd.grapheme_count == 0 else true;
}

inline fn isGrapheme(self: String, i: usize) bool {
    const sd = self.d orelse return false;
    return sd.graphemes_.items[i] == 1;
}

pub fn isDigit(self: String, at: Index) bool {
    const cp = self.charAtIndexOneCp(at) orelse return false;
    return cp >= '0' and cp <= '9';
}

pub fn isWhitespace(self: String, at: Index) bool {
    const g = self.charAtIndex(at) orelse return false;
    return g.isWhitespace();
}

pub fn isWordBoundary(self: String, at: Index, charset: Charset) bool {
    if (at.cp == 0) {
        const gr = self.charAtIndex(at) orelse return false;
        return gr.isWordChar(charset);
    }

    const previous = self.prev(at) orelse return false;
    const gr = self.charAtIndex(at);
    if (gr) |g| {
        return previous.isWordChar(charset) != g.isWordChar(charset);
    }

    return previous.isWordChar(charset);
}

pub fn isWordChar(self: String, at: Index, charset: Charset) bool {
    const gr = self.charAtIndex(at) orelse return false;
    return gr.isWordChar(charset);
}

pub fn iterator(self: *const String) StringIterator {
    return StringIterator.New(self, null);
}

pub fn iteratorFrom(self: *const String, from: Index) StringIterator {
    return StringIterator.New(self, from);
}

pub fn iteratorFromEnd(self: *const String) StringIterator {
    return self.iteratorFrom(self.beforeLast());
}

fn lastIndexGeneric(self: *const String, comptime T: type, needles: []const T, args: Args) ?Index {
    const data = self.d orelse return null;
    return lastIndexGeneric_real(data.codepoints_.items[0..], data.graphemes_.items[0..], data.grapheme_count, T, needles, args);
}

pub fn lastIndexOf(self: *const String, needles_str: String, args: Args) ?Index {
    const nd = needles_str.d orelse return null;
    const needles = nd.codepoints_.items[0..];
    return self.lastIndexGeneric(Codepoint, needles, args);
}

pub fn lastIndexOfAscii(self: *const String, needles: []const u8, args: Args) ?Index {
    return self.lastIndexGeneric(u8, needles, args);
}

pub fn lastIndexOfCp(self: *const String, needle: Codepoint, args: Args) ?Index {
    const data = self.d orelse return null;
    return lastIndexOfCp_real(data.codepoints_.items[0..], data.graphemes_.items[0..], data.grapheme_count, needle, args);
}

pub fn lastIndexOfUtf8(self: String, needles: []const u8, args: Args) ?Index {
    if (needles.len == 1) {
        return self.lastIndexOfCp(needles[0], args);
    }

    const s = String.New(needles) catch return null;
    defer s.deinit();
    return self.lastIndexOf(s);
}

pub fn lastChar(self: *const String) ?Grapheme {
    const idx = self.beforeLast();
    return self.charAtIndex(idx);
}

pub fn leftSlice(self: *const String, from: Index) Slice {
    return self.slice(.{}, from);
}

pub fn matches(self: String, input: *const String, args: Args) ?Index {
    const data = self.d orelse return null;
    return matches_real(data.codepoints_.items[0..], data.graphemes_.items[0..], input, args);
}

pub fn matchesAscii(self: String, input: []const u8, args: Args) ?Index {
    const data = self.d orelse return null;
    return matchesAscii_real(data.codepoints_.items[0..], data.graphemes_.items[0..], input, args);
}

pub fn matchesUtf8(self: String, input: []const u8, args: Args) ?Index {
    const s = String.New(input) catch return null;
    defer s.deinit();
    return self.matches(s, args);
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

pub fn midSlice(self: *const String, from_index: Index) Slice {
    return Slice{ .str = self, .start = from_index, .end = self.afterLast() };
}

pub fn next(self: *const String, idx: Index) ?Grapheme {
    const next_idx = idx.nextIndex(self) orelse return null;
    return self.charAtIndex(next_idx);
}

pub fn offset(self: String, by: usize) Index {
    _ = self;
    return .{.cp = by, .gr = by};
}

/// parseInt tries to parse this string as an integer of type `T` in base `radix`.
pub fn parseInt(self: String, comptime T: type, radix: u8) !T {
    var buf = try self.toUtf8(ctx.a);
    defer buf.deinit(ctx.a);
    return std.fmt.parseInt(T, buf.items, radix);
}

/// parseFloat tries to parse this string as an floating point number of type `T`.
pub fn parseFloat(self: String, comptime T: type) !T {
    var buf = try self.toUtf8(ctx.a);
    defer buf.deinit(ctx.a);
    return std.fmt.parseFloat(T, buf.items);
}

pub fn prev(self: *const String, idx: Index) ?Grapheme {
    var mut_idx = idx;
    const prev_idx = mut_idx.prevIndex(self) orelse return null;
    return self.charAtIndex(prev_idx);
}

pub fn prevIndex(self: *const String, idx: Index) ?Index {
    var mut_idx = idx;
    return mut_idx.prevIndex(self);
}

pub fn printInfo(self: String, src: std.builtin.SourceLocation, msg: ?[]const u8) void {
    const color = if (string_theme == Theme.Light) mtl.COLOR_DEFAULT else mtl.COLOR_GREEN;
    const info = if (msg) |k| k else "String.printInfo(): ";
    if (self.size() <= 255) {
        mtl.debug(src, "{s}[gr={},cp={}]={s}\"{s}\"", .{ info, Num.New(self.size()), Num.New(self.size_cp()), color, self });
    } else {
        mtl.debug(src, "{s}[gr={},cp={}]={s}", .{ info, Num.New(self.size()), Num.New(self.size_cp()), color });
    }
}

const print_format_str = "{s}{}{s}{s}|{s}|{s}{s}{f}{s} ";
const nl_chars = mtl.UNDERLINE_START ++ "(LF)" ++ mtl.UNDERLINE_END;
const cr_chars = mtl.UNDERLINE_START ++ "(CR)" ++ mtl.UNDERLINE_END;
const crnl_chars = mtl.UNDERLINE_START ++ "(CR/LF)" ++ mtl.UNDERLINE_END;

fn printCpBuf(out: anytype, cp_buf: ArrayList(Codepoint), gr_index: isize, see_as: SeeAs, attr: Attr) !void {
    const theme = string_theme;
    if (cp_buf.items.len == 0)
        return;

    var codepoints_str = String{};
    defer codepoints_str.deinit();
    var temp_str_buf: [32]u8 = undefined;

    for (cp_buf.items, 0..) |k, i| {
        const num_as_str = try std.fmt.bufPrint(&temp_str_buf, "{}", .{k}); //"0x{X}"
        try codepoints_str.addAscii(num_as_str);
        const s: Codepoint = if (i < cp_buf.items.len - 1) '+' else ' ';
        try codepoints_str.addChar(s);
    }

    var utf8: ArrayList(u8) = try utf8_from_slice(ctx.a, cp_buf.items);
    defer utf8.deinit(ctx.a);
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

    const cp_color: []const u8 = if (see_as == SeeAs.PartOfGrapheme) mtl.COLOR_GREEN else mtl.COLOR_MAGENTA;
    var final_fg: []const u8 = if (theme == Theme.Light) mtl.COLOR_BLACK else cp_color;
    if (attr == Attr.Codepoint) {
        final_fg = mtl.COLOR_RED ++ mtl.BOLD_START;
    }

    const end_final_fg = if (attr == Attr.Codepoint) mtl.COLOR_DEFAULT ++ mtl.BOLD_END else mtl.COLOR_DEFAULT;
    const num_color = if (theme == Theme.Light) mtl.COLOR_OTHER else mtl.COLOR_YELLOW;
// mtl.debug(@src(), "gr_index: {}", .{gr_index});
    out.print(print_format_str, .{ mtl.COLOR_BLUE, gr_index, mtl.COLOR_DEFAULT, final_fg, cp_as_str, end_final_fg, num_color, codepoints_str, mtl.COLOR_DEFAULT });
}

pub fn printCodepoints(self: String, src: std.builtin.SourceLocation) !void {
    const data = self.d orelse return;
    try printCodepoints_real(data.codepoints_.items[0..], data.graphemes_.items[0..], src, .{});
}

pub fn printGraphemes(self: String, src: std.builtin.SourceLocation) !void {
    const data = self.d orelse return;
    try printGraphemes_real(data.codepoints_.items[0..], data.graphemes_.items[0..], src, .{});
}

pub fn printFind(self: String, needles: []const u8, from: usize, cs: CaseSensitive) ?Index {
    const index = self.indexOf(needles, from, cs);
    const needles_str = String.New(needles) catch return null;
    defer needles_str.deinit();
    return index;
}

pub fn remove(self: *String, needles: []const u8) !void {
    const s = try String.New(needles);
    defer s.deinit();
    const from = self.indexOf(s, .{}) orelse return;
    const data = s.dataConst() orelse return;
    try self.removeLowLevel(from.cp, data.codepoints_.items.len, data.grapheme_count);
}

pub fn removeByIndex(self: *String, start_index: ?Index, gr_count_to_remove: usize) !void {
    var data = self.dataMut();
    const start = start_index orelse return;
    if (gr_count_to_remove == 0)
        return; // removing zero graphemes is not an error

    var cp_count: usize = 0;
    var gr_so_far: usize = 0;
    var break_at_next = false;
    for (data.graphemes_.items[start.cp..]) |b| {
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

    const till = @min(data.codepoints_.items.len, start.cp + cp_count);
    const len_in_cp = till - start.cp;
    try self.removeLowLevel(start.cp, len_in_cp, gr_count_to_remove);
}

pub fn removeLowLevel(self: *String, from_cp: usize, cp_count: usize, gr_count: usize) !void {
    var data = self.dataMut();
    const no_codepoints: []const Codepoint = &[_]Codepoint{};
    try data.codepoints_.replaceRange(ctx.a, from_cp, cp_count, no_codepoints);

    const no_graphemes: []const u1 = &[_]u1{};
    try data.graphemes_.replaceRange(ctx.a, from_cp, cp_count, no_graphemes);

    data.grapheme_count -= gr_count;
}

pub fn replaceUtf8(self: *String, start_index: ?Index, gr_count_to_remove: usize, replacement: []const u8) !void {
    try self.removeByIndex(start_index, gr_count_to_remove);
    try self.insertUtf8(start_index, replacement);
}

pub fn replace(self: *String, start_index: ?Index, gr_count_to_remove: usize, replacement: String) !void {
    try self.removeByIndex(start_index, gr_count_to_remove);
    try self.insert(start_index, replacement);
}

pub fn resetTo(self: *String, str: []const u8) !void {
    try self.init(str, Clear.Yes);
}

pub fn reset(self: *String) void {
    self.clearAndFree();
}

/// returns the graphemes count in string
pub fn size(self: String) usize {
    return if (self.d) |data| data.grapheme_count else 0;
}

/// returns the codepoints count in string
pub fn size_cp(self: String) usize {
    return if (self.d) |sd| sd.codepoints_.items.len else 0;
}

pub fn slice(self: *const String, start: Index, end: Index) Slice {
    return Slice{ .str = self, .start = start, .end = end };
}

pub fn splitPair(self: String, sep: []const u8) ![2]String {
    var arr = try self.split(sep, .{});
    defer arr.deinit(ctx.a);
    if (arr.items.len != 2) {
        for (arr.items) |item| {
            item.deinit();
        }
        return String.Error.Other;
    }

    return .{ arr.items[0], arr.items[1] };
}

const SplitArgs = struct {
    keep: KeepEmptyParts = KeepEmptyParts.Yes,
    cs: CaseSensitive = CaseSensitive.Yes,
};

pub fn split(self: String, sep: []const u8, sa: SplitArgs) !ArrayList(String) {
    const sd = self.d orelse return Error.Alloc;
    var array: ArrayList(String) = .empty;
    errdefer {
        for (array.items) |item| {
            item.deinit();
        }
        array.deinit(ctx.a);
    }

    var from = Index.strStart();
    while (self.indexOfUtf8(sep, .{ .from = from, .cs = sa.cs })) |found| {
        const s = try self.mid(from.gr, @intCast(found.gr - from.gr));
        from = Index{ .cp = found.cp + 1, .gr = found.gr + 1 };

        if (sa.keep == KeepEmptyParts.No and s.isEmpty()) {
            s.deinit();
            continue;
        }

        try array.append(ctx.a, s);
        if (from.cp >= sd.codepoints_.items.len) {
            break;
        }
    }

    if (from.cp < sd.codepoints_.items.len) {
        const s = try self.mid(from.gr, -1);
        if (sa.keep == KeepEmptyParts.No and s.isEmpty()) {
            //try s.print(std.debug, "Skipping2: ");
            s.deinit();
        } else {
            try array.append(ctx.a, s);
        }
    }

    return array;
}

pub fn splitSlices(self: *const String, sep: []const u8, sa: SplitArgs) !ArrayList(Slice) {
    const sd = self.d orelse return Error.Alloc;
    var array: ArrayList(Slice) = .empty;
    errdefer array.deinit(ctx.a);
    const sep_str = try String.New(sep);
    defer sep_str.deinit();
    var from = Index.strStart();

    while (self.indexOf(sep_str, .{ .from = from, .cs = sa.cs })) |found| {
        // const end = Index {.cp = found.cp - from.cp, .gr = found.gr - from.gr};
        const s = self.slice(from, found);
        // const s = try self.midSlice(from.gr, @intCast(found.gr - from.gr));
        from = Index{ .cp = found.cp + 1, .gr = found.gr + 1 };

        if (sa.keep == KeepEmptyParts.No and s.isEmpty()) {
            continue;
        }

        try array.append(ctx.a, s);
        if (from.cp >= sd.codepoints_.items.len) {
            break;
        }
    }

    if (from.cp < sd.codepoints_.items.len) {
        const s = self.slice(from, self.afterLast());
        if (sa.keep == KeepEmptyParts.No and s.isEmpty()) {
            // s.deinit();
        } else {
            try array.append(ctx.a, s);
        }
    }

    return array;
}

pub fn startsWith(self: String, needles: String, cmp: Comparison) bool {
    const sdn = needles.d orelse return false;
    return self.startsWithSlice(sdn.codepoints_.items, cmp);
}

pub fn startsWithAscii(self: String, needles: []const u8, cmp: Comparison) bool {
    if (needles.len == 1) {
        return self.startsWithCp(needles[0]);
    }

    const sd = self.d orelse return false;
    const cp_count = sd.codepoints_.items.len;
    if (cp_count < needles.len) {
        return false;
    }

    if (cmp.cs == .Yes) {
        if (cp_count > needles.len) {
            if (sd.graphemes_.items[needles.len] != 1) {
                return false;
            }
        }

        for (0..needles.len) |i| {
            if (sd.codepoints_.items[i] != needles[i]) {
                return false;
            }
        }

        return true;
    }

    var cps: ArrayList(Codepoint) = .empty;
    defer cps.deinit(ctx.a);
    var arr = cps.addManyAsSlice(ctx.a, needles.len) catch return false;
    for (0..needles.len) |i| {
        arr[i] = needles[i];
    }

    return self.startsWithSlice(cps.items, cmp);
}

pub fn startsWithUtf8(self: String, needles: []const u8, cmp: Comparison) bool {
    if (needles.len == 1) {
        const cp = toCp(needles) catch return false;
        return self.startsWithCp(cp);
    }
    var cps = String.toCodepoints(ctx.a, needles) catch return false;
    defer cps.deinit(ctx.a);
    return self.startsWithSlice(cps.items, cmp);
}

// returns true if the codepoint is a whole grapheme
pub fn startsWithCp(self: String, cp: Codepoint) bool {
    const sd = self.d orelse return false;
    const cp_slice = sd.codepoints_.items[0..];
    if (cp_slice.len == 0 or cp_slice[0] != cp)
        return false;
    const gr_list = sd.graphemes_.items[0..];
    return gr_list.len == 1 or gr_list[1] == 1; // it's either the end or the next cp is a grapheme
}

pub fn startsWithSlice(self: String, needles: CpSlice, cmp: Comparison) bool {
    const sd = self.d orelse return false;
    if (sd.graphemes_.items.len > needles.len) {
        // make sure it ends on a grapheme boundary:
        if (sd.graphemes_.items[needles.len] != 1) {
            return false;
        }
    }

    if (cmp.cs == CaseSensitive.Yes) {
        return std.mem.startsWith(Codepoint, sd.codepoints_.items, needles);
    }

    if (sd.codepoints_.items.len < needles.len) {
        return false;
    }

    for (sd.codepoints_.items[0..needles.len], needles) |l, r| {
        if (ctx.letter_casing.toUpper(l) != ctx.letter_casing.toUpper(r)) {
            return false;
        }
    }

    return true;
}

pub fn strStart() Index {
    return Index{};
}

pub fn substr(self: *const String, start: Index, how_many_gr: usize) !String {
    var new_str = String.Empty();
    const end = self.findIndexFrom(start, how_many_gr) orelse return error.Other;
    try new_str.addStringSlice(self, start, end);
    return new_str;
}

pub fn substring(self: String, start: usize, count: isize) !String {
    const sd = self.d orelse return error.Other;
    const how_many_gr: usize = if (count == -1) sd.grapheme_count - start else @intCast(count);
    const start_index = self.findIndex(start) orelse return error.NotFound;
    return self.substr(start_index, how_many_gr);
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

pub fn toCodepointsFromAscii(a: Allocator, input: []const u8) !ArrayList(Codepoint) {
    var buf: ArrayList(Codepoint) = .empty;
    errdefer buf.deinit(a);
    var arr = try buf.addManyAsSlice(a, input.len);
    for (0..arr.len) |i| {
        arr[i] = input[i];
    }

    return buf;
}

pub fn toCodepoints(a: Allocator, input: []const u8) !ArrayList(Codepoint) {
    var buf: ArrayList(Codepoint) = .empty;
    errdefer buf.deinit(a);
    var cp_iter = zg_codepoint.Iterator{ .bytes = input };
    while (cp_iter.next()) |obj| {
        try buf.append(a, obj.code);
    }

    return buf;
}

pub fn toLower(self: *String) !void {
    try toLower2(self.dataMut().codepoints_.items);
}

pub fn toLower2(list: CpSlice) !void {
    for (list) |*k| {
        k.* = ctx.letter_casing.toLower(k.*);
    }
}

pub inline fn toLowerCp(cp: Codepoint) Codepoint {
    return ctx.letter_casing.toLower(cp);
}

pub fn toOwnedSlice(self: String, a: Allocator) ![]u8 {
    var buf = try self.toUtf8(a);
    return buf.toOwnedSlice(a);
}

pub fn toUtf8(self: String, alloc: Allocator) !ArrayList(u8) {
    const ret: ArrayList(u8) = .empty;
    const sd = self.d orelse return ret;
    return utf8_from_slice(alloc, sd.codepoints_.items);
}

pub fn toUpper(self: *String) !void {
    try toUpper2(self.dataMut().codepoints_.items);
}

pub fn toUpper2(list: CpSlice) !void {
    for (list) |*k| {
        k.* = ctx.letter_casing.toUpper(k.*);
    }
}

pub inline fn toUpperCp(cp: Codepoint) Codepoint {
    return ctx.letter_casing.toUpper(cp);
}

pub fn trim(self: *String) !void {
    try self.trimLeft();
    try self.trimRight();
}

/// These are ASCII chars so they translate directly to codepoints
/// because UTF-8 guarantees that.
const CodepointsToTrim = [_]Codepoint{ ' ', '\t', '\n', '\r' };

pub fn trimLeft(self: *String) void {
    const data = self.dataMut();
    const cp_count = data.codepoints_.items.len;
    if (cp_count == 0) {
        return;
    }

    var remove_count: usize = 0;
    for (0..cp_count) |i| {
        if (!data.isOneCodepointGrapheme(i))
            break;
        const cp = data.codepoints_.items[i];
        if (std.mem.indexOfScalar(u21, &CodepointsToTrim, cp)) |index| {
            _ = index;
            remove_count += 1;
        } else {
            break;
        }
    }

    if (remove_count > 0) {
        self.dropLeft(Index{ .cp = remove_count, .gr = remove_count });
    }
}

pub fn trimRight(self: *String) void {
    const data = self.dataMut();
    const cp_count = data.codepoints_.items.len;
    if (cp_count == 0) {
        return;
    }

    var remove_count: usize = 0;
    for (1..cp_count) |i| {
        const ri = cp_count - i;
        if (!data.startOfGrapheme(ri))
            break;
        const cp = data.codepoints_.items[ri];
        if (std.mem.indexOfScalar(u21, &CodepointsToTrim, cp)) |index| {
            _ = index;
            remove_count += 1;
        } else {
            break;
        }
    }

    if (remove_count > 0) {
        const from = Index{ .cp = cp_count - remove_count, .gr = data.grapheme_count - remove_count };
        self.dropRight(from, RetainCapacity.Yes);
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

pub fn utf8_from_slice(a: Allocator, cp_slice: ConstCpSlice) !ArrayList(u8) {
    var buf: ArrayList(u8) = .empty;
    errdefer buf.deinit(a);
    var tmp: [4]u8 = undefined;
    //mtl.debug(@src(), "cp_slice.len={}, cp_slice={any}", .{cp_slice.len, cp_slice});
    for (cp_slice) |cp| {
        const len = try unicode.utf8Encode(cp, &tmp);
        try buf.appendSlice(a, tmp[0..len]);
    }

    return buf;
}

fn charAtIndexOneCp_real(codepoints: ConstCpSlice, graphemes: GraphemeSlice, at: Index) ?Codepoint {
    if (at.cp >= codepoints.len) {
        return null;
    }

    if (at.cp == (codepoints.len - 1) or (graphemes[at.cp + 1] == 1)) {
        return codepoints[at.cp];
    }

    return null;
}

fn equalsCodepointSlice_real(codepoints: ConstCpSlice, cp_slice: ConstCpSlice, cmp: Comparison) bool {
    if (cp_slice.len == 0) {
        return codepoints.len == 0;
    }

    if (cmp.cs == CaseSensitive.Yes) {
        return std.mem.eql(Codepoint, codepoints, cp_slice);
    }

    if (codepoints.len != cp_slice.len) {
        return false;
    }

    for (codepoints, cp_slice) |l, r| {
        if (ctx.letter_casing.toUpper(l) != ctx.letter_casing.toUpper(r)) {
            return false;
        }
    }

    return true;
}

fn findIndex_real(graphemes: GraphemeSlice, grapheme_index: usize) ?Index {
    var current_gr_count: isize = -1;
    for (graphemes[0..], 0..) |gr_bit, cp_index| {
        if (gr_bit == 1) {
            current_gr_count += 1;

            if (current_gr_count == grapheme_index)
                return Index{ .cp = cp_index, .gr = grapheme_index };
        }
    }

    if (grapheme_index == 0) {
        return .{};
    }

    return null;
}

fn findIndexFrom_real(graphemes: GraphemeSlice, from: Index, grapheme_index: usize) ?Index {
    const gr_index: usize = from.gr + grapheme_index;
    var cp_index: isize = -1;
    const ifrom: isize = @intCast(from.gr);
    var current_grapheme: isize = ifrom - 1;
    for (graphemes[from.cp..]) |k| {
        cp_index += 1;
        if (k == 1) {
            current_grapheme += 1;
        }

        if (current_grapheme == gr_index)
            return Index{ .cp = from.cp + @abs(cp_index), .gr = gr_index };
    }

    return null;
}

fn findManyLinear_real(codepoints: ConstCpSlice, graphemes: GraphemeSlice, needles: ConstCpSlice, start: ?Index, cs: CaseSensitive) ?Index {
    // const data = self.d orelse return null;
    const cp_count = codepoints.len;
    if (needles.len > cp_count) {
        //out.print("needles > cp_count\n", .{}) catch return null;
        return null;
    }

    const from = start orelse Index.strStart();
    var pos = from.cp;
    var index: usize = undefined;
    while (pos < cp_count) {
        const haystack = codepoints[pos..];
        if (cs == CaseSensitive.Yes) {
            index = std.mem.indexOf(Codepoint, haystack, needles) orelse return null;
        } else {
            const graphemes_offset = graphemes[pos..];
            index = findCaseless(graphemes_offset, haystack, needles) orelse return null;
        }
        //out.print("{s} index={}\n", .{@src().fn_name, index}) catch return null;
        pos += index;
        const is_at_haystack_end = (pos >= (cp_count - 1));
        const next_cp_loc = pos + needles.len;
        if (is_at_haystack_end or next_cp_loc >= cp_count or (graphemes[next_cp_loc] == 1)) { // is at end
            const gr_slice = graphemes[0..pos];
            const gr = countGraphemesLinear(gr_slice);
            return Index{ .cp = pos, .gr = gr };
        }

        pos += 1;
    }

    return null;
}

fn findManySimd_real(arg_codepoints: ConstCpSlice, arg_graphemes: GraphemeSlice, needles: ConstCpSlice, from_index: ?Index, comptime depth: u16) ?Index {
    const from = from_index orelse Index.strStart();
    const cp_count = arg_codepoints.len;
    if ((needles.len == 0) or (needles.len > cp_count) or (from.cp >= cp_count)) {
        return null;
    }

    const haystack = arg_codepoints[from.cp..];
    const graphemes = arg_graphemes[from.cp..];
    var pos: usize = from.cp;
    const first_needle = needles[0];
    while (pos < cp_count) {
        const found_abs = findOneSimd_real(arg_codepoints, first_needle, pos, depth) orelse {
            return null;
        };

        const first = found_abs - from.cp;
        // `first` is now relative to haystack slice, not to arg_codepoints
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
                const gr = countGraphemesSimd(arg_graphemes[0..found_abs]);
                return Index{ .cp = found_abs, .gr = gr };
            }
        }

        pos = found_abs + 1;
    }

    return null;
}

fn findOneSimd_real(codepoints: ConstCpSlice, needle: Codepoint, from: usize, comptime vec_len: u16) ?usize {
    const vector_needles: @Vector(vec_len, Codepoint) = @splat(needle);
    // {0, 1, 2, 3, 4, 5, 6, 7, ..vec_len-1?}
    const vec_indices = std.simd.iota(Codepoint, vec_len);
    // Code points greater than 0x10FFFF are invalid (Unicode standard)
    const nulls: @Vector(vec_len, Codepoint) = @splat(0x10FFFF + 1);
    var pos: usize = 0;
    const haystack = codepoints[from..];

    while (pos < haystack.len) {
        if ((haystack.len - pos) < vec_len) {
            // fallback to a normal scan when our input (or what's left of
            // it is smaller than our vec_len)
            const ret = std.mem.indexOfScalarPos(Codepoint, haystack, pos, needle);
            const index = if (ret) |k| (k + from) else null;
            // mtl.debug(@src(), "found={?}(from={}), fallback to normal scan\n",
            // .{index, from});

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

fn findOneSimdFromEnd_real(codepoints: ConstCpSlice, needle: Codepoint, start: ?usize, comptime vector_len: ?u16) ?usize {
    // const sd = self.d orelse return null;
    // const codepoints = sd.codepoints.items;
    const from = start orelse codepoints.len;
    const haystack = codepoints[0..from];
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

fn indexOfCpSlice_real(codepoints: ConstCpSlice, graphemes: GraphemeSlice, needles: ConstCpSlice, find: Args) ?Index {
    if (needles.len == 0)
        return null;
    // const data = self.d orelse return null;
    if (find.cs == CaseSensitive.Yes and codepoints.len >= SimdVecLen) {
        return findManySimd_real(codepoints, graphemes, needles, find.from, SimdVecLen);
    }
    return findManyLinear_real(codepoints, graphemes, needles, find.from, find.cs);
}

fn indexOfUtf8_real(codepoints: ConstCpSlice, graphemes: GraphemeSlice, input: []const u8, args: Args) ?Index {
    if (input.len == 0)
        return null;

    const from = args.from;
    var cp_slice: ConstCpSlice = undefined;
    var needles: ArrayList(Codepoint) = undefined;
    if (input.len == 1) {
        const cp = toCp(input) catch return null;
        cp_slice = &[_]Codepoint{cp};
    } else {
        needles = String.toCodepoints(ctx.a, input) catch return null;
        cp_slice = needles.items;
    }

    // mtl.debug(@src(), "cp_slice: {any}, input: {s}", .{cp_slice, input});
    var idx: ?Index = undefined;
    if (args.cs == CaseSensitive.Yes and codepoints.len >= SimdVecLen) {
        idx = findManySimd_real(codepoints, graphemes, cp_slice, from, SimdVecLen);
    } else {
        idx = findManyLinear_real(codepoints, graphemes, cp_slice, args.from, args.cs);
    }

    if (input.len != 1)
        needles.deinit(ctx.a);

    return idx;
}

fn lastIndexGeneric_real(codepoints: ConstCpSlice, graphemes: GraphemeSlice, grapheme_count: usize, comptime T: type, needles: []const T, args: Args) ?Index {
    if (grapheme_count < needles.len) {
        return null;
    }

    if (needles.len == 1) {
        return lastIndexOfCp_real(codepoints, graphemes, grapheme_count, needles[0], args);
    }

    const from_pos = if (args.from.atZero()) codepoints.len else args.from.cp;
    if (from_pos <= needles.len) {
        return null;
    }

    const from_u = from_pos - needles.len;
    var from: isize = @intCast(from_u);
    var found = false;
    var skip_gr: usize = 0;
    const sensitive = args.cs == .Yes;
    while (from >= 0) {
        // from -= 1;
        const at: usize = @intCast(from);
        if (graphemes[at] == 1) {
            skip_gr += 1;
            found = true;
            const end: usize = at + needles.len;
            for (codepoints[at..end], needles) |cp, n| {
                const l = if (sensitive) cp else ctx.letter_casing.toUpper(cp);
                const r = if (sensitive) n else ctx.letter_casing.toUpper(n);
                if (l != r) {
                    found = false;
                    break;
                }
            }

            if (found) {
                var skipped_gr: usize = 0;
                for (graphemes[(from_u + 1)..]) |bit| {
                    if (bit == 1) {
                        skipped_gr += 1;
                    }
                }

                const new_gr = grapheme_count - skip_gr - skipped_gr;
                return Index{ .cp = at, .gr = new_gr };
            }
        }

        from -= 1;
    }

    return null;
}

fn lastIndexOfCp_real(codepoints: ConstCpSlice, graphemes: GraphemeSlice, grapheme_count: usize, needle: Codepoint, args: Args) ?Index {
    const from_pos: usize = if (args.from.atZero()) codepoints.len else args.from.cp;
    if (grapheme_count == 0 or from_pos < 1) {
        return null;
    }

    const from_u = from_pos - 1;
    var from: isize = @intCast(from_u);
    var skip_gr: usize = 0;
    const sensitive = args.cs == .Yes;
    const r = if (sensitive) needle else ctx.letter_casing.toUpper(needle);
    while (from >= 0) {
        const at: usize = @intCast(from);
        if (graphemes[at] == 1) {
            skip_gr += 1;
            const cp = codepoints[at];
            const l = if (sensitive) cp else ctx.letter_casing.toUpper(cp);
            if (l == r) {
                if (at < from_pos) { // make sure this grapheme length == 1,
                    // which is the case if it's at the end of the string
                    // or if the next grapheme bit == 1.
                    if (graphemes[at + 1] != 1) {
                        from -= 1;
                        continue;
                    }
                }
                var skipped_gr: usize = 0;
                for (graphemes[(from_u + 1)..]) |bit| {
                    if (bit == 1) {
                        skipped_gr += 1;
                    }
                }

                const new_gr = grapheme_count - skip_gr - skipped_gr;
                return Index{ .cp = at, .gr = new_gr };
            }
        }

        from -= 1;
    }

    return null;
}

fn matches_real(codepoints: ConstCpSlice, graphemes: GraphemeSlice, input: Slice, args: Args) ?Index {
    const end = args.from.cp + input.size_cp();
    if (!endsWithGrapheme(graphemes, end)) {
        return null;
    }

    const str_cps = codepoints[args.from.cp..end];
    const str_graphemes = graphemes[args.from.cp..end];
    var gr_count: usize = 0;
    const needles_cps = input.getCpSlice() orelse return null;
    const cs = args.cs == .Yes;
    for (str_cps, needles_cps, str_graphemes) |a, b, gr| {
        const a1 = if (cs) a else toLowerCp(a);
        const b1 = if (cs) b else toLowerCp(b);

        if (a1 != b1) {
            return null;
        }

        if (gr == 1)
            gr_count += 1;
    }

    return Index{ .cp = end, .gr = args.from.gr + gr_count };
}

fn matchesAscii_real(codepoints: ConstCpSlice, graphemes: GraphemeSlice, input: []const u8, args: Args) ?Index {
    const end = args.from.cp + input.len;
    const sensitive = args.cs == .Yes;
    const bit: Codepoint = ~@as(Codepoint, 32);
    for (graphemes[args.from.cp..end], codepoints[args.from.cp..end], input) |gr, cp, in| {
        const l = if (sensitive) cp else (cp & bit);
        const r = if (sensitive) in else (in & bit);
        if (gr != 1 or l != r) {
            return null;
        }
    }

    return Index{ .cp = end, .gr = args.from.gr + input.len };
}

pub fn print(self: String, src: std.builtin.SourceLocation, msg: []const u8) void {
    mtl.debug(src, "{s}{f}", .{ msg, self });
}

pub threadlocal var string_theme = Theme.Dark;
pub fn print_out(src: std.builtin.SourceLocation, msg: ?String) void {
    const info = if (msg) |s| s else String.Empty();
    mtl.debug(src, "{f}", .{info._(2)});
}

pub fn printCodepoints_real(codepoints: ConstCpSlice, graphemes: GraphemeSlice, src: std.builtin.SourceLocation,
off_by: Index) !void {
    var cp_buf: ArrayList(Codepoint) = .empty;
    defer cp_buf.deinit(ctx.a);
    const out = std.debug;

    var info = try String.FromCpGr(codepoints, graphemes);
    defer info.deinit();

    print_out(src, info);
    for (codepoints, 0..) |cp, i| {
        if (i > 255) {
            break;
        }
        const attr = if (graphemes[i] == 1) Attr.Grapheme else Attr.Codepoint;
        try cp_buf.append(ctx.a, cp);
        var cp_index: isize = @intCast(i);
        cp_index += @intCast(off_by.cp);
        try printCpBuf(out, cp_buf, cp_index, SeeAs.CodepointOnly, attr);
        cp_buf.clearRetainingCapacity();
    }
    out.print("\n", .{});
}

pub fn printGraphemes_real(codepoints: ConstCpSlice, graphemes: GraphemeSlice, src: std.builtin.SourceLocation,
    off_by: Index) !void {
    var cp_buf: ArrayList(Codepoint) = .empty;
    defer cp_buf.deinit(ctx.a);
    var gr_index: isize = -1;
    const out = std.debug;
    var info = try String.FromCpGr(codepoints, graphemes);
    defer info.deinit();

    print_out(src, info);
    for (codepoints, 0..) |cp, i| {
        if (i > 255) {
            break;
        }
        if (graphemes[i] == 1) {
            // mtl.debug(@src(), "gr_index: {}", .{gr_index});
            var final_index = gr_index;
            final_index += @intCast(off_by.gr);
            try printCpBuf(out, cp_buf, final_index, SeeAs.PartOfGrapheme, Attr.Ignore);
            gr_index += 1;
            cp_buf.clearRetainingCapacity();
        }

        try cp_buf.append(ctx.a, cp);
    }

    try printCpBuf(out, cp_buf, gr_index, SeeAs.PartOfGrapheme, Attr.Ignore);
    out.print("\n", .{});
}

