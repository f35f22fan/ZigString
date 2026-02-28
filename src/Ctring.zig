pub const Ctring = @This();
const std = @import("std");
const builtin = @import("builtin");
const unicode = std.unicode;
const ArrayList = std.ArrayList;
const HashMap = std.AutoHashMap;
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const maxInt = std.math.maxInt;

pub const io = @import("io.zig");
pub const mtl = @import("mtl.zig");

const zg_codepoint = @import("code_point");
const Graphemes = @import("Graphemes");
const LetterCasing = @import("LetterCasing");
const Normalize = @import("Normalize");
const CaseFolding = @import("CaseFolding");
const GeneralCategories = @import("GeneralCategories");

const alloc = std.testing.allocator;

pub const Cp = i22;
pub const CpSlice = []Cp;
pub const ConstCpSlice = []const Cp;
pub const Direction = enum(u8) { Forward, Back };
pub const Error = error{ Other };
const Dict = HashMap(Cp, []Cp);
pub const Charset = enum(u8) {
    Ascii,
    Unicode,
};

const Range = struct {
    start: usize = 0,
    end: usize = 0,
};

pub const CtringIterator = struct {
    str: *const Ctring,
    pos: usize,
    first_time: bool = true,
    range: Range = .{},

    pub fn New(str: *const Ctring, from: ?usize) CtringIterator {
        const pos = if (from) |i| i else 0;
        return CtringIterator{ .str = str, .pos = pos, .range = .{.start=0, .end=str.size()} };
    }

    pub fn FromView(v: *const View, from: ?usize) CtringIterator {
        const pos = if (from) |i| i+v.start else v.start;
        return CtringIterator{ .str = v.s, .pos = pos, .range = .{.start=v.start, .end=v.end} };
    }

    pub fn continueFrom(self: *CtringIterator, pos: usize) void {
        self.pos = pos;
        self.first_time = true;
    }

    pub fn go(self: *CtringIterator, dir: Direction) ?Grapheme {
        return if (dir == .Forward) self.next() else self.prev();
    }

    pub fn hasMore(self: CtringIterator, dir: Direction) bool {
        return if (dir == .Forward) self.pos + 1 < self.range.end else self.pos > self.start;
    }

    pub fn next(self: *CtringIterator) ?Grapheme {
        if (self.pos < self.range.end - 1) {
            if (self.first_time) {
                self.first_time = false;
            } else {
                self.pos += 1;
            }
            
            return self.str.at(self.pos);
        }

        return null;
    }

    pub fn nextFrom(self: *CtringIterator, pos: usize) ?Grapheme {
        self.first_time = false;
        self.pos = pos;
        return self.next();
    }

    pub fn prev(self: *CtringIterator) ?Grapheme {
        if (self.first_time) {
            self.first_time = false;
        } else {
            if (self.pos == self.range.start) {
                return null;
            }
            self.pos -= 1;
        }
        
        return self.str.at(self.pos);
    }

    pub fn prevFrom(self: *CtringIterator, pos: usize) ?Grapheme {
        self.first_time = false;
        self.pos = pos;
        return self.prev();
    }

};

const View = struct {
/// The `start` and `end` fields must contain absolute values. Thus all input
/// Range args to the methods of `View` must contain absolute values. But for
/// convenience the default constructor .{} (which is thus initialized to zeroes)
/// is interpreted as to contain the whole string.
    start: usize,
    end: usize,
    s: *const Ctring,

    pub fn afterLast(self: View) usize {
        return self.end;
    }

    pub fn endsWith(self: View, rhs: Ctring) bool {
        const rsz = rhs.size();
        if (rsz > self.size()) {
            return false;
        }

        return self.s.find(rhs, .{.start=self.end - rsz, .end=self.end}) != null;
    }

    pub fn endsWithAscii(self: View, rhs: []const u8) bool {
        const rsz = rhs.len;
        if (rsz > self.size()) {
            return false;
        }

        return self.s.findAscii(rhs, .{.start=self.end - rsz, .end=self.end}) != null;
    }

    pub fn endsWithUtf8(self: View, rhs: []const u8) bool {
        var s = Ctring.New(rhs) catch return false;
        defer s.deinit();
        return self.endsWith(s);
    }

    pub fn eq(self: View, rhs: Ctring) bool {
        if (self.size() != rhs.size()) {
            return false;
        }

        return rhs.find(self.s, self.range()) != null;
    }

    pub fn eqAscii(self: View, ascii: []const u8) bool {
        const self_len = self.end - self.start;
        if (ascii.len != self_len) {
            return false;
        }
        if (ascii.len == 0 and (self_len == 0)) {
            return true;
        }
        return self.s.eqAscii(ascii, self.range());
    }

    pub fn eqUtf8(self: View, rhs: []const u8) bool {
        var s = Ctring.New(rhs) catch return false;
        defer s.deinit();
        return s.eqView(self);
    }

    pub fn find(self: View, needles: Ctring, from: ?usize) ?usize {
        const r: Range = if (from) |f| .{.start=f, .end=self.end} else self.range();
        return self.s.find(needles, r);
    }

    pub fn findAscii(self: View, needles: []const u8, from: ?usize) ?usize {
        const r: Range = if (from) |f| .{.start=f, .end=self.end} else self.range();
        return self.s.findAscii(needles, r);
    }

    pub fn findUtf8(self: View, needles: []const u8, from: ?usize) ?usize {
        const r: Range = if (from) |f| .{.start=f, .end=self.end} else self.range();
        return self.s.findUtf8(needles, r);
    }

    pub fn format(self: *const View, writer: *std.Io.Writer) !void {
        return self._(0).format(writer);
    }

    pub fn _(self: *const View, context: i32) View_ {
        return .{ .v = self, .context = context };
    }

    pub fn iterator(self: *const View, from: ?usize) CtringIterator {
        return CtringIterator.FromView(self, from);
    }
    
    pub fn lastIndexOf(self: View, needles: Ctring) ?usize {
        return self.s.lastIndexOf(needles, self.range());
    }

    pub fn lastIndexOfAscii(self: View, needles: []const u8) ?usize {
        return self.s.lastIndexOfAscii(needles, self.range());
    }

    pub fn lastIndexOfUtf8(self: View, needles: []const u8) ?usize {
        return self.s.lastIndexOfUtf8(needles, self.range());
    }

    inline fn range(self: View) Range {
        return .{.start = self.start, .end = self.end};
    }

    pub fn setView(self: *View, start: usize, end: usize) void {
        self.start = start;
        self.end = end;
    }

    pub fn size(self: View) usize {
        return self.end - self.start;
    }

    pub fn split(self: View, sep: Ctring, keep_empty_parts: bool) !ArrayList(View) {
        var arr: ArrayList(View) = .empty;
        errdefer arr.deinit(ctx.a);
        var at_idx: usize = self.start;
        const sep_size = sep.size();
        while (at_idx < self.end) {
            const r: Range = .{.start=at_idx, .end=self.end};
            if (self.s.find(sep, r)) |idx| {
                const new_view = self.s.view(at_idx, idx);
                const is_empty = (new_view.end - new_view.start == 0);
                if (keep_empty_parts or !is_empty) {
                    try arr.append(ctx.a, new_view);
                }
                at_idx = idx + sep_size;
            } else {
                const new_view = self.s.view(at_idx, self.end);
                try arr.append(ctx.a, new_view);
                break;
            }
        }

        return arr;
    }

    pub fn splitAscii(self: View, sep: []const u8, keep_empty_parts: bool) !ArrayList(View) {
        var arr: ArrayList(View) = .empty;
        errdefer arr.deinit(ctx.a);
        var at_idx: usize = self.start;
        const sep_size = sep.len;
        while (at_idx < self.end) {
            const r: Range = .{.start=at_idx, .end=self.end};
            if (self.s.findAscii(sep, r)) |idx| {
                const new_view = self.s.view(at_idx, idx);
                const is_empty = (new_view.end - new_view.start == 0);
                if (keep_empty_parts or !is_empty) {
                    try arr.append(ctx.a, new_view);
                }
                at_idx = idx + sep_size;
            } else {
                const new_view = self.s.view(at_idx, self.end);
                try arr.append(ctx.a, new_view);
                break;
            }
        }

        return arr;
    }

    pub fn splitUtf8(self: View, sep: []const u8, keep_empty_parts: bool) !ArrayList(View) {
        var s = try Ctring.New(sep);
        defer s.deinit();
        return self.split(s, keep_empty_parts);
    }

    pub fn startsWith(self: View, needles: Ctring) bool {
        const r: Range = .{.start=self.start, .end=self.start+needles.size()};
        return self.s.find(needles, r) != null;
    }

    pub fn startsWithAscii(self: View, rhs: []const u8) bool {
        const r: Range = .{.start=self.start, .end=self.start + rhs.len};
        return self.s.findAscii(rhs, r) != null;
    }

    pub fn startsWithUtf8(self: View, rhs: []const u8) bool {
        var s = Ctring.New(rhs) catch return false;
        defer s.deinit();
        const r: Range = .{.start=self.start, .end=self.start+s.size()};
        return self.s.findUtf8(rhs, r) != null;
    }

    pub fn toBytes(self: View, a: Allocator) !ArrayList(u8) {
        return self.s.toBytes(a, self.range());
    }

    pub fn toString(self: View) !Ctring {
        return try self.s.clone(self.range());
    }

    const View_ = struct {
        context: i32,
        v: *const View,
        pub fn format(self: View_, writer: *std.Io.Writer) !void {
            if (self.v.s.data) |data_| {
                switch (data_.*) {
                    .ascii => |buf| {
                        try printBytes(buf.items[self.v.start..self.v.end], writer, self.context);
                    },
                    .utf8 => |*utf8| {
                        var buf = utf8_to_bytes(ctx.a, utf8, self.v.start, self.v.end) catch return std.Io.Writer.Error.WriteFailed;
                        defer buf.deinit(ctx.a);
                        try printBytes(buf.items, writer, self.context);
                    },
                }
            }
        }
    };
};

