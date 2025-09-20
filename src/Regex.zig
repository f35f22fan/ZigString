const std = @import("std");
const ArrayList = std.ArrayList;
const String = @import("String.zig");
const Grapheme = String.Grapheme;
const Index = String.Index;
const Slice = String.Slice;
const mtl = String.mtl;
const Cp = String.Codepoint;
const Regex = @This();
const Allocator = std.mem.Allocator;
const IdType = u16;

const Error = error {
    BadRange,
    Parsing,
};

const Meta = enum(u8) {
    Not,
    Or,
    NonCapture,
    NamedCapture,
    NegativeLookAhead,
    NegativeLookBehind,
    PositiveLookAhead,
    PositiveLookBehind,

    SymbolAnyChar,
    SymbolNewLine,
    SymbolTab,
    SymbolNumber,
    SymbolNonNumber,
    SymbolWordChar,
    SymbolNonWordChar,
    SymbolWhitespace,
    SymbolNonWhitespace,
    SymbolWordBoundary,
    SymbolNonWordBoundary,
    SymbolStartOfLine,
    SymbolEndOfLine,
};

fn Iterator(comptime T: type) type {
    return struct {
        const Self = @This();
        items: []T,
        at: usize = 0,
        first_time: bool = true,

        pub fn New(a: []T) Self {
            return Iterator(T) {
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

        inline fn size(self: Self) usize {
            return self.items.len;
        }

        pub fn current(self: Self) ?T {
            if (self.at >= self.size())
                return null;
            return self.items[self.at];
        }

        inline fn nextIdx(self: *Self) ?usize {
            if (self.first_time) {
                self.first_time = false;
                return self.at;
            } else {
                if (self.at+1 >= self.size()) {
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
            if (self.prevIdx()) |idx| {
                return &self.items[idx];
            }

            return null;
        }

        pub fn prev(self: *Self) ?T {
           if (self.prevIdx()) |idx| {
                return self.items[idx];
            }

            return null;
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

const Token = union(enum) {
    group: Group,
    qtty: Qtty,
    meta: Meta,
    str: String,
    name: String,
    range: GraphemeRange,

    inline fn isMeta(self: Token, param: Meta) bool {
        switch(self) {
            .meta => |m| return (m == param),
            else => return false,
        }
    }

    inline fn isRange(self: Token) bool {
        switch(self) {
            .range => return true,
            else => return false,
        }
    }

    pub fn isAnyChar(self: Token) bool {
        return self.isMeta(Meta.SymbolAnyChar);
    }

    pub fn isNot(self: Token) bool {
        return self.isMeta(Meta.Not);
    }

    pub fn isName(self: Token) bool {
        switch (self) {
            .name => return true,
            else => return false,
        }
    }

    pub fn isOr(self: Token) bool {
        return self.isMeta(Meta.Or);
    }

    pub fn isQtty(self: Token) bool {
        switch (self) {
            .qtty => return true,
            else => return false,
        }
    }

    pub fn isString(self: Token) bool {
        switch (self) {
            .str => return true,
            else => return false,
        }
    }

    pub fn deinit(self: Token) void {
        switch (self) {
            .group => |g| {
                // mtl.debug(@src(), "{}", .{g});
                g.deinit();
            },
            .str => |s| {
                // mtl.debug(@src(), "{}", .{s});
                s.deinit();
            },
            .name => |s| {
                s.deinit();
            },
            else => {},
        }
    }
};

pub const GraphemeRange = struct {
    a: Cp,
    b: Cp,

    pub fn New(a: Cp, b: Cp) GraphemeRange {
        return .{.a = a, .b = b};
    }

    pub fn within(self: GraphemeRange, input: *const String, at: Index) bool {
        const g = input.charAtIndex(at) orelse return false;
        const cp = g.getCodepoint() orelse return false;
        return cp >= self.a and cp <= self.b;
    }

    pub fn format(self: GraphemeRange, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Range{{{}-{}}}", .{self.a, self.b});
    }
};

pub const Qtty = struct {
    a: i64 = 1,
    b: i64 = 1,
    lazy: bool = false,

    pub fn FromCurly(input: String) !Qtty {
        if (input.indexOfAscii(",", .{})) |comma_idx| {
            const s1 = try input.betweenIndices(String.strStart(), comma_idx);
            defer s1.deinit();
            const n1: i32 = try s1.parseInt(i32, 10);
            if (comma_idx.eq(input.beforeLast())) {
                return Qtty {.a = n1, .b = inf()};
            } else {
                const s2 = try input.betweenIndices(comma_idx.addRaw(1), input.beforeLast().addRaw(1));
                defer s2.deinit();
                const n2: i32 = try s2.parseInt(i32, 10);
                const qtty = Qtty.FixedRange(n1, n2);
                
                return qtty;
            }
        } else {
            const n1: i32 = try input.parseInt(i32, 10);
            return Qtty.ExactNumber(n1);
        }

        return Error.Parsing;
    }

    pub inline fn inf() i64 {
        return std.math.maxInt(i64);
    }
    /// format implements the `std.fmt` format interface for printing types.
    pub fn format(self: Qtty, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        var buf: [8]u8 = undefined;
        var s: []const u8 = undefined;
        const lazy = if (self.lazy) "(lazy)" else "";
        if (self.b == inf()) {
            try writer.print("Qtty[{}+{s}]", .{self.a, lazy});
        } else {
            if (self.a == self.b) {
                try writer.print("Qtty[{}{s}]", .{self.a, lazy});
            } else {
                s = if (self.b == inf()) "+" else try std.fmt.bufPrint(&buf, "{}", .{self.b});
                try writer.print("Qtty[{}..{s}{s}]", .{self.a, s, lazy});
            }
        }
    }

    pub fn exactNumber(self: Qtty, n: i64) bool {
        return self.a == n and self.b == n;
    }

    pub fn ExactNumber(a: i64) Qtty {
        return Qtty {.a = a, .b = a};
    }

    pub fn One() Qtty {
        return Qtty {.a = 1, .b = 1};
    }

    pub fn setExactNumber(self: *Qtty, a: i64) void {
        self.a = a;
        self.b = a;
    }

    pub fn setFixedRange(self: *Qtty, a: i64, b: i64) !void {
        if (a > b) {
            return Error.BadRange;
        }
        self.a = a;
        self.b = b;
    }

    pub fn setNOrMore(self: *Qtty, a: i64) void {
        self.a = a;
        self.b = inf();
    }

    pub fn setOneOrMore(self: *Qtty) void {
        self.a = 1;
        self.b = inf();
    }

    pub fn setZeroOrMore(self: *Qtty) void {
        self.a = 0;
        self.b = inf();
    }

    pub fn ZeroOrMore() Qtty { return Qtty {.a = 0, .b = inf()}; }
    pub fn zeroOrMore(self: Qtty) bool { // x*
        return self.a == 0 and self.b == inf();
    }

    pub fn ZeroOrOne() Qtty { return Qtty {.a = 0, .b = 1}; }
    pub fn zeroOrOne(self: Qtty) bool { // x?
        return self.a == 0 and self.b == 1;
    }

    pub fn OneOrMore() Qtty { return Qtty {.a = 1, .b = inf()}; }
    pub fn oneOrMore(self: Qtty) bool { // x+
        return self.a == 1 and self.b >= 1;
    }

    pub fn nOrMore(self: Qtty) bool {
        return self.b == inf();
    }

    pub fn FixedRange(a: i64, b: i64) Qtty {
        return Qtty {.a = a, .b = b};
    }

    pub fn fixedRange(self: Qtty) bool { // x{a,b}
        return self.b != inf();
    }

    pub fn asManyAsPossible(self: Qtty) bool {
        return self.b == inf();
    }

    pub fn New(a: i64, b: ?i64) Qtty {
        return Qtty {
            .a = a,
            .b = if (b) |n| n else 1,
        };
    }
};

const Enclosed = enum(u8) {
    None,
    Square,
    Round,
};

pub const EvalAs = enum(u8) {
    Or,
    Not,
};

pub const Match = enum(u8) {
    AnyOf,
    All,
};

pub const Group = struct {
    enclosed: Enclosed = .None,
    match_type: Match = .All,
    qtty: Qtty = .New(1, Qtty.inf()),
    regex: *Regex,
    token_arr: ArrayList(ArrayList(Token)) = undefined,
    id: ?IdType = null,
    parent_id: ?IdType = null,
    capture: ?String = null,
    capture_index: usize = 0,
    starts_at: ?Index = null,

    pub fn New(regex: *Regex, parent: ?*Group) Group {
        const parent_id = if (parent) |p| p.id else null;
        var g = Group{.regex = regex, .id = regex.next_group_id, .parent_id = parent_id};
        regex.next_group_id += 1;
        
        // mtl.debug(@src(), "g.id={}, p.id={}", .{g.id, parent_id});
        // g.tokens = ArrayList(Token).init(regex.alloc);
        g.token_arr = ArrayList(ArrayList(Token)).init(regex.alloc);

        return g;
    }

    inline fn printMeta(writer: anytype, m: Meta) !void {
         try writer.print("{s}{}{s} ", .{String.COLOR_CYAN, m, String.COLOR_DEFAULT});
    }

    pub fn format(self: Group, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        if (fmt.len > 0) {
            if (std.mem.eql(u8, fmt, "id")) {
                try writer.print("Group:{?}", .{self.id});
                return;
            }
        }

        try writer.print("{s}Group:{?} {} (parent:{?}) {s}", .{String.COLOR_ORANGE,
        self.id, self.match_type, self.parent_id, String.COLOR_DEFAULT});
        for (self.token_arr.items, 0..) |arr, array_index| {
            for (arr.items, 0..) |t, item_index| {
                if (array_index > 0 and item_index == 0) {
                    try printMeta(writer, .Or);
                }
                switch (t) {
                    .group => |g| {
                        try writer.print("{s}Group={?}{s} ", .{String.COLOR_BLUE, g.id, String.COLOR_DEFAULT});
                    },
                    .qtty => |q| {
                        try writer.print("{s}{}{s} ", .{String.COLOR_GREEN, q, String.COLOR_DEFAULT});
                    },
                    .meta => |m| {
                        try printMeta(writer, m);
                    },
                    .str => |s| {
                        try writer.print("{dt} ", .{s});
                    },
                    .name => |s| {
                        try writer.print("{dt} ", .{s});
                    },
                    .range => |r| {
                        try writer.print("{s}{}{s} ", .{String.COLOR_MAGENTA, r, String.COLOR_DEFAULT});
                    }
                }
            }
        }
    }

    fn startsWithMeta(slice: []const Token, meta: Meta) bool {
        if (slice.len == 0) {
            return false;
        }

        return slice[0].isMeta(meta);
    }

    fn endsWithMeta(slice: []const Token, meta: Meta) bool {
        if (slice.len == 0) {
            return false;
        }

        return slice[slice.len - 1].isMeta(meta);
    }

    pub fn addGrapheme(tokens: *ArrayList(Token), gr: Grapheme) !void {
        // If the last token is a string add to it, otherwise append a new string Token and add to it:
        const len = tokens.items.len;
        if (len > 0 and tokens.items[len-1].isString()) {
            const t = &tokens.items[len-1];
            switch (t.*) {
                .str => |*s| {
                    try s.addGrapheme(gr);
                },
                else => {
                    unreachable;
                }
            }
        } else {
            var s = String.New();
            try s.addGrapheme(gr);
            try tokens.append(Token{ .str = s });
        }
    }

    pub fn canCapture(self: *const Group) bool {
        for (self.token_arr.items) |*arr| {
            if (startsWithMeta(arr.items, Meta.NonCapture))
                return false;
        }

        return true;
    }

    pub fn getCapture(self: *const Group, name: String) ?Slice {
        for (self.token_arr.items) |arr| {
            for (arr.items) |*t| {
                switch (t.*) {
                    .name => |gn| {
                        if (gn.eq(name)) {
                            // mtl.debug(@src(), "{dt}, capture: {?}", .{name, self.capture});
                            if (self.capture) |*str| {
                                return str.asSlice();
                            } else {
                                return null;
                            }
                        }
                    },
                    .group => |*subgroup| {
                        if (subgroup.getCapture(name)) |result| {
                            return result;
                        }
                    },
                    else => {},
                }
            }
        }

        return null;
    }

    pub fn getCaptureByIndex(self: *const Group, index: usize) ?Slice {
        if (self.capture_index == index) {
            if (self.capture) |*s| {
                return s.asSlice();
            } else {
                return null;
            }
        }

        for (self.token_arr.items) |*arr| {
            for (arr.items) |*t| {
                switch (t.*) {
                    .group => |*g| {
                        if (g.getCaptureByIndex(index)) |slice| {
                            return slice;
                        }
                    },
                    else => {}
                }
            }
        }

        return null;
    }

    fn matchAll(arr: *ArrayList(Token), tokens_iter: *Iterator(Token), input: *const String, haystack: *const String, from: Index) ?Index {
        var qtty = Qtty.One();
        if (tokens_iter.peekNext()) |next_token| {
            switch(next_token.*) {
                .qtty => |q| {
                    qtty = q;
                    _ = tokens_iter.next(); // if so then need to advance
                },
                else => {},
            }
        }

        if (qtty.a == 0 and qtty.lazy) {
            return from;
        }

        var negative_lookahead = false;
        var positive_lookahead = false;
        if (tokens_iter.peekPrev()) |prev_token| {
            if (prev_token.isMeta(.NegativeLookAhead)) {
                negative_lookahead = true;
            } else if (prev_token.isMeta(.PositiveLookAhead)) {
                positive_lookahead = true;
            }
        }

        const starts_with_not = startsWithMeta(arr.items, .Not);
        
        if (qtty.exactNumber(1)) {
            const past_match = matchStr(starts_with_not, input, haystack, from);
            if (negative_lookahead) {
                // mtl.debug(@src(), "Dealing with negative_lookahead for {dt}", .{input});
                return if (past_match == null) from else null;
            } else if (positive_lookahead) {
                return from; // must not advance
            } else {
                return past_match;
            }
        }

        const last_gr_index = input.beforeLast();
        const base_str = input.betweenIndices(.{}, last_gr_index) catch return null;
        defer base_str.deinit();
        var at = from;
        {
            const past_match = matchStr(starts_with_not, &base_str, haystack, from);
            if (past_match) |pm| {
                at = pm;
            } else {
                if (negative_lookahead) {
                    return from; // means match
                } else if (positive_lookahead) {
                    return null; // means no match
                }
            }
        }
        const last_char_str = input.midIndex(last_gr_index) catch return null;
        defer last_char_str.deinit();
        // mtl.debug(@src(), "base_str:{dt}, last_char:{}", .{base_str, last_char_str});
        var count: usize = 0;
        
        while (true) {
            if (matchStr(starts_with_not, &last_char_str, haystack, at)) |idx| {
                count += 1;
                at = idx;
                if (count == qtty.b) {
                    break;
                }
            } else {
                break;
            }
        }

        if (count >= qtty.a) {
            return if (positive_lookahead) from else at;
        }

        return null;
    }

    fn matchAny(tokens_arr: *ArrayList(Token), tokens_iter: *Iterator(Token), input: *const String, haystack: *const String, from: Index) ?Index {
        const starts_with_not = startsWithMeta(tokens_arr.items, .Not);
        var negative_lookahead = false;
        if (tokens_iter.peekPrev()) |prev_token| {
            if (prev_token.isMeta(.NegativeLookAhead)) {
                negative_lookahead = true;
            }
        }

        const hgr = haystack.charAtIndex(from) orelse return null;
        // var found = false;
        var string_iter = input.iterator();
        while (string_iter.next()) |gr| {
            // mtl.debug(@src(), "input: {dt}, gr: {dt} vs haystack {dt}", .{input, gr, hgr});
            const gr_match = gr.eq(hgr);
            if (starts_with_not) {
                if (gr_match) {
                    return null;
                }
            } else if (gr_match) {
                if (negative_lookahead) {
                    return from;
                } else {
                    return from.addGrapheme(gr);
                }
            }
        }

        if (starts_with_not) {
            return from.addGrapheme(hgr);
        }

        return null;
    }

    fn matchStr(starts_with_not: bool, needles: *const String, haystack: *const String, from: Index) ?Index {
        const past_idx = haystack.matches(needles, from);//, cs
        //if (startsWithMeta(arr.items, .Not))
        if (starts_with_not) {
            if (past_idx) |idx| {
                _ = &idx;
                // mtl.debug(@src(), "STARTS WITH: {dt}", .{haystack.slice(from, idx)});
                return null;
            } else {
                // mtl.debug(@src(), "DOESN'T START WITH {dt}", .{needles});
            }
        }

        
        return past_idx;
    }

    fn parseIntoTokens(self: *Group, index: Index) !Index {
        var it = String.Iterator.New(&self.regex.pattern, index);
        var ret_idx: ?Index = null;
        const new_array = ArrayList(Token).init(self.regex.alloc);
        try self.token_arr.append(new_array);
        var current_arr: *ArrayList(Token) = &self.token_arr.items[0];

        while (it.next()) |gr| {
            if (gr.eqAscii('[')) {
                if (self.hasContent()) {
                    var new_group = Group.New(self.regex, self);
                    new_group.setSquare();
                    const newg = it.next() orelse return error.Other;
                    it.continueFrom(try new_group.parseIntoTokens(newg.idx));
                    try addGroup(current_arr, new_group);
                } else {
                    self.setSquare();
                }
            } else if (gr.eqAscii(']')) {
                ret_idx = gr.idx.addRaw(1);
                break;
            } else if (gr.eqAscii('(')) {
                if (self.hasContent()) {
                    var new_group = Group.New(self.regex, self);
                    new_group.setRound();
                    const newg = it.next() orelse return error.Other;
                    it.continueFrom(try new_group.parseIntoTokens(newg.idx));
                    try addGroup(current_arr, new_group);
                } else {
                    self.setRound();
                }
            } else if (gr.eqAscii(')')) {
                ret_idx = gr.idx.addRaw(1);
                break;
            } else if (gr.eqAscii('?')) {
                const s: *String = &self.regex.pattern;
                if (s.matchesAscii("?:", gr.idx)) |idx| {
                    it.continueFrom(idx);
                    try addMeta(current_arr, .NonCapture);
                    // self.non_capture = true;
                } else if (s.matchesAscii("?!", gr.idx)) |idx_past| {
                    it.continueFrom(idx_past);
                    try addMeta(current_arr, .NegativeLookAhead);
                } else if (s.matchesAscii("?<!", gr.idx)) |idx| {
                    it.continueFrom(idx);
                    try addMeta(current_arr, .NegativeLookBehind);
                } else if (s.matchesAscii("?=", gr.idx)) |idx| {
                    it.continueFrom(idx);
                    try addMeta(current_arr, .PositiveLookAhead);
                } else if (s.matchesAscii("?<=", gr.idx)) |idx| {
                    it.continueFrom(idx);
                    try addMeta(current_arr, .PositiveLookBehind);
                } else if (s.matchesAscii("?<", gr.idx)) |idx| { //(?<name>\\w+) = name = e.g."Jordan"
                    it.continueFrom(idx);
                    // named capture
                    if (s.indexOfAscii(">", .{.from = idx.addRaw("?<".len)})) |closing_idx| {
                        const name = try s.betweenIndices(idx, closing_idx);
                        // mtl.debug(@src(), "Name: \"{}\"", .{name});
                        try addMeta(current_arr, .NamedCapture);
                        try addName(current_arr, name);
                        it.continueFrom(closing_idx.addRaw(1)); // go past ">"
                    }
                } else { // just "?"
                    try addQtty(current_arr, Qtty.ZeroOrOne());
                }
            } else if (gr.eqAscii('{')) {
                const s: *String = &self.regex.pattern;
                if (s.indexOfAscii("}", .{.from = gr.idx.addRaw(1)})) |idx| {
                    const qtty_in_curly = try s.betweenIndices(gr.idx.addRaw("}".len), idx);
                    defer qtty_in_curly.deinit();
                    it.continueFrom(idx.addRaw("}".len));
                    const qtty = try Qtty.FromCurly(qtty_in_curly);
                    try addQtty(current_arr, qtty);
                    // mtl.debug(@src(), "qtty_in_curly: {}", .{qtty});
                } else {
                    mtl.debug(@src(), "Not found closing '}}'", .{});
                }
            } else if (gr.eqAscii('\\')) {
                const symbol = it.next() orelse break;
                if (symbol.eqAscii('d')) {
                    try addMeta(current_arr, Meta.SymbolNumber);
                } else if (symbol.eqAscii('D')) {
                    try addMeta(current_arr, Meta.SymbolNonNumber);
                } else if (symbol.eqAscii('w')) {
                    try addMeta(current_arr, Meta.SymbolWordChar);
                } else if (symbol.eqAscii('W')) {
                    try addMeta(current_arr, Meta.SymbolNonWordChar);
                } else if (symbol.eqAscii('s')) {
                    try addMeta(current_arr, Meta.SymbolWhitespace);
                } else if (symbol.eqAscii('S')) {
                    try addMeta(current_arr, Meta.SymbolNonWhitespace);
                } else if (symbol.eqAscii('.')) {
                    try addAscii(current_arr, "."); // literally the dot character
                } else if (symbol.eqAscii('b')) {
                    try addMeta(current_arr, Meta.SymbolWordBoundary);
                } else if (symbol.eqAscii('B')) {
                    try addMeta(current_arr, Meta.SymbolNonWordBoundary);
                } else if (symbol.eqAscii('|')) {
                    try addAscii(current_arr, "|");
                }
            } else if (gr.eqAscii('^')) {
                if (gr.idx.gr == 0) {
                    // self.must_start_on_line = true;
                    try addMeta(current_arr, .SymbolStartOfLine);
                } else {
                    // mtl.debug(@src(), "Adding .Not to {?}, current_arr.len={}", .{self.id, current_arr.items.len});
                    try addMeta(current_arr, Meta.Not);
                }
            } else if (gr.eqAscii('+')) {
                var q = Qtty.OneOrMore();
                if (it.next()) |ng| {
                    if (ng.eqAscii('?')) {
                        q.lazy = true;
                    } else {
                        it.continueFrom(gr.idx.addRaw(1));
                    }
                }
                try addQtty(current_arr, q);
            } else if (gr.eqAscii('*')) {
                var q = Qtty.OneOrMore();
                if (it.next()) |ng| {
                    if (ng.eqAscii('?')) {
                        q.lazy = true;
                    } else {
                        it.continueFrom(gr.idx.addRaw(1));
                    }
                }
                try addQtty(current_arr, Qtty.ZeroOrMore());
            } else if (gr.eqAscii('\n')) {
                try addMeta(current_arr, Meta.SymbolNewLine);
            } else if (gr.eqAscii('\t')) {
                try addMeta(current_arr, Meta.SymbolTab);
            } else if (gr.eqAscii('.')) {
                try addMeta(current_arr, Meta.SymbolAnyChar);
            } else if (gr.eqAscii('$')) {
                try addMeta(current_arr, .SymbolEndOfLine);
            } else if (gr.eqAscii('|')) {
                // try self.addMeta(Meta.Or);
                // mtl.debug(@src(), ">>>>>>>>>>>>>> FOUND AN OR", .{});
                const new_arr = ArrayList(Token).init(self.regex.alloc);
                try self.token_arr.append(new_arr);
                current_arr = &self.token_arr.items[self.token_arr.items.len - 1];
            } else {
                // mtl.debug(@src(), "[GR] {dt}, group_id={?}, current_arr.len={}", .{gr, self.id, current_arr.items.len});
                try addGrapheme(current_arr, gr);
            }
        }

        try self.analyzeTokens();

        if (ret_idx) |idx| {
            return idx;
        }

        return it.idx;
    }

    fn analyzeTokens(self: *Group) !void {
        for (self.token_arr.items) |*arr| {
            var token_iter = Iterator(Token).New(arr.items);
            // for (self.tokens.items, 0..) |*t, i| {
            while (token_iter.nextPtr()) |t| {
                switch (t.*) {
                    .str => |*s| {
                        var new_tokens = ArrayList(Token).init(self.regex.alloc);
                        defer new_tokens.deinit();
                        try parseRange(s.*, &new_tokens);
                        if (new_tokens.items.len > 0) {
                            arr.orderedRemove(token_iter.at).deinit();
                            for (new_tokens.items) |item| {
                                try arr.insert(token_iter.at, item);
                            }
                        }
                    },
                    else => {}
                }
            }
        }
    }

    inline fn addGroup(arr: *ArrayList(Token), g: Group) !void {
        try arr.append(Token {.group = g});
    }

    inline fn addMeta(arr: *ArrayList(Token), m: Meta) !void {
        try arr.append(Token {.meta = m});
    }

    fn addName(arr: *ArrayList(Token), s: String) !void {
        try arr.append(Token {.name = s});
    }

    fn addQtty(arr: *ArrayList(Token), qtty: Qtty) !void {
        try arr.append(Token {.qtty = qtty});
    }

    fn addStr(arr: *ArrayList(Token), s: String) !void {
        try arr.append(Token {.str = s});
    }

    fn addAscii(arr: *ArrayList(Token), s: []const u8) !void {
        try arr.append(Token {.str = try String.FromAscii(s)});
    }

    fn addUtf8(arr: *ArrayList(Token), s: []const u8) !void {
        try arr.append(Token {.str = try String.From(s)});
    }

    pub fn deinit(self: Group) void {
        for (self.token_arr.items) |arr| {
            for (arr.items) |t| {
                t.deinit();
            }
            arr.deinit();
        }
        self.token_arr.deinit();

        if (self.capture) |str| {
            str.deinit();
        }
    }

    pub fn hasContent(self: Group) bool {
        for (self.token_arr.items) |arr| {
            if (arr.items.len > 0) {
                return true;
            }
        }

        return false;
    }

    pub fn matches(self: *Group, input: *const String, from: Index) ?Index {
        for (self.token_arr.items, 0..) |*arr, i| {
            _ = &i;
            if (self.matches2(arr, input, from)) |past_idx| {
                // mtl.debug(@src(), ">>>>>>MATCHES group.id={?}, arr={} past_idx:{}", .{self.id, i, past_idx});
                return past_idx;
            } else {
                // mtl.debug(@src(), ">>>>>>MATCH FAILED group.id={?}, arr={}", .{self.id, i});
            }
        }

        return null;
    }

    pub fn matches2(self: *Group, tokens: *ArrayList(Token), haystack: *const String, from: Index) ?Index {
        var at = from;
        const cs = String.CaseSensitive.Yes;
        _ = cs;
        const starts_with_not = startsWithMeta(tokens.items, .Not);
        // mtl.debug(@src(), ">>>>>>>>>>>>>Group ID: {?} from:{}", .{self.id, from});

        if (startsWithMeta(tokens.items, .SymbolStartOfLine)) {
            if (at.cp != 0) {
                const gr = haystack.prev(at) orelse return null;
                if (!gr.eqAscii('\n')) {
                    return null;
                }
            }
        }

        // for (self.tokens.items) |*t| {
        var tokens_iter = Iterator(Token).New(tokens.items);
        while (tokens_iter.nextPtr()) |t| {
            switch (t.*) {
                .str => |*needles| {
                    if (self.match_type == Match.All) {
                        if (matchAll(tokens, &tokens_iter, needles, haystack, at)) |idx_past| {
                            if (!startsWithMeta(tokens.items, .NonCapture)) {
                                // mtl.debug(@src(), "CAPTURE:Y {dt}", .{input.slice(at, idx_past)});
                                if (self.capture) |*str| {
                                    str.addSlice(haystack, at, idx_past) catch return null;
                                } else {
                                    self.capture = haystack.betweenIndices(at, idx_past) catch return null;
                                }
                            }
                            at = idx_past;
                        } else {
                            return null;
                        }
                    } else { // == Match.AnyOf
                        // const gr = haystack.charAtIndex(at) orelse return null;
                        // mtl.debug(@src(), "AnyOf: haystack {dt}, at: {}, needles:{}, token_arr.len={}, group.id={?}",
                        // .{gr, at, needles, self.token_arr.items.len, self.id});
                        if (matchAny(tokens, &tokens_iter, needles, haystack, at)) |idx_after| {
                            _ = &idx_after;
                        } else {
                            return null;
                        }
                    }
                },
                .meta => |m| {
                    switch (m) {
                        .SymbolWordChar => {
                            // mtl.debug(@src(), "Word char:\"{?}\"", .{input.charAtIndex(at)});
                            if (!haystack.isWordChar(at)) {
                                // mtl.trace(@src());
                                return null;
                            }
                            
                            if (self.findNextChars(haystack, at, m, &tokens_iter)) |idx_after| {
                                // mtl.trace(@src());
                                at = idx_after;
                            } else {
                                mtl.trace(@src());
                                return null;
                            }
                        },
                        .SymbolWordBoundary => {
                            if (!haystack.isWordBoundary(at)) {
                                return null;
                            }
                        },
                        .SymbolNonWordBoundary => {
                            if (haystack.isWordBoundary(at)) {
                                return null;
                            }
                        },
                        .SymbolNumber => {
                            if (!haystack.isNumber(at)) {
                                return null;
                            }
                            if (self.findNextChars(haystack, at, m, &tokens_iter)) |past_idx| {
                                at = past_idx;
                            } else {
                                return null;
                            }
                        },
                        .SymbolNonNumber => {
                            if (haystack.isNumber(at)) {
                                return null;
                            }

                            if (self.findNextChars(haystack, at, m, &tokens_iter)) |past_idx| {
                                at = past_idx;
                            } else {
                                return null;
                            }
                        },
                        .SymbolWhitespace => {
                            if (!haystack.isWhitespace(at)) {
                                return null;
                            }

                            if (self.findNextChars(haystack, at, m, &tokens_iter)) |past_idx| {
                                at = past_idx;
                            } else {
                                return null;
                            }
                        },
                        .SymbolNonWhitespace => {
                            if (haystack.isWhitespace(at)) {
                                return null;
                            }

                            if (self.findNextChars(haystack, at, m, &tokens_iter)) |past_idx| {
                                at = past_idx;
                            } else {
                                return null;
                            }
                        },
                        else => |v| {
                            _ = v;
                            // mtl.debug(@src(), "UNTREATED META => {}", .{v});
                        }
                    }
                },
                .group => |*sub_group| {
                    var qtty: Qtty = Qtty.ExactNumber(1);
                    if (tokens_iter.peekNext()) |next_token| {
                        switch (next_token.*) {
                            .qtty => |q| {
                                qtty = q;
                                tokens_iter.add(1);
                            },
                            else => {}
                        }
                    }

                    var work = qtty.a > 0 or !qtty.lazy;
                    var count: usize = 0;
                    while (work) {
                        if (sub_group.matches(haystack, at)) |past_idx| {
                            at = past_idx;
                        } else {
                            break;
                        }
                        count += 1;
                        if (qtty.lazy and count >= qtty.a) {
                            work = false; // break if lazy
                        } else if (count >= qtty.b) {
                            break; // break if maximum count reached
                        }
                        // otherwise keep finding as many as possible
                    }

                    if (count < qtty.a) {
                        return null;
                    }
                },
                .range => |range| {
                    _ = &range;
                    const gr = haystack.charAtIndex(at) orelse return null;
                    _ = &gr;
                    // mtl.debug(@src(), "RANGE, Group:{?}, starts_with {dt}, gr={dt} at={}, not:{}",
                    // .{self.id, haystack.midSlice(from), gr, from, starts_with_not});
                    if (range.within(haystack, at)) {
                        // mtl.debug(@src(), "Group={?} Range MATCH {}, at:{}, for: {?}, not:{}",
                        // .{self.id, range, at, gr, starts_with_not});
                    } else {
                        // mtl.debug(@src(), "Group={?} Range FAIL {}, for: {?}, at={}",
                        // .{self.id, range, gr, at});
                        // return at;
                    }
                    
                },
                else => |v| {
                    _ = &v;
                    // mtl.debug(@src(), "UNTREATED => {}", .{v});
                }
            }
        }

        switch (self.match_type) {
            .AnyOf => {
                const gr = haystack.charAtIndex(at) orelse return null;
                at = at.addGrapheme(gr);
                if (starts_with_not) {
                    // mtl.debug(@src(), "="**20, .{});
                }
                if (self.capture) |*str| {
                    str.addGrapheme(gr) catch return null;
                } else {
                    self.capture = gr.toString() catch return null;
                }
            },
            else => {},
        }

        if (self.starts_at == null)
            self.starts_at = from;

        if (!at.isPast(haystack) and startsWithMeta(tokens.items, .SymbolEndOfLine)) {
            const gr = haystack.charAtIndex(at) orelse return null;
            if (!gr.eqAscii('\n')) {
                return null;
            }
        }

        return at;
    }

    // returns past last found grapheme, or null
    pub fn findNextChars(self: *Group, input: *const String, from: Index, meta: Meta, tokens_iter: *Iterator(Token)) ?Index {

        var qtty: Qtty = Qtty.One();
        if (tokens_iter.peekNext()) |next_token| {
            switch (next_token.*) {
               .qtty => |q| {
                    qtty = q;
                    tokens_iter.add(1);
                },
                else => {}
            }
        }

        var positive_lookahead = false;
        if (tokens_iter.peekFirst()) |token| {
            if (token.isMeta(.PositiveLookAhead)) {
                positive_lookahead = true;
            }
        }

        var string_iter = input.iteratorFrom(from);
        var count: usize = 0;
        var found_enough = false;
        var ret_idx: Index = from;
        while (string_iter.next()) |gr| {
            var found_next_one = true;
            switch (meta) {
                .SymbolWordChar => {
                    // mtl.debug(@src(), "SymbolWordChar:\"{dt}\"", .{gr});
                    if (!gr.isWordChar()) {
                        found_next_one = false;
                        break;
                    }
                },
                .SymbolNumber => {
                    if (!gr.isNumber()) {
                        found_next_one = false;
                        break;
                    }
                },
                .SymbolWhitespace => {
                    // mtl.debug(@src(), "SymbolWhitespace", .{});
                    if (!gr.isWhitespace()) {
                        found_next_one = false;
                        break;
                    }
                },
                .SymbolNonWhitespace => {
                    // mtl.debug(@src(), "SymbolNonWhitespace", .{});
                    if (gr.isWhitespace()) {
                        found_next_one = false;
                        break;
                    }
                },
                else => {}
            }

            if (!found_next_one) {
                break;
            }

            ret_idx = gr.idx.addGrapheme(gr);
            count += 1;
            // mtl.debug(@src(), "count:{}, qtty={}", .{count, qtty});
            if (qtty.lazy) {
                if (qtty.a >= count) {
                    found_enough = true;
                    // mtl.debug(@src(), "count:{}", .{count});
                    break;
                }
            } else {
                if (count >= qtty.b) {
                    found_enough = true;
                    // mtl.debug(@src(), "q:{}, count:{}", .{qtty, count});
                    break;
                }
            }
        }

        if (qtty.asManyAsPossible()) {
            found_enough = true;
        }

        if (found_enough) {
            if (positive_lookahead) {
                return from;
            }
            if (self.capture) |*str| {
                str.addSlice(input, from, ret_idx) catch return null;
            } else {
                self.capture = input.betweenIndices(from, ret_idx) catch return null;
            }
        }

        // mtl.debug(@src(), "found_enough={}", .{found_enough});

        return if (found_enough) ret_idx else null;
    }

    fn parseRange(s: String, tokens: *ArrayList(Token)) !void {
        const idx = s.indexOfAscii("-", .{}) orelse return;
        var iter = s.iteratorFrom(idx);
        const prev = iter.prevFrom(idx) orelse return;
        const next = iter.nextFrom(idx) orelse return;
        const cp1 = prev.getCodepoint() orelse return;
        const cp2 = next.getCodepoint() orelse return;
        if (cp1 > cp2) {
            mtl.debug(@src(), "Error: {}({}) > {}({})", .{prev, cp1, next, cp2});
            return;
        }
        const range = GraphemeRange.New(cp1, cp2);
        // mtl.debug(@src(), "Range: {}", .{range});
        
        if (s.size() == 3) {
            try tokens.append(Token{.range = range});
            return;
        }

        var left: String = .{};
        var right: String = .{};
        // mtl.debug(@src(), "string {dt}", .{s});
        if (prev.idx.gr != 0 and prev.idx.gr != 0) {
            left = try s.betweenIndices(.{}, prev.idx);
        }

        const str_end = s.beforeLast();
        if (next.idx.gr < str_end.gr) {
            const next_gr = iter.next() orelse return;
            right = try s.midIndex(next_gr.idx);
        }
        
        if (!right.isEmpty()) {
            const len = tokens.items.len;
            try parseRange(right, tokens);
            const items_added = len != tokens.items.len;
            if (items_added) {
                right.deinit();
            } else {
                try tokens.append(Token{.str = right});
            }
        } else {
            right.deinit();
        }

        try tokens.append(Token{.range = range});
        if (!left.isEmpty()) {
            try tokens.append(Token{.str = left});
        } else {
            left.deinit();
        }
    }

    fn prepareForNewSearch(self: *Group) void {
        self.starts_at = null;
        self.capture_index = 0;
        if (self.capture) |str| {
            str.deinit();
        }
        self.capture = null;

        for (self.token_arr.items) |*arr| {
            for (arr.items) |*t| {
                switch (t.*) {
                    .group => |*g| {
                        g.prepareForNewSearch();
                    },
                    else => {}
                }
            
            }
        }
    }

    pub fn printTokens(self: Group) void {
        mtl.debug(@src(), "{}", .{self});
        for (self.token_arr.items, 0..) |arr, i| {
            _ = i;
            // mtl.debug(@src(), "Group Array={}", .{i});
            for (arr.items) |item| {
                switch (item) {
                    .group => |*g| {
                        g.printTokens();
                    },
                    else => {},
                }
            }
        }
    }

    pub fn setCaptureIndex(self: *Group, index: usize) usize {
        var new_index = index;
        if (self.canCapture()) {
            self.capture_index = new_index;
            new_index += 1;
        }

        for (self.token_arr.items) |*arr| {
            for (arr.items) |*t| {
                switch (t.*) {
                    .group => |*g| {
                        new_index = g.setCaptureIndex(new_index);
                    },
                    else => {}
                }
            }
        }

        return new_index;
    }

    inline fn setRound(self: *Group) void {
        self.match_type = Match.All;
        self.enclosed = Enclosed.Round;
    }

    inline fn setSquare(self: *Group) void {
        self.match_type = Match.AnyOf;
        self.enclosed = Enclosed.Square;
    }
};

// Formula: =SUM(B1+0.3,20.9,-2.4+3*MAX(18,7),B2,C1:C2,MIN(A1,5))*(-3+2)
global_search: bool = true,
case_sensitive: bool = true,
tokens: ArrayList(Token),
pattern: String,
alloc: Allocator,
groups: ArrayList(Group) = undefined,
top_group: Group = undefined,
next_group_id: IdType = 0,
start_pos: ?Index = null,
end_pos: ?Index = null,
found_slice: ?Slice = null,

// Regex takes ownership over `pattern`
pub fn New(alloc: Allocator, pattern: String) !*Regex {
    errdefer pattern.deinit();
    const regex = try alloc.create(Regex);
    errdefer alloc.destroy(regex);
    regex.* = Regex {
        .pattern = pattern,
        .tokens = ArrayList(Token).init(alloc),
        .alloc = alloc,
        .groups = ArrayList(Group).init(alloc),
    };
    
    var top_group: Group = Group.New(regex, null);
    errdefer top_group.deinit();
    _ = try top_group.parseIntoTokens(String.strStart());
    regex.top_group = top_group;

    return regex;
}

pub fn deinit(self: *Regex) void {
    
    for (self.tokens.items) |g| {
        g.deinit();
    }
    self.tokens.deinit();

    self.top_group.deinit();
    self.pattern.deinit();
    self.alloc.destroy(self);
}

pub fn getCapture(self: *const Regex, name: []const u8) ?Slice {
    const name_str = String.From(name) catch return null;
    defer name_str.deinit();
    if (self.top_group.getCapture(name_str)) |result| {
        return result;
    }

    return null;
}

pub fn getCaptureByIndex(self: *const Regex, index: usize) ?Slice {
    if (index == 0) {
        if (self.found_slice) |slice| {
            return slice;
        }
    }

    return self.top_group.getCaptureByIndex(index);
}

pub fn find(self: *Regex, input: *const String, from: Index) ?Slice {
    self.top_group.prepareForNewSearch();
    self.found_slice = null;
    self.start_pos = null;
    self.end_pos = null;
    var input_iter = input.iteratorFrom(from);
    while (input_iter.next()) |gr| {
        if (self.top_group.matches(input, gr.idx)) |end_pos| {
            if (self.start_pos == null) {
                self.start_pos = gr.idx;
            }
            self.end_pos = end_pos;
            const start = self.start_pos orelse return null;
            self.found_slice = input.slice(start, end_pos);
            break;
        }
    }

    _ = self.top_group.setCaptureIndex(1);

    return self.found_slice;
}

pub fn matchedSlice(self: *const Regex, input: *const String) ?String.Slice {
    const start = self.start_pos orelse return null;
    const end = self.end_pos orelse return null;
    // mtl.debug(@src(), "start: {}, end: {}, input: {dt}", .{start, end, input});
    return input.slice(start, end);
}

pub fn printGroups(self: Regex) void {
    self.top_group.printTokens();
}

fn printGroupResult(self: Group) void {
    mtl.debug(@src(), "{id} captured: {?}, starts at: {?}", .{self,
        self.capture, self.starts_at});
    for (self.token_arr.items) |arr| {
        for (arr.items) |item| {
            switch (item) {
                .group => |g| {
                    printGroupResult(g);
                },
                else => {},
            }
        }
    }
}

test "Test regex" {
    const alloc = std.testing.allocator;
    String.ctx = try String.Context.New(alloc);
    defer String.ctx.deinit();

    const heap = "A==-=-CDDKMikeБГДaopqxyzz567\n";//Jos\u{65}\u{301} se fu\u{E9} seguía";
    // const heap = "abc 34def";

    const pattern_native = //"\\s\\d{2}";// "se\\B";// "\u{65}\u{301}";
\\=(=-){2,5}(?=\w+)(AB|CD{2})[EF|^GH](?<ClientName>\w+)(?:БГД[^zyA-Z0-9c1-3]opq(?!345))xyz{2,3}(?=\d{2,})$
;

//on website:
//=(=-){2,5}(AB|CD{2})[^GH](?<ClientName>\w+)(?:БГД[^gbA-Z0-9c1-3]opq(?!345))xyz{2,3}$
    const pattern_str = try String.From(pattern_native);
    const regex = try Regex.New(alloc, pattern_str);
    defer regex.deinit();
    mtl.debug(@src(), "Regex: {dt}", .{pattern_str});
    regex.printGroups();

    const heap_str = try String.From(heap);
    defer heap_str.deinit();
    try heap_str.printGraphemes(@src());

    if (regex.find(&heap_str, Index.strStart())) |matched_slice| {
        mtl.debug(@src(), "Regex matched at {}", .{matched_slice.start});
        mtl.debug(@src(), "Matched string slice: {dt}", .{matched_slice});
        mtl.debug(@src(), "Client name: {?}", .{regex.getCapture("ClientName")}); // should find it
        mtl.debug(@src(), "Pet name: {?}", .{regex.getCapture("Pet Name")}); // should not find it
        for (0..8) |i| {
            mtl.debug(@src(), "Result({}) {?}", .{i, regex.getCaptureByIndex(i)});
        }
        
        
        printGroupResult(regex.top_group);
    } else {
        mtl.debug(@src(), "Regex didn't match", .{});
    }

    if (false) {
        var items = [_]u8 {15, 16, 17};
        var iter = Iterator(u8).New(&items);

        mtl.debug(@src(), "current: {?}", .{iter.current()});
        mtl.debug(@src(), "peek next: {?}", .{iter.peekNext()});
        mtl.debug(@src(), "current: {?}", .{iter.current()});

        while (iter.nextPtr()) |k| {
            mtl.debug(@src(), "next: {}, TypeOf:{}", .{k.*, @TypeOf(k)});
        }

        while (iter.prev()) |k| {
            mtl.debug(@src(), "prev: {}", .{k});
        }
    }

    //() - catpure group, referred by index number preceded by $, like $1
    //(?:) - non capture group
    
    // (?!) – negative lookahead
    // (?<!) – negative lookbehind
    // (?=) – positive lookahead
    // (?<=) – positive lookbehind


}

