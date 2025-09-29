const std = @import("std");
const ArrayList = std.ArrayList;
const String = @import("String.zig");
const Grapheme = String.Grapheme;
const Index = String.Index;
const Slice = String.Slice;
const CaseSensitive = String.CaseSensitive;
const Args = String.Args;
const StringIterator = String.StringIterator;
const Iterator = String.Iterator;
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

    pub fn within(self: GraphemeRange, input: *const String, args: Args) bool {
        var cp = input.charAtIndexOneCp(args.from) orelse return false;
        if (args.cs == .Yes) {
            // mtl.debug(@src(), "cp={}, self.a={}, self.b={}", .{cp, self.a, self.b});
            return cp >= self.a and cp <= self.b;
        }
        
        cp = String.toLowerCp(cp);
        const a1 = String.toLowerCp(self.a);
        const b1 = String.toLowerCp(self.b);
        const flag = cp >= a1 and cp <= b1;
        // mtl.debug(@src(), "cp={}, self.a={}, self.b={}", .{cp, a1, b1});

        return flag;
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

    pub fn done(self: Qtty, n: i64) bool {
        return n >= self.b;
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

    pub fn All() Qtty {
        return Qtty {.a = 1, .b = inf() };
    }

    pub fn One() Qtty {
        return Qtty {.a = 1, .b = 1};
    }

    pub fn setExactNumber(self: *Qtty, a: i64) void {
        self.a = a;
        self.b = a;
    }

     pub fn FixedRange(a: i64, b: i64) Qtty {
        return Qtty {.a = a, .b = b};
    }

    pub fn fixedRange(self: Qtty) bool { // x{a,b}
        return self.b != inf();
    }

    pub fn setFixedRange(self: *Qtty, a: i64, b: i64) !void {
        if (a > b) {
            return error.BadRange;
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

pub const EvalAs = enum(u8) {
    Or,
    Not,
};

pub const Match = enum(u8) {
    AnyOf,
    All,
};

const LookAround = struct {
    negative_lookahead: bool = false,
    positive_lookahead: bool = false,
    negative_lookbehind: bool = false,
    positive_lookbehind: bool = false,
    non_capture: bool = false,

    inline fn anyNegative(self: LookAround) bool {
        return self.negative_lookahead or self.negative_lookbehind;
    }

    inline fn anyPositive(self: LookAround) bool {
        return self.positive_lookahead or self.positive_lookbehind;
    }

    fn anyLookBehind(self: LookAround) bool {
        return self.negative_lookbehind or self.positive_lookbehind;
    }

    fn dontCapture(self: LookAround) bool {
        return self.non_capture or self.negative_lookahead or
        self.positive_lookahead or self.negative_lookbehind or
        self.positive_lookbehind;
    }

    pub fn From(tokens_iter: *Iterator(Token)) LookAround {
        var la: LookAround = .{};
        const token = tokens_iter.peekFirst() orelse return la;
            
        switch (token.*) {
            .meta => |m| {
                switch (m) {
                    .NegativeLookAhead => la.negative_lookahead = true,
                    .PositiveLookAhead => la.positive_lookahead = true,
                    .NegativeLookBehind => la.negative_lookbehind = true,
                    .PositiveLookBehind => la.positive_lookbehind = true,
                    .NonCapture => la.non_capture = true,
                    else => {},
                }
            },
            else => {},
        }

        return la;
    }
};

fn checkLookBehind(tokens_iter: *Iterator(Token), haystack: *const String, args: Args) bool {
    if (tokens_iter.peekPrev()) |prev| {
         switch (prev.*) {
            .group => |*pg| {
                if (pg.look_around.anyLookBehind()) {
                    const idx = pg.matches(haystack, args.from);
                    return if (idx == null) false else true;
                }
            },
            else => {},
        }
    }

    return true;
}

pub const Group = struct {
    match_type: Match = .All,
    regex: *Regex,
    token_arr: ArrayList(ArrayList(Token)) = undefined,
    id: ?IdType = null,
    parent_id: ?IdType = null,
    captures: ArrayList(Slice) = undefined,
    capture_index: usize = 0,
    look_around: LookAround = .{},

    pub fn New(regex: *Regex, parent: ?*Group) Group {
        const parent_id = if (parent) |p| p.id else null;
        var new_group = Group{.regex = regex, .id = regex.next_group_id, .parent_id = parent_id};
        regex.next_group_id += 1;
        new_group.token_arr = ArrayList(ArrayList(Token)).init(regex.alloc);
        new_group.captures = ArrayList(Slice).init(regex.alloc);

        return new_group;
    }

    pub fn deinit(self: Group) void {
        for (self.token_arr.items) |arr| {
            for (arr.items) |t| {
                t.deinit();
            }
            arr.deinit();
        }
        self.token_arr.deinit();

        self.captures.deinit();
    }

    fn addCapture(self: *Group, slice: Slice) !void {
        if (slice.start.eq(slice.end)) {
            return; // negative/positive look ahead/behind
        }

        const len = self.captures.items.len;
        if (len > 0) {
            var capture: *Slice = &self.captures.items[len - 1];
            if (capture.end.eq(slice.start)) {
                capture.end = slice.end;
                return;
            }
        }

        try self.captures.append(slice);
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

    pub fn canCapture(self: *const Group) bool {
        for (self.token_arr.items) |*arr| {
            if (startsWithMeta(arr.items, Meta.NonCapture))
                return false;
        }

        return true;
    }

    fn endsWithMeta(slice: []const Token, meta: Meta) bool {
        if (slice.len == 0) {
            return false;
        }

        return slice[slice.len - 1].isMeta(meta);
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
            self.addCapture(input.slice(from, ret_idx)) catch return null;
        }

        // mtl.debug(@src(), "found_enough={}", .{found_enough});

        return if (found_enough) ret_idx else null;
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

    pub fn getCaptureByName(self: *const Group, name: String) ?*const ArrayList(Slice) {
        for (self.token_arr.items) |arr| {
            for (arr.items) |*t| {
                switch (t.*) {
                    .name => |group_name| {
                        if (group_name.eq(name)) {
                            return &self.captures;
                        }
                    },
                    .group => |*subgroup| {
                        if (subgroup.getCaptureByName(name)) |result| {
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
            return self.capture;
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

    pub fn hasContent(self: Group) bool {
        for (self.token_arr.items) |arr| {
            if (arr.items.len > 0) {
                return true;
            }
        }

        return false;
    }

    pub fn isTop(self: Group) bool {
       return self.parent_id == null;
    }

    fn matchWholeString(self: *const Group, arr: *ArrayList(Token), tokens_iter: *Iterator(Token), needles: *const String, haystack: *const String, from: Index) ?Index {
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

        const starts_with_not = startsWithMeta(arr.items, .Not);
        var at = from;
        if (qtty.exactNumber(1)) {
            if (self.look_around.anyLookBehind()) {
                if (from.gr < needles.size()) {
                    return null; // ANY NEGATIVE/POSITIVE?
                }

                at = haystack.findIndex(from.gr - needles.size()) orelse return null;
            }
            const past_match = matchStr(starts_with_not, needles, haystack,
            .{.from=at, .cs=self.regex.params.cs});
            if (self.look_around.anyNegative()) {
                return if (past_match == null) from else null; // must not advance
            } else if (self.look_around.anyPositive()) {
                return if (past_match == null) null else from; // must not advance
            } else {
                return past_match;
            }
        }

        if (self.look_around.anyLookBehind()) {
            unreachable;
            // const args: Args = .{.from=from, .cs=self.regex.params.cs};
            // const flag = self.matchesBehind(haystack, needles, args);
            // return if (flag) from else null;
        }

        const last_gr_index = needles.beforeLast();
        const base_str = needles.betweenIndices(.{}, last_gr_index) catch return null;
        defer base_str.deinit();
        {
            at = from;
            const past_match = matchStr(starts_with_not, &base_str, haystack,
            .{.from=at, .cs=self.regex.params.cs});
            if (past_match) |pm| {
                at = pm;
            } else {
                if (self.look_around.anyNegative()) {
                    return from; // means match
                } else if (self.look_around.anyPositive()) {
                    return null; // means no match
                }
            }
        }
        const last_char_str = needles.midIndex(last_gr_index) catch return null;
        defer last_char_str.deinit();
        // mtl.debug(@src(), "base_str:{dt}, last_char:{}", .{base_str, last_char_str});
        var count: usize = 0;
        
        while (true) {
            if (matchStr(starts_with_not, &last_char_str, haystack,
            .{.from=at, .cs=self.regex.params.cs})) |idx| {
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
            return if (self.look_around.positive_lookahead) from else at;
        }

        return null;
    }

    fn matchAnyChar(tokens_arr: *ArrayList(Token), tokens_iter: *Iterator(Token), input: *const String, haystack: *const String, args: Args) ?Index {
        const starts_with_not = startsWithMeta(tokens_arr.items, .Not);
        var negative_lookahead = false;
        if (tokens_iter.peekPrev()) |prev_token| {
            if (prev_token.isMeta(.NegativeLookAhead)) {
                negative_lookahead = true;
            }
        }

        const hgr = haystack.charAtIndex(args.from) orelse return null;
        // var found = false;
        var string_iter = input.iterator();
        while (string_iter.next()) |gr| {
            // mtl.debug(@src(), "input: {dt}, gr: {dt} vs haystack {dt}", .{input, gr, hgr});
            const gr_match = gr.eq(hgr, args.cs);
            if (starts_with_not) {
                if (gr_match) {
                    return null;
                }
            } else if (gr_match) {
                if (negative_lookahead) {
                    return args.from;
                } else {
                    return args.from.addGrapheme(gr);
                }
            }
        }

        if (starts_with_not) {
            return args.from.addGrapheme(hgr);
        }

        return null;
    }

    fn matchStr(starts_with_not: bool, needles: *const String, haystack: *const String, args: Args) ?Index {
        const past_idx = haystack.matches(needles, args);
        if (starts_with_not) {
            if (past_idx) |idx| {
                _ = &idx;
                return null;
            }
        }
        
        return past_idx;
    }

    pub fn matches(self: *Group, input: *const String, from: Index) ?Index {
        // mtl.debug(@src(), "from:{}, group.id:{?}", .{from, self.id});
        const args = Args {.from = from, .cs = self.regex.params.cs };
        for (self.token_arr.items, 0..) |*arr, i| {
            _ = &i;
            // mtl.debug(@src(), "items.len={}, group.id={?}", .{arr.items.len, self.id});
            if (arr.items.len == 0) {
                continue;
            }
            
            if (self.matchesArray(arr, input, args)) |past_idx| {
                return past_idx;
            }
        }

        return null;
    }

    fn matchesArray(self: *Group, tokens: *ArrayList(Token), haystack: *const String, args: Args) ?Index {
        var tokens_iter = Iterator(Token).New(tokens.items);
        self.look_around = LookAround.From(&tokens_iter);
        if (self.look_around.anyLookBehind()) {
            // must be performed after the token in front of it matches.
            // mtl.debug(@src(), "skipping group {?}", .{self.id});
            return args.from;
        }

        var at = args.from;
        if (startsWithMeta(tokens.items, .SymbolStartOfLine)) {
            if (at.cp != 0) {
                const gr = haystack.prev(at) orelse return null;
                if (!gr.eqAscii('\n')) {
                    return null;
                }
            }
        }
// if previous token is a look_behind, call it.
        const starts_with_not = startsWithMeta(tokens.items, .Not);
        while (tokens_iter.nextPtr()) |t| {
            switch (t.*) {
                .str => |*needles| {
                    if (self.match_type == .All) {
                        if (matchWholeString(self, tokens, &tokens_iter, needles, haystack, at)) |idx_past| {
                            if (!checkLookBehind(&tokens_iter, haystack, args)) {
                                return null;
                            }
                            if (!self.look_around.dontCapture()) {
                                self.addCapture(haystack.slice(at, idx_past)) catch return null;
                            }
                            at = idx_past;
                        } else {
                            return null;
                        }
                    } else { // == .AnyOf
                        if (matchAnyChar(tokens, &tokens_iter, needles, haystack, .{.from=at, .cs=args.cs})) |idx_after| {
                            if (!checkLookBehind(&tokens_iter, haystack, args)) {
                                return null;
                            }
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
                                return null;
                            }
                            
                            if (self.findNextChars(haystack, at, m, &tokens_iter)) |idx_after| {
                                if (!checkLookBehind(&tokens_iter, haystack, args)) {
                                    return null;
                                }
                                at = idx_after;
                            } else {
                                return null;
                            }
                        },
                        .SymbolWordBoundary => {
                            if (!haystack.isWordBoundary(at)) {
                                return null;
                            }
                            if (!checkLookBehind(&tokens_iter, haystack, args)) {
                                return null;
                            }
                        },
                        .SymbolNonWordBoundary => {
                            if (haystack.isWordBoundary(at)) {
                                return null;
                            }
                            if (!checkLookBehind(&tokens_iter, haystack, args)) {
                                return null;
                            }
                        },
                        .SymbolNumber => {
                            if (!haystack.isDigit(at)) {
                                return null;
                            }
                            if (self.findNextChars(haystack, at, m, &tokens_iter)) |past_idx| {
                                if (!checkLookBehind(&tokens_iter, haystack, args)) {
                                    return null;
                                }
                                at = past_idx;
                            } else {
                                return null;
                            }
                        },
                        .SymbolNonNumber => {
                            if (haystack.isDigit(at)) {
                                return null;
                            }

                            if (self.findNextChars(haystack, at, m, &tokens_iter)) |past_idx| {
                                if (!checkLookBehind(&tokens_iter, haystack, args)) {
                                    return null;
                                }
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
                                if (!checkLookBehind(&tokens_iter, haystack, args)) {
                                    return null;
                                }
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
                                if (!checkLookBehind(&tokens_iter, haystack, args)) {
                                    return null;
                                }
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

                    var count: usize = 0;
                    while (qtty.a > 0 or !qtty.lazy) {
                        if (sub_group.matches(haystack, at)) |past_idx| {
                            at = past_idx;
                        } else {
                            break;
                        }
                        count += 1;
                        if (qtty.lazy and count >= qtty.a) {
                            break;
                        } else if (count >= qtty.b) {
                            break; // break if maximum count reached
                        }
                        // otherwise keep finding as many as possible
                    }

                    if (count < qtty.a) {
                        return null;
                    }

                    if (!checkLookBehind(&tokens_iter, haystack, args)) {
                        return null;
                    }
                },
                .range => |range| {
                    var flag = range.within(haystack, .{.from=at, .cs=self.regex.params.cs});
                    if (starts_with_not) {
                        flag = !flag;
                    }
                    if (!flag) {
                        // mtl.debug(@src(), "{} failed.", .{range});
                        return null;
                    }
                    if (!checkLookBehind(&tokens_iter, haystack, args)) {
                        return null;
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
                if (!self.look_around.dontCapture())
                    self.addCapture(gr.slice()) catch return null;
            },
            else => {},
        }

        if (!at.isPast(haystack) and startsWithMeta(tokens.items, .SymbolEndOfLine)) {
            const gr = haystack.charAtIndex(at) orelse return null;
            if (!gr.eqAscii('\n')) {
                return null;
            }
        }

        return at;
    }

    fn matchesBehind(self: *const Group, tokens_iter: *Iterator(Token), haystack: *const String, args: Args) bool {
        _ = &self;
        _ = &args;
        _ = &haystack;

        var qtty = Qtty.One();
        if (tokens_iter.peekNext()) |next_token| {
            switch(next_token.*) {
                .qtty => |q| {
                    qtty = q;
                },
                else => {},
            }
        }

        mtl.debug(@src(), "{?}", .{self.id});
        return true;
    }

    fn parseIntoTokens(self: *Group, index: Index) !Index {
        var str_iter = StringIterator.New(&self.regex.pattern, index);
        var ret_idx: ?Index = null;
        const new_array = ArrayList(Token).init(self.regex.alloc);
        try self.token_arr.append(new_array);
        var current_arr: *ArrayList(Token) = &self.token_arr.items[0];

        while (str_iter.next()) |gr| {
            if (gr.eqAscii('[')) {
                if (self.hasContent()) {
                    var new_group = Group.New(self.regex, self);
                    new_group.match_type = .AnyOf;
                    const newg = str_iter.next() orelse return error.Other;
                    str_iter.continueFrom(try new_group.parseIntoTokens(newg.idx));
                    try addGroup(current_arr, new_group);
                } else {
                    self.match_type = .AnyOf;
                }
            } else if (gr.eqAscii(']')) {
                ret_idx = gr.idx.addRaw(1);
                break;
            } else if (gr.eqAscii('(')) {
                if (self.hasContent() or self.isTop()) {
                    mtl.trace(@src());
                    var new_group = Group.New(self.regex, self);
                    new_group.match_type = .All;
                    const newg = str_iter.next() orelse return error.Other;
                    str_iter.continueFrom(try new_group.parseIntoTokens(newg.idx));
                    try addGroup(current_arr, new_group);
                } else {
                    mtl.trace(@src());
                    self.match_type = .All;
                }
            } else if (gr.eqAscii(')')) {
                ret_idx = gr.idx.addRaw(1);
                break;
            } else if (gr.eqAscii('?')) {
                const s: *String = &self.regex.pattern;
                if (s.matchesAscii("?:", gr.idx)) |idx| {
                    str_iter.continueFrom(idx);
                    try addMeta(current_arr, .NonCapture);
                    // self.non_capture = true;
                } else if (s.matchesAscii("?!", gr.idx)) |idx_past| {
                    str_iter.continueFrom(idx_past);
                    try addMeta(current_arr, .NegativeLookAhead);
                } else if (s.matchesAscii("?<!", gr.idx)) |idx| {
                    str_iter.continueFrom(idx);
                    try addMeta(current_arr, .NegativeLookBehind);
                } else if (s.matchesAscii("?=", gr.idx)) |idx| {
                    str_iter.continueFrom(idx);
                    try addMeta(current_arr, .PositiveLookAhead);
                } else if (s.matchesAscii("?<=", gr.idx)) |idx| {
                    str_iter.continueFrom(idx);
                    try addMeta(current_arr, .PositiveLookBehind);
                } else if (s.matchesAscii("?<", gr.idx)) |idx| { //(?<name>\\w+) = name = e.g."Jordan"
                    str_iter.continueFrom(idx);
                    // named capture
                    if (s.indexOfAscii(">", .{.from = idx.addRaw("?<".len)})) |closing_idx| {
                        const name = try s.betweenIndices(idx, closing_idx);
                        // mtl.debug(@src(), "Name: \"{}\"", .{name});
                        try addMeta(current_arr, .NamedCapture);
                        try addName(current_arr, name);
                        str_iter.continueFrom(closing_idx.addRaw(1)); // go past ">"
                    }
                } else { // just "?"
                    try addQtty(current_arr, Qtty.ZeroOrOne());
                }
            } else if (gr.eqAscii('{')) {
                const s: *String = &self.regex.pattern;
                if (s.indexOfAscii("}", .{.from = gr.idx.addRaw(1)})) |idx| {
                    const qtty_in_curly = try s.betweenIndices(gr.idx.addRaw("}".len), idx);
                    defer qtty_in_curly.deinit();
                    str_iter.continueFrom(idx.addRaw("}".len));
                    const qtty = try Qtty.FromCurly(qtty_in_curly);
                    try addQtty(current_arr, qtty);
                    // mtl.debug(@src(), "qtty_in_curly: {}", .{qtty});
                } else {
                    mtl.debug(@src(), "Not found closing '}}'", .{});
                }
            } else if (gr.eqAscii('\\')) {
                const symbol = str_iter.next() orelse break;
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
                if (str_iter.next()) |ng| {
                    if (ng.eqAscii('?')) {
                        q.lazy = true;
                    } else {
                        str_iter.continueFrom(gr.idx.addRaw(1));
                    }
                }
                try addQtty(current_arr, q);
            } else if (gr.eqAscii('*')) {
                var q = Qtty.OneOrMore();
                if (str_iter.next()) |ng| {
                    if (ng.eqAscii('?')) {
                        q.lazy = true;
                    } else {
                        str_iter.continueFrom(gr.idx.addRaw(1));
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
                if (current_arr.items.len == 0) {
                    return error.Parsing;
                }
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

        return str_iter.idx;
    }

    fn parseRange(s: String, tokens: *ArrayList(Token)) !void {
        const idx = s.indexOfAscii("-", .{}) orelse return;
        var iter = s.iteratorFrom(idx);
        const prev_idx = iter.prevFrom(idx) orelse return;
        const next_idx = iter.nextFrom(idx) orelse return;
        const cp1 = prev_idx.getCodepoint() orelse return;
        const cp2 = next_idx.getCodepoint() orelse return;
        if (cp1 > cp2) {
            mtl.debug(@src(), "Error: {}({}) > {}({})", .{prev_idx, cp1, next_idx, cp2});
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
        if (prev_idx.idx.gr != 0 and prev_idx.idx.gr != 0) {
            left = try s.betweenIndices(.{}, prev_idx.idx);
        }

        const str_end = s.beforeLast();
        if (next_idx.idx.gr < str_end.gr) {
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
        self.capture_index = 0;
        self.captures.clearAndFree();

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

    fn printMeta(writer: anytype, m: Meta) !void {
         try writer.print("{s}{}{s} ", .{String.COLOR_CYAN, m, String.COLOR_DEFAULT});
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

    fn startsWithMeta(slice: []const Token, meta: Meta) bool {
        if (slice.len == 0) {
            return false;
        }

        return slice[0].isMeta(meta);
    }
};

pub const FindParams = struct {
    qtty: Qtty = Qtty.One(),
    cs: CaseSensitive = .Yes,
    from: Index = Index.strStart(),
};

tokens: ArrayList(Token),
pattern: String,
alloc: Allocator,
top_group: Group = undefined,
next_group_id: IdType = 0,
found: ArrayList(Slice) = undefined,
input: *const String = undefined,
params: FindParams = .{},
count: isize = 0,


// Regex takes ownership over `pattern`
pub fn New(alloc: Allocator, pattern: String) !*Regex {
    errdefer pattern.deinit();
    const regex = try alloc.create(Regex);
    errdefer alloc.destroy(regex);
    regex.* = Regex {
        .alloc = alloc,
        .pattern = pattern,
        .tokens = ArrayList(Token).init(alloc),
        .found = ArrayList(Slice).init(alloc),
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
    
    self.found.deinit();
    self.top_group.deinit();
    self.pattern.deinit();
    self.alloc.destroy(self);
}

pub fn getCapture(self: *const Regex, name: []const u8) ?Slice {
    const name_str = String.From(name) catch return null;
    defer name_str.deinit();
    if (self.top_group.getCaptureByName(name_str)) |result| {
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

pub fn findNext(self: *Regex) ?Index {
    self.found.clearAndFree();
    self.top_group.prepareForNewSearch();
    var input_iter = self.input.iteratorFrom(self.params.from);
    
    while (input_iter.next()) |gr| {
        if (self.top_group.matches(self.input, gr.idx)) |end_pos| {
            input_iter.continueFrom(end_pos);
            const next_slice = self.input.slice(gr.idx, end_pos);
            self.found.append(next_slice) catch return null;
            return end_pos;
        }
    }

    _ = self.top_group.setCaptureIndex(1);    

    return null;
}

pub fn nextSearch(self: *Regex) ?Index {
    if (self.params.qtty.done(self.count)) {
        return null;
    }

    if (self.findNext()) |end_pos| {
        self.count += 1;
        self.params.from = end_pos;
        return end_pos;
    }

    return null;
}

pub fn printGroups(self: Regex) void {
    self.top_group.printTokens();
}

fn printGroupResult(self: *const Group) void {
    const len = self.captures.items.len;
    const none = if (len == 0) " (none)" else "";
    mtl.debug(@src(), "{id} captures:{s}", .{self, none});
    for (self.captures.items) |*slice| {
        mtl.debug(@src(), "capture: {dt}, ({}-{})", .{slice, slice.start.gr, slice.end.gr});
    }

    for (self.token_arr.items) |arr| {
        for (arr.items) |item| {
            switch (item) {
                .group => |*g| {
                    printGroupResult(g);
                },
                else => {},
            }
        }
    }
}

pub fn setParams(self: *Regex, input: *const String, params: FindParams) void {
    self.input = input;
    self.params = params;
    self.count = 0;
}

test "Test regex" {
    const alloc = std.testing.allocator;
    String.ctx = try String.Context.New(alloc);
    defer String.ctx.deinit();
    
    const haystack = "A==-=-CDDKMikeБГДaopqxyzz567\n"; //Jos\u{65}\u{301} se fu\u{E9} seguía";
    const pattern =
\\=(=-){2,5}(?=\w+)(AB|CD{2})[EF|^GH](?<ClientName>\w+)(?:БГД[^zyA-Z0-9c1-3]opq(?!05))xyz{2,3}(?=\d{2,})$
;

// "se\\B";// "\u{65}\u{301}";
//on website:
//=(=-){2,5}(AB|CD{2})[^GH](?<ClientName>\w+)(?:БГД[^gbA-Z0-9c1-3]opq(?!345))xyz{2,3}$

    try performSearch(alloc, "(?<!\\w+)\\s\\d{2,}", "abc. 34 4444def 789");

    if (false) {
        try performSearch(alloc, pattern, haystack);
    }
}

fn performSearch(alloc: Allocator, pattern: []const u8, heap: []const u8) !void {
    const regex_pattern = try String.From(pattern);

    const regex = Regex.New(alloc, regex_pattern) catch |e| {
        mtl.debug(@src(), "Can't create regex: {}", .{e});
        return e;
    };
    defer regex.deinit();
    mtl.debug(@src(), "Regex: {dt}", .{regex_pattern});
    regex.printGroups();

    const heap_str = try String.From(heap);
    defer heap_str.deinit();
    try heap_str.printGraphemes(@src());

    regex.setParams(&heap_str, .{.qtty = .All(), .cs = .Yes});

    while (regex.nextSearch()) |currently_at| {
        mtl.debug(@src(), "Search is at {}", .{currently_at});
        for (regex.found.items, 0..) |slice, i| {
            mtl.debug(@src(), "Slice({}-{}) #{}: {dt}", .{slice.start.gr, slice.end.gr, i, slice});
        }
    }
}

//() - catpure group, referred by index number preceded by $, like $1
//(?:) - non capture group
    
// (?!) – negative lookahead
// (?=) – positive lookahead

// (?<!) – negative lookbehind
// (?<=) – positive lookbehind

// Excel formula example: =SUM(B1+0.3,20.9,-2.4+3*MAX(18,7),B2,C1:C2,MIN(A1,5))*(-3+2)