const Grapheme_ = struct {
    context: i32,
    gr: *const Grapheme,
    pub fn format(self: Grapheme_, writer: *std.Io.Writer) !void {
        switch (self.gr.data) {
            .ascii => |byte| {
                try printBytes(&.{byte}, writer, self.context);
            },
            .cps => |cps| {
                var buf: ArrayList(u8) = .empty;
                defer buf.deinit(ctx.a);
                var tmp: [4]u8 = undefined;
                for (cps) |cp| {
                    const c: u21 = @intCast(cp);
                    const len = unicode.utf8Encode(c, &tmp) catch return std.Io.Writer.Error.WriteFailed;
                    buf.appendSlice(ctx.a, tmp[0..len]) catch return std.Io.Writer.Error.WriteFailed;
                }
                
                try printBytes(buf.items, writer, self.context);
            },
        }
    }
};

const GrData = union(enum) {
    cps: ConstCpSlice,
    ascii: u8,
};

pub const Grapheme = struct {
    data: GrData = undefined,
    idx: usize = 0,

    pub fn NewCps(idx: usize, cps: ConstCpSlice) Grapheme {
        return .{.idx = idx, .data = GrData{.cps = cps}};
    }

    pub fn NewAscii(idx: usize, ascii: u8) Grapheme {
        return .{.idx = idx, .data = GrData{.ascii = ascii}};
    }

    pub fn eq(self: Grapheme, cp: Cp) bool {
        const my_cp = self.oneCp() orelse return false;
        return my_cp == cp;
    }

    pub fn eqUtf8(self: Grapheme, str: []const u8) bool {
        var gc_iter = ctx.graphemes.iterator(str);
        var graphemes: ArrayList(Cp) = .empty;
        defer graphemes.deinit(ctx.a);
        while (gc_iter.next()) |grapheme_bytes| {
            const bytes = grapheme_bytes.bytes(str);
            var cp_iter = zg_codepoint.Iterator{ .bytes = bytes };
            while (cp_iter.next()) |obj| {
                graphemes.append(ctx.a, obj.code) catch return false;
            }
        }

        switch (self.data) {
            .ascii => |ascii| {
                if (graphemes.items.len > 1) {
                    return false;
                }
                return graphemes.items[0] == ascii;
            },
            .cps => |cps| {
                return std.mem.eql(Cp, cps, graphemes.items);
            },
        }
    }

    pub fn format(self: *const Grapheme, writer: *std.Io.Writer) !void {
        return self._(0).format(writer);
    }

    pub fn _(self: *const Grapheme, context: i32) Grapheme_ {
        return .{ .gr = self, .context = context };
    }

    fn isAsciiAWordChar(cp: Cp) bool {
        return (cp >= 'A' and cp <= 'Z') or (cp >= 'a' and cp <= 'z') or
            (cp >= '0' and cp <= '9') or (cp == '_');
    }

    pub fn isWordChar(self: Grapheme, charset: Charset) bool {
        const cp = self.oneCp() orelse return false;
        const ascii_match = isAsciiAWordChar(cp);

        if (charset == .Ascii) {
            return ascii_match;
        }

        return ascii_match or ctx.gencat.isLetter(cp);
    }

    pub fn isDigit(self: Grapheme) bool {
        const cp = self.oneCp() orelse return false;
        return cp >= '0' and cp <= '9';
    }

    pub fn isWhitespace(self: Grapheme) bool {
        const cp = self.oneCp() orelse return false;
        return cp == ' ' or cp == '\t' or cp == '\n' or cp == '\r';
    }

    inline fn oneCp(self: Grapheme) ?Cp {
        switch(self.data) {
            .cps => |cps| {
                if (cps.len == 1) {
                    return cps[0];
                }
            },
            .ascii => |ascii| {
                return ascii;
            },
        }
        return null;
    }

    pub fn toBytes(self: Grapheme, a: Allocator, result: *ArrayList(u8)) !void {
        switch (self.gr.data) {
            .ascii => |byte| {
                try result.append(a, byte);
            },
            .cps => |cps| {
                var tmp: [4]u8 = undefined;
                for (cps) |cp| {
                    const c: u21 = @intCast(cp);
                    const len = try unicode.utf8Encode(c, &tmp);
                    try result.appendSlice(a, tmp[0..len]);
                }
            },
        }
    }
};

const Utf8 = struct {
    arr: ArrayList(Cp) = .empty,
    dict: ?*Dict = null,

    inline fn dictMut(self: *Utf8) !*Dict {
        if (self.dict) |d| {
            return d;
        }
        const d = try ctx.a.create(Dict);
        d.* = .init(ctx.a);
        self.dict = d;
        return d;
    }

    pub fn addAscii(self: *Utf8, arr: []const u8) !void {
        const slice = try self.arr.addManyAsSlice(ctx.a, arr.len);
        for (slice, arr) |*a, b| {
            a.* = b;
        }
    }

    pub fn addUtf(self: *Utf8, rhs: *const Utf8) !void {
        const offset: usize = self.arr.items.len;
        try self.arr.appendSlice(ctx.a, rhs.arr.items);

        const rdict = rhs.dict orelse return;
        for (self.arr.items[offset..]) |*cp| {
            if (cp.* < 0) {
                const gr = rdict.get(cp.*) orelse unreachable;
                const new_id = try self.addGraphemeCluster(gr);
                cp.* = new_id;
            }
        }
    }

    pub fn addGraphemeCluster(self: *Utf8, gr: []const Cp) !Cp {
        var dict = try self.dictMut();
        // dict.count() + 1 is needed to have -id always be a negative number,
        // because when it's zero it doesn't turn into a negative number.
        // Which is how an ID id distinguished for a regular Codepoint.
        const id: Cp = @intCast(dict.count() + 1);
        var iter = dict.iterator();
        while (iter.next()) |entry| {
            const slice = entry.value_ptr.*;
            if (std.mem.eql(Cp, slice, gr)) {
                // mtl.debug(@src(), "slices equal: {any} vs {any}", .{slice, gr});
                return entry.key_ptr.*;
            }
        }

        const sl = try ctx.a.dupe(Cp, gr);
        try dict.put(-id, sl);
        
        return -id;
    }

    pub fn clone(self: Utf8, range: Range) !Utf8 {
        const end = if (range.end == 0) self.arr.items.len else range.end;
        var utf: Utf8 = .{};
        try utf.arr.appendSlice(ctx.a, self.arr.items[range.start..end]);
        if (self.dict) |source| {
            const dict = try utf.dictMut();
            // dict.* = try source.clone() segfaults at dict.deinit(),
            // thus copy dict by hand.
            var iter = source.iterator();
            while (iter.next()) |entry| {
                const val = try ctx.a.dupe(Cp, entry.value_ptr.*);
                try dict.put(entry.key_ptr.*, val);
            }
            
        }

        return utf;
    }

    pub fn findAscii(self: Utf8, needles: []const u8, range: Range) ?usize {
        const haystack = self.arr.items[range.start..range.end];
        for (0..haystack.len) |i| {
            if (needles.len > haystack[i..].len) {
                return null;
            }
            
            var equals = true;
            for (haystack[i..i + needles.len], needles) |cp, b| {
                if (cp != b) {
                    equals = false;
                    break;
                }
            }

            if (equals) {
                return i + range.start;
            }
        }

        return null;
    }

    pub fn find(self: Utf8, needles_utf: Utf8, source_range: Range, needle_range: ?Range) ?usize {
        const haystack = self.arr.items[source_range.start..source_range.end];
        var n_start: usize = 0;
        var n_end: usize = needles_utf.arr.items.len;
        if (needle_range) |r| {
            n_start = r.start;
            n_end = r.end;
        }
        const needles = needles_utf.arr.items[n_start..n_end];
        
        for (0..haystack.len) |i| {
            if (needles.len > haystack[i..].len) {
                return null;
            }
            
            var equals = true;
            for (haystack[i..i+needles.len], needles) |cp, rcp| {
                if (cp < 0 or rcp < 0) {
                    if (cp >= 0 or rcp >= 0) {
                        equals = false;
                        break;
                    }
                    const dict = self.dict orelse return null;
                    const rdict = needles_utf.dict orelse return null;
                    const sl1 = dict.get(cp) orelse return null;
                    const sl2 = rdict.get(rcp) orelse return null;
                    if (!std.mem.eql(Cp, sl1, sl2)) {
                        equals = false;
                        break;
                    }
                } else if (cp != rcp) {
                    equals = false;
                    break;
                }
            }

            if (equals) {
                return i + source_range.start;
            }
        }

        return null;
    }

    pub fn getGrapheme(self: *Utf8, idx: usize) ?Grapheme {
        if (idx >= self.arr.items.len) {
            return null;
        }
        const id = self.arr.items[idx];
        if (id >= 0) {
            return .NewCps(idx, self.arr.items[idx..idx+1]);
        }
        var dict = self.dict orelse return null;
        return .NewCps(idx, dict.get(id) orelse return null);
    }
};

const Ctring_ = struct {
    context: i32,
    s: *const Ctring,
    pub fn format(self: Ctring_, writer: *std.Io.Writer) !void {
        if (self.s.data) |data_| {
            switch (data_.*) {
                .ascii => |buf| {
                    try printBytes(buf.items, writer, self.context);
                },
                .utf8 => |*utf8| {
                    var buf = utf8_to_bytes(ctx.a, utf8, 0, utf8.arr.items.len) catch return std.Io.Writer.Error.WriteFailed;
                    defer buf.deinit(ctx.a);
                    try printBytes(buf.items, writer, self.context);
                },
            }
        }
    }
};

const Data = union(enum) {
    utf8: Utf8,
    ascii: ArrayList(u8),
};

data: ?*Data = null,

pub const Context = struct {
    a: Allocator = undefined,
    graphemes: Graphemes,
    letter_casing: LetterCasing = undefined,
    case_folding: CaseFolding = undefined,
    normalize: Normalize = undefined,
    gencat: GeneralCategories = undefined,

    pub fn New(a: Allocator) !Context {
        const normalize = try Normalize.init(a);
        var context = Context{
            .a = a,
            .graphemes = try Graphemes.init(a),
            .letter_casing = try LetterCasing.init(a),
            .normalize = normalize,
            .case_folding = try CaseFolding.initWithNormalize(a, normalize),
            .gencat = try GeneralCategories.init(a),
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

pub fn New(input: []const u8) !Ctring {
    var result = try init();
    const data = try result.dataMut();
    var gc_iter = ctx.graphemes.iterator(input);
    var grapheme: ArrayList(Cp) = .empty;
    defer grapheme.deinit(ctx.a);
    var utf8: Utf8 = .{};
    while (gc_iter.next()) |grapheme_bytes| {
        const bytes = grapheme_bytes.bytes(input);
        var cp_iter = zg_codepoint.Iterator{ .bytes = bytes };
        grapheme.clearRetainingCapacity();
        while (cp_iter.next()) |obj| {
            try grapheme.append(ctx.a, obj.code);
        }

        if (grapheme.items.len == 1) {
            try utf8.arr.append(ctx.a, grapheme.items[0]);
        } else {
            const id = try utf8.addGraphemeCluster(grapheme.items);
            try utf8.arr.append(ctx.a, id);
        }
    }

    data.* = Data {.utf8 = utf8};

    return result;
}

pub threadlocal var ctx: Context = undefined;
pub fn Init(a: Allocator) !void {
    Ctring.ctx = try Context.New(a);
}

pub fn Deinit() void {
    Ctring.ctx.deinit();
}

pub fn empty() Ctring {
    return Ctring{};
}

inline fn init() !Ctring {
    const data = try alloc.create(Data);
    return Ctring {.data = data};
}

pub fn deinit(self: *Ctring) void {
    if (self.data) |d| {
        switch (d.*) {
            .ascii => |*arr| arr.deinit(ctx.a),
            .utf8 => |*utf8| {
                utf8.arr.deinit(ctx.a);
                if (utf8.dict) |dict_| {
                    var iter = dict_.iterator();
                    while (iter.next()) |entry| {
                        const memory = entry.value_ptr.*;
                        ctx.a.free(memory);
                    }
                    dict_.deinit();
                    ctx.a.destroy(dict_);
                }
            }
        }

        alloc.destroy(d);
    }
}

pub fn Ascii(s: []const u8) !Ctring {
    var arr: ArrayList(u8) = .empty;
    try arr.appendSlice(alloc, s);
    const result = try init();
    if (result.data) |data_| {
        data_.* = Data {.ascii = arr};
    }

    return result;
}

pub fn add(self: *Ctring, rhs: Ctring) !void {
    const rdata = rhs.data orelse return;
    if (!rhs.isAscii() and self.isAscii()) {
        try self.switchToUtf();
    }
    const data = try self.dataMut();
    switch (data.*) {
        .utf8 => |*utf8| {
            switch (rdata.*) {
                .utf8 => |*rutf8| {
                    try utf8.addUtf(rutf8);
                },
                .ascii => |*rascii| {
                    try utf8.addAscii(rascii.items);
                }
            }
        },
        .ascii => |*ascii| {
            switch (rdata.*) {
                .ascii => |*rascii| {
                    try ascii.appendSlice(ctx.a, rascii.items);
                },
                else => unreachable,
            }
        }
    }
}

pub fn addAscii(self: *Ctring, rhs: []const u8) !void {
    const data = try self.dataMut();
    switch (data.*) {
        .utf8 => |*utf| {
            try utf.addAscii(rhs);
        },
        .ascii => |*ascii| {
            try ascii.appendSlice(ctx.a, rhs);
        }
    }
}

pub fn addUtf8(self: *Ctring, rhs: []const u8) !void {
    var s = try Ctring.New(rhs);
    defer s.deinit();
    return self.add(s);
}

pub inline fn afterLast(self: Ctring) usize {
    return self.size();
}

pub fn at(self: Ctring, index: usize) ?Grapheme {
    const data = self.data orelse return null;
    switch (data.*) {
        .ascii => |*arr| {
            if (index < arr.items.len) {
                return .NewAscii(index, arr.items[index]);
            }
        },
        .utf8 => |*utf8| {
            return utf8.getGrapheme(index);
        }
    }

    return null;
}

const ChangeCase = enum(u8) {
    toLower,
    toUpper
};

pub fn changeCase(self: *Ctring, change: ChangeCase) void {
    const data = self.data orelse return;
    switch (data.*) {
        .ascii => |*ascii| {
            for (ascii.items) |*byte| {
                if (change == .toLower) {
                    byte.* |= @as(u8, 32);
                } else {
                    byte.* &= ~@as(u8, 32);
                }
            }
        },
        .utf8 => |*utf| {
            for (utf.arr.items) |*cp| {
                if (cp.* >= 0) {
                    const n: u21 = @intCast(cp.*);
                    cp.* = ctx.letter_casing.toLower(n);
                }
            }

            if (utf.dict) |dict_|{
                var iter = dict_.iterator();
                while (iter.next()) |entry| {
                    var slice = entry.value_ptr.*;
                    for (0..slice.len) |i| {
                        const n: u21 = @intCast(slice[i]);
                        var n2: u21 = undefined;
                        if (change == .toLower) {
                            n2 = ctx.letter_casing.toLower(n);
                        } else {
                            n2 = ctx.letter_casing.toUpper(n);
                        }
                        slice[i] = n2;
                    }
                }
            }
        }
    }
}

pub fn clone(self: Ctring, range: Range) !Ctring {
    const end = if (range.end == 0) self.afterLast() else range.end;
    const data = self.data orelse return error.Other;

    switch (data.*) {
        .ascii => |ascii| {
            mtl.debug(@src(), "range:{}-{}", .{range.start, end});
            return Ctring.Ascii(ascii.items[range.start..end]);
        },
        .utf8 => |utf| {
            var result = try Ctring.init();
            errdefer result.deinit();
            const rdata = try result.dataMut();
            rdata.* = Data {.utf8 = try utf.clone(range)};
            return result;
        }
    }
}

inline fn dataMut(self: *Ctring) !*Data {
    if (self.data) |d| {
        return d;
    }

    const data = try alloc.create(Data);
    self.data = data;
    return data;
}

pub fn codepointCount(self: Ctring) usize {
    const data = self.data orelse return 0;
    var count: usize = 0;
    switch (data.*) {
        .ascii => |*ascii| return ascii.items.len,
        .utf8 => |*utf8| {
            for (utf8.arr.items) |cp| {
                if (cp >= 0) {
                    count += 1;
                } else {
                    if (utf8.dict) |d| {
                        if (d.get(cp)) |slice| {
                            count += slice.len;
                        }
                    }
                }
            }
        }
    }

    return count;
}

pub fn complexGraphemeCount(self: Ctring) usize {
    const data = self.data orelse return 0;
    switch (data.*) {
        .utf8 => |*utf8| {
            var count: usize = 0;
            for (utf8.arr.items) |cp| {
                if (cp < 0) {
                    count += 1;
                }
            }

            return count;
        },
        else => {},
    }

    return 0;
}

pub fn dictSize(self: Ctring) usize {
    if (self.data) |data_| {
        switch (data_.*) {
            .utf8 => |*utf8| {
                if (utf8.dict) |dict_| {
                    return dict_.count();
                }
            },
            else => {},
        }
    }

    return 0;
}
const CpsToTrim = [_]Cp{ ' ', '\t', '\n', '\r' };
fn dropLeft(T: type, arr: *ArrayList(T)) void {
    var drop: usize = 0;
    for (arr.items) |byte| {
        if (std.mem.indexOfScalar(Cp, &CpsToTrim, byte)) |index| {
            _ = index;
            drop += 1;
        } else {
            break;
        }
    }

    if (drop > 0) {
        const new_items: []const T = &[_]T{};
        arr.replaceRange(ctx.a, 0, drop, new_items) catch {};
    }
}

fn dropRight(T: type, arr: *ArrayList(T)) void {
    var at_idx = arr.items.len;
    var drop_from: usize = at_idx;
    while (at_idx > 0) {
        at_idx -= 1;
        const cp = arr.items[at_idx];
        if (std.mem.indexOfScalar(Cp, &CpsToTrim, cp)) |index| {
            _ = index;
            drop_from = at_idx;
        } else {
            break;
        }
    }

    if (drop_from < arr.items.len) {
        arr.shrinkAndFree(ctx.a, drop_from);
    }
}

pub fn endsWith(self: Ctring, rhs: Ctring) bool {
    const rsz = rhs.size();
    const sz = self.size();
    if (rsz > sz) {
        return false;
    }
    return self.find(rhs, .{.start=sz-rsz, .end=sz}) != null;
}

pub fn endsWithAscii(self: Ctring, rhs: []const u8) bool {
    const sz = self.size();
    return self.findAscii(rhs, .{.start=sz - rhs.len, .end=sz}) != null;
}

pub fn endsWithUtf8(self: Ctring, rhs: []const u8) bool {
    var s = Ctring.New(rhs) catch return false;
    defer s.deinit();
    return self.endsWith(s);
}

pub fn eq(self: Ctring, rhs: Ctring, range: Range) bool {
    const end = if (range.end == 0) self.afterLast() else range.end;
    if (end - range.start != rhs.size()) {
        return false;
    }

    return self.find(rhs, .{.start = range.start, .end=end}) != null;
}

pub fn eqAscii(self: Ctring, rhs: []const u8, range: Range) bool {
    const start = range.start;
    const end = if (range.end == 0) self.afterLast() else range.end;
    if (end - start != rhs.len) {
        return false;
    }

    const data = self.data orelse return false;
    switch (data.*) {
        .ascii => |ascii| {
            const slice = ascii.items[start..end];
            return std.mem.eql(u8, slice, rhs);
        },
        .utf8 => |utf| {
            return utf.findAscii(rhs, .{.start=start, .end=end}) != null;
        }
    }
}

pub fn eqUtf8(self: Ctring, rhs: []const u8, range: Range) bool {
    var s = Ctring.New(rhs) catch return false;
    defer s.deinit();
    
    return self.eq(s, range);
}

pub fn eqView(self: Ctring, rhs: View) bool {
    if (self.size() != rhs.size()) {
        return false;
    }

    return self.findView(rhs, .{}) != null;
}

fn findUtfInAscii(heap_slice: []const u8, utf: Utf8, utf_range: Range) ?usize {
    const end = if (utf_range.end == 0) utf.arr.items.len else utf_range.end;
    const utf_slice = utf.arr.items[utf_range.start..end];
    const needles_len = utf_slice.len;
    for (0..heap_slice.len) |i| {
        if (needles_len > heap_slice[i..].len) {
            // mtl.debug(@src(), "{s} vs {any}, utf.arr.len:{}",
            // .{heap_slice[i..], utf_slice, utf.arr.items.len});
            return null;
        }

        var equals = true;
        for (heap_slice[i..i + needles_len], utf_slice) |b, cp| {
            if (cp < 0 or cp != b) {
                equals = false;
                break;
            }
        }

        if (equals) {
            return i;
        }
    }

    mtl.trace(@src());
    return null;
}

pub fn find(self: Ctring, needle: Ctring, range: Range) ?usize {
    const data = self.data orelse return null;
    const rdata = needle.data orelse return null;
    const start = range.start;
    const end = if (range.end == 0) self.size() else range.end;
    if (end - start < needle.size()) {
        return null;
    }
    switch (data.*) {
        .ascii => |ascii| {
            switch (rdata.*) {
                .ascii => |rascii| {
                    return std.mem.indexOf(u8, ascii.items[start..end], rascii.items);
                },
                .utf8 => |rutf| {
                    return findUtfInAscii(ascii.items[start..end], rutf, .{});
                }
            }
        },
        .utf8 => |utf| {
            switch (rdata.*) {
                .ascii => |rascii| {
                    const heap_range = Range {.start = start, .end = end};
                    return utf.findAscii(rascii.items, heap_range);
                },
                .utf8 => |rutf| {
                    const source_range: Range = .{.start = start, .end = end};
                    return utf.find(rutf, source_range, null);
                }
            }
        }
    }

    return null;
}

pub fn findAscii(self: Ctring, needles:[]const u8, range: Range) ?usize {
    const data = self.data orelse return null;
    const start = range.start;
    const end = if (range.end == 0) self.size() else range.end;
    if (end - start < needles.len) {
        return null;
    }
    switch (data.*) {
        .ascii => |ascii| {
            return std.mem.indexOf(u8, ascii.items[start..end], needles);
        },
        .utf8 => |utf| {
            const haystack_range = Range {.start = start, .end = end};
            return utf.findAscii(needles, haystack_range);
        }
    }

    return null;
}

pub fn findUtf8(self: Ctring, needles:[]const u8, range: Range) ?usize {
    var s = Ctring.New(needles) catch return null;
    defer s.deinit();
    return self.find(s, range);
}

pub fn findView(self: Ctring, needle: View, range: Range) ?usize {
    const data = self.data orelse return null;
    const rdata = needle.s.data orelse return null;
    const start = range.start;
    const end = if (range.end == 0) self.afterLast() else range.end;
    switch (data.*) {
        .ascii => |ascii| {
            switch (rdata.*) {
                .ascii => |rascii| {
                    const slice = rascii.items[needle.start..needle.end];
                    return std.mem.indexOf(u8, ascii.items[start..end], slice);
                },
                .utf8 => |rutf| {
                    const r: Range = .{.start=needle.start, .end=needle.end};
                    return findUtfInAscii(ascii.items[start..end], rutf, r);
                }
            }
        },
        .utf8 => |utf| {
            switch (rdata.*) {
                .ascii => |rascii| {
                    const slice = rascii.items[needle.start..needle.end];
                    const heap_range = Range {.start = start, .end = end};
                    return utf.findAscii(slice, heap_range);
                },
                .utf8 => |rutf| {
                    const source_range: Range = .{.start = start, .end = end};
                    return utf.find(rutf, source_range, needle.range());
                }
            }
        }
    }

    return null;
}

pub fn iterator(self: *Ctring, from: ?usize) CtringIterator {
    return CtringIterator.New(self, from);
}

inline fn isAscii(self: Ctring) bool {
    if (self.data) |data_| {
        switch (data_.*) {
            .ascii => return true,
            else => {},
        }
    }

    return false;
}

pub fn last(self: Ctring) usize {
    const sz = self.size();
    return if (sz == 0) 0 else sz - 1;
}

pub fn lastIndexOf(self: Ctring, needles: Ctring, range: Range) ?usize {
    const sz = self.size();
    const end = if (range.end == 0) sz else range.end;
    const rsz = needles.size();
    if (end == 0 or rsz == 0 or rsz > end) {
        return null;
    }

    const data = self.data orelse unreachable;
    const rdata = needles.data orelse unreachable;
    var pos: usize = end - rsz + 1;
    switch (data.*) {
        .ascii => |ascii| {
            switch (rdata.*) {
                .ascii => |rascii| {
                    const slice2 = rascii.items[0..];
                    while (pos > 0) {
                        pos -= 1;
                        const slice1 = ascii.items[pos..pos+rsz];
                        if (std.mem.eql(u8, slice1, slice2)) {
                            return pos;
                        }
                    }
                    return null;
                },
                .utf8 => |rutf| {
                    const rutf_range: Range = .{.start = 0, .end=rsz};
                    while (pos > 0) {
                        pos -= 1;
                        const slice1 = ascii.items[pos..pos+rsz];
                        if (rutf.findAscii(slice1, rutf_range)) |_| {
                            return pos;
                        }
                    }
                }
            }
        },
        .utf8 => |utf| {
            switch (rdata.*) {
                .ascii => |rascii| {
                    const rslice = rascii.items[0..];
                    while (pos > 0) {
                        pos -= 1;
                        const r: Range = .{.start=pos, .end=pos+rsz};
                        if (utf.findAscii(rslice, r)) |_| {
                            return pos;
                        }
                    }
                },
                .utf8 => |rutf| {
                    while (pos > 0) {
                        pos -= 1;
                        const r: Range = .{.start=pos, .end=pos+rsz};
                        if (utf.find(rutf, r, null)) |_| {
                            return pos;
                        }
                    }
                }
            }
        }
    }

    return null;
}

pub fn lastIndexOfAscii(self: Ctring, needles: []const u8, range: Range) ?usize {
    const sz = self.size();
    const end = if (range.end == 0) sz else range.end;
    const rsz = needles.len;
    if (end == 0 or rsz == 0 or rsz > end) {
        return null;
    }

    const data = self.data orelse unreachable;
    var pos: usize = end - needles.len + 1;
    switch (data.*) {
        .ascii => |ascii| {
            while (pos > 0) {
                pos -= 1;
                const slice = ascii.items[pos..pos+rsz];
                if (std.mem.eql(u8, slice, needles)) {
                    return pos;
                }
            }
        },
        .utf8 => |utf| {
            while (pos > 0) {
                pos -= 1;
                const r: Range = .{.start=pos, .end=pos+rsz};
                if (utf.findAscii(needles, r)) |_| {
                    return pos;
                }
            }
        }
    }

    return null;
}

pub fn lastIndexOfUtf8(self: Ctring, needles: []const u8, range: Range) ?usize {
    var s = Ctring.New(needles) catch return null;
    defer s.deinit();
    return self.lastIndexOf(s, range);
}

pub fn printStats(self: Ctring, src: std.builtin.SourceLocation) void {
    const used_memory = self.usedMemory();
    const used_mem: f128 = @floatFromInt(used_memory);
    const gr_count: f128 = @floatFromInt(self.size());
    const bytes_per_grapheme = used_mem / gr_count;
    
    const max: usize = @min(36, self.size());
    var grapheme: ArrayList(Cp) = .empty;
    defer grapheme.deinit(ctx.a);

    if (self.size() <= max) {
        mtl.debug(src, "{f} [STATS]:", .{self._(2)});
    }

    std.debug.print("Graphemes:{}(complex:{}) cps:{} dict.count:{} memory:{} bytes_per_gr:{d:.2}\n",
        .{self.size(), self.complexGraphemeCount(), self.codepointCount(), self.dictSize(), used_memory, bytes_per_grapheme});
    
    std.debug.print("[", .{});
    for (0..max) |i| {
        const gr = self.at(i) orelse break;
        switch (gr.data) {
            .cps => |cps| {
                grapheme.appendSlice(ctx.a, cps) catch return;
            },
            .ascii => |byte| {
                grapheme.append(ctx.a, byte) catch return;
            }
        }
        
        for (grapheme.items, 0..) |cp, n| {
            std.debug.print("{X}", .{cp});
            if (n < grapheme.items.len-1) {
                std.debug.print("_", .{});
            }
        }
        
        std.debug.print("{f} ", .{gr._(2)});
        grapheme.clearRetainingCapacity();
        if (i < max-1) {
            std.debug.print(" ", .{});
        }
    }

    std.debug.print("]\n", .{});
}

pub fn size(self: Ctring) usize {
    var count: usize = 0;
    if (self.data) |data_| {
        count = switch (data_.*) {
            .utf8 => |*utf8| utf8.arr.items.len,
            .ascii => |arr| arr.items.len,
        };
    }
    
    return count;
}

pub fn switchToUtf(self: *Ctring) !void {
    const data = try self.dataMut();
    var utf8: Utf8 = .{};
    switch (data.*) {
        .ascii => |*ascii| {
            try utf8.addAscii(ascii.items);
            ascii.deinit(ctx.a);
        },
        .utf8 => return,
    }

    data.* = Data {.utf8 = utf8};
}

pub fn startsWith(self: Ctring, needles: Ctring) bool {
    if (needles.size() > self.size()) {
        return false;
    }

    return self.find(needles, .{.start=0, .end=needles.size()}) != null;
}

pub fn startsWithAscii(self: Ctring, needles: []const u8) bool {
    if (needles.len > self.size()) {
        return false;
    }

    return self.findAscii(needles, .{.start=0, .end=needles.len}) != null;
}

pub fn startsWithUtf8(self: Ctring, needles: []const u8) bool {
    var s = Ctring.New(needles) catch return false;
    defer s.deinit();
    return self.find(s, .{.start=0, .end=s.size()}) != null;
}

pub fn toBytes(self: Ctring, a: Allocator, range: Range) !ArrayList(u8) {
    const data = self.data orelse return error.Other;
    switch (data.*) {
        .ascii => |*ascii| {
            const end = if (range.end == 0) ascii.items.len else range.end;
            var ret: ArrayList(u8) = .empty;
            try ret.appendSlice(ctx.a, ascii.items[range.start..end]);
            return ret;
        },
        .utf8 => |*utf8| {
            const end = if (range.end == 0) utf8.arr.items.len else range.end;
            return utf8_to_bytes(a, utf8, range.start, end);
        }
    }
    
    return .empty;
}

pub fn toLower(self: *Ctring) void {
    self.changeCase(.toLower);
}

pub fn toUpper(self: *Ctring) void {
    self.changeCase(.toUpper);
}

pub fn trim(self: *Ctring) void {
    self.trimLeft();
    self.trimRight();
}

pub fn trimLeft(self: *Ctring) void {
    const data = self.data orelse return;
    switch (data.*) {
        .ascii => |*ascii| {
            dropLeft(u8, ascii);
        },
        .utf8 => |*utf| {
            dropLeft(Cp, &utf.arr);
        }
    }
}

pub fn trimRight(self: *Ctring) void {
    const data = self.data orelse return;
    switch (data.*) {
        .ascii => |*ascii| {
            dropRight(u8, ascii);
        },
        .utf8 => |*utf| {
            dropRight(Cp, &utf.arr);
        }
    }
}

pub fn usedMemory(self: Ctring) usize {
    const data = self.data orelse return 0;
    switch (data.*) {
        .ascii => |*ascii| return ascii.items.len,
        .utf8 => |*utf8| {
            var count = utf8.arr.items.len * 3; // Cp = 3 bytes
            if (utf8.dict) |dict| {
                var iter = dict.iterator();
                while (iter.next()) |entry| {
                    count += 3; // sizeof(Cp)
                    const sl = entry.value_ptr.*;
                    count += sl.len * 3;
                }
            }

            return count;
        },
    }
}

fn utf8_to_bytes(a: Allocator, utf8: *Utf8, start: usize, end: usize) !ArrayList(u8) {
    var buf: ArrayList(u8) = .empty;
    errdefer buf.deinit(a);
    var tmp: [4]u8 = undefined;
    for (utf8.arr.items[start..end]) |cp| {
        if (cp >= 0) {
            const c: u21 = @intCast(cp);
            const len = try unicode.utf8Encode(c, &tmp);
            try buf.appendSlice(a, tmp[0..len]);
        } else {
            var dict = try utf8.dictMut();
            const val = dict.get(cp) orelse return error.Other;
            for (val) |next_cp| {
                const c: u21 = @intCast(next_cp);
                const len = try unicode.utf8Encode(c, &tmp);
                try buf.appendSlice(a, tmp[0..len]);
            }
        }
    }

    return buf;
}

fn cps_to_bytes(cps: ConstCpSlice) !ArrayList(u8) {
    var buf: ArrayList(u8) = .empty;
    errdefer buf.deinit(ctx.a);
    var tmp: [4]u8 = undefined;
    for (cps) |cp| {
        if (cp >= 0) {
            const c: u21 = @intCast(cp);
            const len = try unicode.utf8Encode(c, &tmp);
            try buf.appendSlice(ctx.a, tmp[0..len]);
        }
    }

    return buf;
}

pub fn view(self: *const Ctring, start: usize, end: usize) View {
    return View {.s = self, .start = start, .end = end};
}

pub fn format(self: *const Ctring, writer: *std.Io.Writer) !void {
    return self._(0).format(writer);
}

pub fn _(self: *const Ctring, context: i32) Ctring_ {
    return .{ .s = self, .context = context };
}

pub fn printBytes(buf: []const u8, writer: *std.Io.Writer, context: i32) !void {
    const fmtstr = "{s}{s}{s}{s}{s}";

    if (context == 1) { // colored
        try writer.print(fmtstr, .{ mtl.COLOR_YELLOW, mtl.BGCOLOR_BLACK, buf, mtl.BGCOLOR_DEFAULT, mtl.COLOR_DEFAULT });
    } else if (context == 2) { // highlighted
        try writer.print(fmtstr, .{ mtl.COLOR_BLACK, mtl.BGCOLOR_YELLOW, buf, mtl.BGCOLOR_DEFAULT, mtl.COLOR_DEFAULT });
    } else { // no color, default
        try writer.print("{s}", .{buf});
    }
}

fn analyze(fullpath: []const u8) !void {
    var arr = try io.readFileUtf8(alloc, fullpath);
    defer arr.deinit(alloc);
    var s = try Ctring.New(arr.items);
    defer s.deinit();
    s.printStats(@src());
}

// Don't change this string, many tests depend on it:
const JoseBytes = "Jos\u{65}\u{301} se fu\u{65}\u{301} a Sevilla sin pararse";

test "Equals, Iteration" {
    try Ctring.Init(alloc);
    defer Ctring.Deinit();

    {
        var top = try Ctring.New("🧑‍🌾 橋 5b");
        defer top.deinit();

        {
            var v = top.view(0, 3);
            try expect(v.eqUtf8("🧑‍🌾 橋"));
            v.setView(4, 6);
            try expect(v.eqAscii("5b"));

            v.setView(0, 6);
            try expect(v.startsWith(top));
            try expect(v.startsWithUtf8("🧑‍🌾 橋"));
            
            v.setView(3, 6);
            try expect(v.startsWithAscii(" 5"));

            v.setView(0, 6);
            var end = try Ctring.Ascii("5b");
            defer end.deinit();
            try expect(v.endsWith(end));

            var end2 = try Ctring.New("橋 5b");
            defer end2.deinit();
            try expect(v.endsWith(end2));

            try expect(v.endsWithAscii("5b"));
            try expect(v.endsWithUtf8("橋 5b"));
        }

        {
            try expect(top.startsWithUtf8("🧑‍🌾 "));
            var s = try Ctring.New("🧑‍🌾 ");
            defer s.deinit();
            try expect(top.startsWith(s));
            try expect(top.endsWithUtf8("橋 5b"));
            var end = try Ctring.New("橋 5b");
            defer end.deinit();
            try expect(top.endsWith(end));
        }
        
        if (true) {
            {
                const correct = [_][]const u8 {"🧑‍🌾", " ", "橋", " ", "5", "b"};
                var iter = top.iterator(0);
                var idx: usize = 0;
                while (iter.next()) |gr| {
                    try expect(gr.eqUtf8(correct[idx]));
                    idx += 1;
                }
            }
            {
                const correct = [_][]const u8 {"橋", " ", "5", "b"};
                var iter = top.view(1, top.size()).iterator(1);
                var idx: usize = 0;
                while (iter.next()) |gr| {
                    try expect(gr.eqUtf8(correct[idx]));
                    idx += 1;
                }
            }
        }

        if (true) {
            const correct = [_][]const u8 {"b", "5", " ", "橋", " ", "🧑‍🌾"};
            var iter = top.iterator(top.last());
            var idx: usize = 0;
            while (iter.prev()) |gr| {
                try expect(gr.eqUtf8(correct[idx]));
                idx += 1;
            }
        }

        if (true) {
            var abc = try Ctring.New("abc");
            defer abc.deinit();
            try expect(abc.eqAscii("abc", .{}));

            var def = try Ctring.Ascii("def");
            defer def.deinit();
            try expect(def.eqAscii("def", .{}));
            try expect(def.startsWithAscii("de"));
            try expect(def.startsWithUtf8("de"));
            var de = try Ctring.New("de");
            defer de.deinit();
            try expect(def.startsWith(de));
            try expect(def.endsWithAscii("ef"));

        }

        var thai = try Ctring.New("“मनीष”");
        defer thai.deinit();
        {
            var cloned = try thai.clone(.{.start = 2, .end = 3});
            defer cloned.deinit();
            const my_view = thai.view(2, 3);
            try expect(cloned.eqView(my_view));
            try expect(thai.eqUtf8("“मनीष”", .{}));
            var converted = try my_view.toString();
            defer converted.deinit();
            try expect(converted.eqUtf8("नी", .{}));
            var arr = try my_view.toBytes(alloc);
            defer arr.deinit(alloc);
            try expect(std.mem.eql(u8, arr.items, "नी"));
        }
    }

    //﷽
    // mtl.debug(@src(), "Data:{} Ctring:{} Grapheme:{}", .{@sizeOf(Data), @sizeOf(Ctring), @sizeOf(Grapheme)} );

    // try analyze("/home/fox/Text/Chinese.txt");
    // try analyze("/home/fox/Text/Chinese2.txt");
    // try analyze("/home/fox/Text/English.txt");
    // try analyze("/home/fox/Text/Thai.txt");
}

test "Find" {
    try Ctring.Init(alloc);
    defer Ctring.Deinit();

    var top = try Ctring.New("🧑‍🌾 .橋 .5b.橋");
    defer top.deinit();
    {
        var ascii = try Ctring.Ascii("Hello");
        defer ascii.deinit();
        ascii.toUpper();
        ascii.toLower();
        
        var needles = try Ctring.New("lo");
        defer needles.deinit();
        try expect(ascii.find(needles, .{}) == 3);
        try expect(ascii.find(needles, .{.end=ascii.afterLast()}) == 3);

        const v = top.view(0, top.size());
        try expect(v.findAscii(".", null) == 2);
        try expect(v.findAscii(".", 3) == 5);
        try expect(v.findUtf8("橋", null) == 3);
        try expect(v.findUtf8(".橋", null) == 2);
        try expect(v.findUtf8("橋", 4) == 9);
        try expect(v.findUtf8(".橋", 3) == 8);
    }

    {
        var utf = try Ctring.New(JoseBytes);
        defer utf.deinit();

        try expect(utf.findUtf8("\u{65}\u{301}", .{}) == 3);
        try expect(utf.findUtf8("\u{65}\u{301}", .{.start=4}) == 10);
        try expect(utf.findAscii("se", .{}) == 5);
        try expect(utf.findAscii("se", .{.start=10}) == 31);
        var my_view = utf.view(31, 33);
        try expect(utf.findView(my_view, .{.start=10}) == 31);
        my_view.setView(10, 12);
        try expect(utf.findView(my_view, .{}) == 3);
    }

    { // lastIndexOf
        {
            var suf = try Ctring.New(".");
            defer suf.deinit();
            const idx = top.lastIndexOf(suf, .{});
            try expect(idx == 8);
            try expect(top.find(suf, .{}) == 2);
            try expect(top.lastIndexOfAscii(".5b", .{}) == 5);
        }
        {
            var suf = try Ctring.Ascii(".");
            defer suf.deinit();
            const idx = top.lastIndexOf(suf, .{});
            try expect(idx == 8);
        }
        {
            var suf = try Ctring.New("橋");
            defer suf.deinit();
            const idx = top.lastIndexOf(suf, .{});
            try expect(idx == 9);
        }

        {
            var suf = try Ctring.New(".橋");
            defer suf.deinit();
            try expect(top.lastIndexOf(suf, .{}) == 8);
            try expect(top.find(suf, .{}) == 2);
        }

        { // too long
            var needle = try Ctring.New("lkajsdfkjlasjfsdfsdf");
            defer needle.deinit();
            try expect(top.lastIndexOf(needle, .{}) == null);
        }

        const v = top.view(0, top.size());
        {
            try expect(v.lastIndexOfUtf8("🧑‍🌾") == 0);
            try expect(v.lastIndexOfUtf8(".橋") == v.size()-2);
            try expect(v.lastIndexOfAscii(".") == v.size()-2);
            var s = try Ctring.New(".5b");
            defer s.deinit();
            try expect(v.lastIndexOf(s) == 5);
        }
    }
}

test "Split" {
    try Ctring.Init(alloc);
    defer Ctring.Deinit();

    var top = try Ctring.New(JoseBytes);
    defer top.deinit();
    // top.printStats(@src());
    // mtl.debug(@src(), "{f}", .{top._(2)});

    const top_view = top.view(0, top.size());
    {
        var sep = try Ctring.Ascii(" ");
        defer sep.deinit();
        var arr = try top_view.split(sep, true);
        defer arr.deinit(ctx.a);
        const correct = [_][]const u8{"Jos\u{65}\u{301}", "se", "fu\u{65}\u{301}",
        "a", "Sevilla", "sin", "pararse"};
        for (arr.items, correct) |a, b| {
            try expect(a.eqUtf8(b));
        }
    }

    {
        var arr = try top_view.splitAscii(" ", true);
        defer arr.deinit(ctx.a);
        const correct = [_][]const u8{"Jos\u{65}\u{301}", "se", "fu\u{65}\u{301}",
        "a", "Sevilla", "sin", "pararse"};
        for (arr.items, correct) |a, b| {
            try expect(a.eqUtf8(b));
        }
    }

    {
        var root = try Ctring.New("Hello,  world! Again!");
        defer root.deinit();
        const rootv = root.view(0, root.size());
        {
            var arr = try rootv.splitAscii(" ", true);
            defer arr.deinit(ctx.a);

            const correct = [_][]const u8{"Hello,", "", "world!", "Again!"};
            for (arr.items, correct) |a, b| {
                // mtl.debug(@src(), "{f} vs \"{s}\"", .{a._(2), b});
                try expect(a.eqAscii(b));
            }
        }

        {
            var arr = try rootv.splitAscii(" ", false);
            defer arr.deinit(ctx.a);

            const correct = [_][]const u8{"Hello,", "world!", "Again!"};
            for (arr.items, correct) |a, b| {
                // mtl.debug(@src(), "{f} vs \"{s}\"", .{a._(2), b});
                try expect(a.eqAscii(b));
            }
        }
    }
}