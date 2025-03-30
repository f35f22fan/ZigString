const std = @import("std");
const ArrayList = std.ArrayList;
const Str = @import("String.zig");
const mtl = Str.mtl;
const Cp = Str.Codepoint;
const Regex = @This();
const Allocator = std.mem.Allocator;
const IdType = i16;

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

        pub fn peekNext(self: Self) ?T {
            const next_index: usize = self.at + 1;
            if (next_index >= self.size()) {
                return null;
            }

            return self.items[next_index];
        }

        pub fn peekPrev(self: Self) ?T {
            if (self.at == 0 or (self.at - 1) >= self.size()) {
                return null;
            }

            return self.items[self.at - 1];
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
    str: Str,
    name: Str,

    inline fn isMeta(self: Token, param: Meta) bool {
        switch(self) {
            .meta => |m| return (m == param),
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
            .qtty => |q| {
                _ = q;
                // mtl.debug(@src(), "{}", .{q});
            },
            .meta => |m| {
                _ = m;
                // mtl.debug(@src(), "{}", .{m});
            }
        }
    }
};

pub const Qtty = struct {
    a: i64 = 1,
    b: i64 = 1,
    lazy: bool = false,

    pub fn FromCurly(input: Str) !Qtty {
        if (input.indexOfAscii(",", .{})) |comma_idx| {
            const s1 = try input.betweenIndices(Str.strStart(), comma_idx);
            defer s1.deinit();
            const n1: i32 = try s1.parseInt(i32, 10);
            if (comma_idx.equals(input.strEnd())) {
                return Qtty.ExactNumber(n1);
            } else {
                const s2 = try input.betweenIndices(comma_idx.addRaw(1), input.strEnd().addRaw(1));
                defer s2.deinit();
                const n2: i32 = try s2.parseInt(i32, 10);
                const qtty = Qtty.FixedRange(n1, n2);
                
                return qtty;
            }
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
            s = if (self.b == inf()) "+" else try std.fmt.bufPrint(&buf, "{}", .{self.b});
            try writer.print("Qtty[{}..{s}{s}]", .{self.a, s, lazy});
        }
    }

    pub fn exactNumber(self: Qtty, n: i64) bool {
        return self.a == n and self.b == n;
    }

    pub fn ExactNumber(a: i64) Qtty {
        return Qtty {.a = a, .b = a};
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
    enclosed: Enclosed = Enclosed.None,
    match: Match = Match.All,
    not: bool = false,
    qtty: Qtty = .New(1, Qtty.inf()),
    regex: *Regex,
    tokens: ArrayList(Token) = undefined,
    id: IdType = -1,
    parent_id: IdType = -1,
    result: Str = .{},

    pub fn New(regex: *Regex, parent: ?*Group) Group {
        const parent_id: IdType = if (parent) |p| p.id else -1;
        var g = Group{.regex = regex, .id = regex.next_group_id, .parent_id = parent_id};
        regex.next_group_id += 1;
        
        // mtl.debug(@src(), "g.id={}, p.id={}", .{g.id, parent_id});
        g.tokens = ArrayList(Token).init(regex.alloc);

        return g;
    }

    pub fn format(self: Group, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}Id={}({}) {s} ", .{Str.COLOR_ORANGE, self.id, self.parent_id, Str.COLOR_DEFAULT});
        for (self.tokens.items) |t| {
            switch (t) {
                .group => |g| {
                    try writer.print("{s}Group={}{s} ", .{Str.COLOR_BLUE, g.id, Str.COLOR_DEFAULT});
                },
                .qtty => |q| {
                    try writer.print("{s}{}{s} ", .{Str.COLOR_GREEN, q, Str.COLOR_DEFAULT});
                },
                .meta => |m| {
                    try writer.print("{s}{}{s} ", .{Str.COLOR_CYAN, m, Str.COLOR_DEFAULT});
                },
                .str => |s| {
                    try writer.print("{dt} ", .{s});
                },
                .name => |s| {
                    try writer.print("{dt} ", .{s});
                }
            }
        }
    }

    pub fn addGrapheme(self: *Group, gr: Str.Grapheme) !void {
        // If the last token is a string add to it, otherwise append a new string Token and add to it:
        const len = self.tokens.items.len;
        if (len > 0 and self.tokens.getLast().isString()) {
            const t = &self.tokens.items[len-1];
            switch (t.*) {
                .str => |*s| {
                    try s.addGrapheme(gr);
                },
                else => {
                    mtl.warn(@src(), "Not a string", .{});
                }
            }
        } else {
            var s = Str.New();
            try s.addGrapheme(gr);
            try self.tokens.append(Token{ .str = s });
        }
    }

    fn matchAll2(self: *Group, needles: Str, haystack: Str, from: Str.Index) ?Str.Index {
        const past_match = haystack.matchesStr(needles, from);//, cs
        mtl.debug(@src(), "input.matchesStr={dt}, at={}, input={dt}, past_match={?}", .{needles, from, haystack, past_match});
        var ok = false;
        
        if (self.not) {
            ok = past_match == null;
        } else {
            ok = past_match != null;
        }

        return if (ok) past_match else null;
    }

    fn matchAll(self: *Group, iter: *Iterator(Token), input: Str, haystack: Str, from: Str.Index) ?Str.Index {
        var qtty = Qtty.ExactNumber(1);
        if (iter.peekNext()) |next_token| {
            switch(next_token) {
                .qtty => |q| {
                    qtty = q;
                    _ = iter.next(); // if so then need to advance
                },
                else => {},
            }
        }

        if (qtty.a == 0 and qtty.lazy) {
            return from;
        }

        mtl.debug(@src(), "************** {}", .{qtty});
        var negative_lookahead = false;
        if (iter.peekPrev()) |prev_token| {
            if (prev_token.isMeta(Meta.NegativeLookAhead)) {
                negative_lookahead = true;
            }
        }
        
        if (qtty.exactNumber(1)) {
            mtl.debug(@src(), "exact number", .{});
            const past_match = self.matchAll2(input, haystack, from);
            if (negative_lookahead) {
                return if (past_match == null) from else null;
            } else {
                return past_match;
            }
        }

        const last_gr_index = input.strEnd();
        const base_str = input.betweenIndices(.{}, last_gr_index) catch return null;
        defer base_str.deinit();
        var at = from;
        {
            const past_match = self.matchAll2(base_str, haystack, from);
            if (past_match) |pm| {
                at = pm;
            } else {
                if (negative_lookahead) {
                    return from; // this is success
                }
            }
        }
        const last_char_str = input.midIndex(last_gr_index) catch return null;
        defer last_char_str.deinit();
        mtl.debug(@src(), "base_str:{dt}, last_char:{}", .{base_str, last_char_str});
        var count: usize = 0;
        
        while (true) {
            if (self.matchAll2(last_char_str, haystack, at)) |idx| {
                count += 1;
                at = idx;
                if (count == qtty.b) {
                    break;
                }
            } else {
                break;
            }
        }

        return if (count >= qtty.a) at else null;
    }

    fn parseIntoTokens(self: *Group, index: Str.Index) !Str.Index {
        var it = Str.Iterator.New(&self.regex.pattern, index);
        while (it.next()) |gr| {
            if (gr.eqAscii('[')) {
                if (self.hasContent()) {
                    var g = Group.New(self.regex, self);
                    g.setSquare();
                    const newg = it.next() orelse return Str.Error.Other;
                    it.continueFrom(try g.parseIntoTokens(newg.idx));
                    try self.addGroup(g);
                } else {
                    self.setSquare();
                }
            } else if (gr.eqAscii(']')) {
                return gr.idx.addRaw(1);
            } else if (gr.eqAscii('(')) {
                if (self.hasContent()) {
                    var g = Group.New(self.regex, self);
                    g.setRound();
                    const newg = it.next() orelse return Str.Error.Other;
                    it.continueFrom(try g.parseIntoTokens(newg.idx));
                    try self.addGroup(g);
                } else {
                    self.setRound();
                }
            } else if (gr.eqAscii(')')) {
                return gr.idx.addRaw(1);
            } else if (gr.eqAscii('?')) {
                const s: *Str = &self.regex.pattern;
                if (s.matches("?:", gr.idx)) |idx| {
                    it.continueFrom(idx);
                    try self.addMeta(Meta.NonCapture);
                } else if (s.matches("?!", gr.idx)) |idx| {
                    it.continueFrom(idx);
                    try self.addMeta(Meta.NegativeLookAhead);
                } else if (s.matches("?<!", gr.idx)) |idx| {
                    it.continueFrom(idx);
                    try self.addMeta(Meta.NegativeLookBehind);
                } else if (s.matches("?=", gr.idx)) |idx| {
                    it.continueFrom(idx);
                    try self.addMeta(Meta.PositiveLookAhead);
                } else if (s.matches("?<=", gr.idx)) |idx| {
                    it.continueFrom(idx);
                    try self.addMeta(Meta.PositiveLookBehind);
                } else if (s.matches("?<", gr.idx)) |idx| { //(?<name>\\w+) = name = e.g."Jordan"
                    it.continueFrom(idx);
                    // named capture
                    if (s.indexOf2(">", .{.from = idx.addRaw("?<".len)})) |closing_idx| {
                        const name = try s.betweenIndices(idx, closing_idx);
                        // mtl.debug(@src(), "Name: \"{}\"", .{name});
                        try self.addMeta(Meta.NamedCapture);
                        try self.addName(name);
                        it.continueFrom(closing_idx.addRaw(1)); // go past ">"
                    }
                } else { // just "?"
                    try self.addQtty(Qtty.ZeroOrOne());
                }
            } else if (gr.eqAscii('{')) {
                const s: *Str = &self.regex.pattern;
                if (s.indexOf2("}", .{.from = gr.idx.addRaw(1)})) |closing_idx| {
                    const qtty_in_curly = try s.betweenIndices(gr.idx.addRaw(1), closing_idx);
                    defer qtty_in_curly.deinit();
                    it.continueFrom(closing_idx.addRaw(1));
                    const qtty = try Qtty.FromCurly(qtty_in_curly);
                    try self.addQtty(qtty);
                    // mtl.debug(@src(), "qtty_in_curly: {}", .{qtty});
                } else {
                    mtl.debug(@src(), "Not found closing '}}'", .{});
                }
            } else if (gr.eqAscii('\\')) {
                const symbol = it.next() orelse break;
                if (symbol.eqAscii('d')) {
                    try self.addMeta(Meta.SymbolNumber);
                } else if (symbol.eqAscii('D')) {
                    try self.addMeta(Meta.SymbolNonNumber);
                } else if (symbol.eqAscii('w')) {
                    try self.addMeta(Meta.SymbolWordChar);
                } else if (symbol.eqAscii('W')) {
                    try self.addMeta(Meta.SymbolNonWordChar);
                } else if (symbol.eqAscii('s')) {
                    try self.addMeta(Meta.SymbolWhitespace);
                } else if (symbol.eqAscii('S')) {
                    try self.addMeta(Meta.SymbolNonWhitespace);
                } else if (symbol.eqAscii('.')) {
                    try self.addMeta(Meta.SymbolAnyChar);
                } else if (symbol.eqAscii('b')) {
                    try self.addMeta(Meta.SymbolWordBoundary);
                } else if (symbol.eqAscii('B')) {
                    try self.addMeta(Meta.SymbolNonWordBoundary);
                }
            } else if (gr.eqAscii('^')) {
                if (gr.idx.gr == 0) {
                    try self.addMeta(Meta.SymbolStartOfLine);
                } else {
                    try self.addMeta(Meta.Not);
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
                try self.addQtty(q);
            } else if (gr.eqAscii('*')) {
                var q = Qtty.OneOrMore();
                if (it.next()) |ng| {
                    if (ng.eqAscii('?')) {
                        q.lazy = true;
                    } else {
                        it.continueFrom(gr.idx.addRaw(1));
                    }
                }
                try self.addQtty(Qtty.ZeroOrMore());
            } else if (gr.eqAscii('\n')) {
                try self.addMeta(Meta.SymbolNewLine);
            } else if (gr.eqAscii('\t')) {
                try self.addMeta(Meta.SymbolTab);
            } else if (gr.eqAscii('$')) {
                try self.addMeta(Meta.SymbolEndOfLine);
            } else if (gr.eqAscii('|')) {
                try self.addMeta(Meta.Or);
            } else {
                try self.addGrapheme(gr);
            }
        }

        return it.idx;
    }

    inline fn addGroup(self: *Group, g: Group) !void {
        try self.tokens.append(Token {.group = g});
    }

    inline fn addMeta(self: *Group, m: Meta) !void {
        try self.tokens.append(Token {.meta = m});
    }

    fn addName(self: *Group, s: Str) !void {
        try self.tokens.append(Token {.name = s});
    }

    fn addQtty(self: *Group, qtty: Qtty) !void {
        try self.tokens.append(Token {.qtty = qtty});
    }

    fn addStr(self: *Group, s: Str) !void {
        try self.tokens.append(Token {.str = s});
    }

    pub fn deinit(self: Group) void {
        for (self.tokens.items) |item| {
            item.deinit();
        }
        self.tokens.deinit();
        self.result.deinit();
    }

    pub fn hasContent(self: Group) bool {
        return self.tokens.items.len > 0;
    }

    pub fn matches(self: *Group, input: Str, from: Str.Index) ?Str.Index {
        {
            mtl.debug(@src(), "group:{}, at={}", .{self.id, from});
            const haystack = input.midIndex(from) catch return null;
            defer haystack.deinit();
            mtl.debug(@src(), "group:{}, haystack:{dt}, at={}", .{self.id, haystack, from});
        }
        var at = from;
        const cs = Str.CaseSensitive.Yes;
        _ = cs;
        // for (self.tokens.items) |*t| {
        var iter = Iterator(Token).New(self.tokens.items);
        while (iter.nextPtr()) |t| {
            switch (t.*) {
                .str => |needles| {
                    if (self.match == Match.All) {
                        if (self.matchAll(&iter, needles, input, at)) |idx| {
                            at = idx;
                        } else {
                            mtl.debug(@src(), "{s}self.matchAll failed{s}", .{Str.COLOR_RED, Str.COLOR_DEFAULT});
                            return null;
                        }
                    } else { // == Match.AnyOf

                    }
                },
                .meta => |m| {
                    switch (m) {
                        .SymbolWordChar => {
                            var qtty: ?Qtty = null;
                            if (iter.peekNext()) |next_token| {
                                switch (next_token) {
                                    .qtty => |q| {
                                        qtty = q;
                                        iter.add(1);
                                    },
                                    else => {}
                                }
                            }
                            mtl.debug(@src(), "find a word char, qtty:{?}, from:{}, input:{}", .{qtty, from, input});
                            if (findWordChar(input, from, qtty)) |past_last| {
                                at = past_last;
                            }
                        },
                        else => {

                        }
                    }
                },
                .group => |*g| {
                    if (g.matches(input, at)) |idx| {
                        at = idx;
                    } else {
                        return null;
                    }
                },
                else => {}
            }
        }

        return at;
    }

    // returns past last found grapheme, or null
    pub fn findWordChar(input: Str, from: Str.Index, qtty: ?Qtty) ?Str.Index {
        var iter = input.iteratorFrom(from);
        var count: usize = 0;
        var matched = false;
        var ret_idx: Str.Index = from;
        while (iter.next()) |gr| {
            if (!gr.isWordChar()) {
                break;
            }

            ret_idx = gr.idx.addGrapheme(gr);
            matched = true;
            count += 1;
            if (qtty) |q| {
                if (q.lazy) {
                    if (q.a >= count) {
                        mtl.debug(@src(), "", .{});
                        return ret_idx;
                    }
                } else {
                    if (count >= q.b) {
                        mtl.debug(@src(), "q:{}, count:{}", .{q, count});
                        return ret_idx;
                    }
                }
            }
        }

        mtl.debug(@src(), "q:{?}, count:{}", .{qtty, count});
        return if (matched) ret_idx else null;
    }

    pub fn printTokens(self: Group) void {
        mtl.debug(@src(), "{}", .{self});
        for (self.tokens.items) |item| {
            switch (item) {
                .group => |*v| {
                    v.printTokens();
                },
                else => {},
            }
        }
    }

    inline fn setRound(self: *Group) void {
        self.match = Match.All;
        self.enclosed = Enclosed.Round;
    }

    inline fn setSquare(self: *Group) void {
        self.match = Match.AnyOf;
        self.enclosed = Enclosed.Square;
    }
};

// Formula: =SUM(B1+0.3,20.9,-2.4+3*MAX(18,7),B2,C1:C2,MIN(A1,5))*(-3+2)
global_search: bool = true,
case_sensitive: bool = true,
tokens: ArrayList(Token),
pattern: Str,
alloc: Allocator,
groups: ArrayList(Group) = undefined,
next_group_id: IdType = 0,
result: ArrayList(Str),

// Regex takes ownership over `pattern`
pub fn New(alloc: Allocator, pattern: Str) !*Regex {
    errdefer pattern.deinit();
    const ptr = try alloc.create(Regex);
    errdefer alloc.destroy(ptr);
    ptr.* = Regex {
        .pattern = pattern,
        .tokens = ArrayList(Token).init(alloc),
        .result = ArrayList(Str).init(alloc),
        .alloc = alloc,
        .groups = ArrayList(Group).init(alloc),
    };
    
    mtl.debug(@src(), "Regex: {}", .{pattern});
    
    var g: Group = Group.New(ptr, null);
    errdefer g.deinit();
    _ = try g.parseIntoTokens(Str.strStart());
    try ptr.groups.append(g);

    return ptr;
}

inline fn clearResult(self: *Regex) void {
     for (self.result.items) |s| {
        s.deinit();
    }
    self.result.deinit();
}

pub fn deinit(self: *Regex) void {
    for (self.tokens.items) |g| {
        g.deinit();
    }
    self.pattern.deinit();
    
    for (self.groups.items) |g| {
        g.deinit();
    }
    self.groups.deinit();

   self.clearResult();
}

pub fn getGroup(self: *Regex, id: IdType) ?*Group { // method not used yet
    for (self.groups.items) |*g| {
        if (g.id == id) {
            return g;
        }
    }

    return null;
}

pub fn find(self: *Regex, input: Str, from: Str.Index) ?Str.Index {
    self.clearResult();
    var at = from;
    var starts_at: ?Str.Index = null;
    for (self.groups.items) |*group| {
        if (group.matches(input, at)) |idx| {
            if (starts_at == null) {
                starts_at = at;
            }
            at.add(idx);
        } else {
            mtl.debug(@src(), "Group failed: {}", .{group});
            return null;
        }
    }

    return starts_at;
}

pub fn printGroups(self: Regex) void {
    for (self.groups.items) |group| {
        group.printTokens();
    }
}

test "Test regex" {
    const alloc = std.testing.allocator;
    Str.ctx = try Str.Context.New(alloc);
    defer Str.ctx.deinit();

// ?: means make the capturing group a non capturing group, i.e. don't include its match as a back-reference.
// ?! is the negative lookahead. The regex will only match if the capturing group does not match.
    const pattern = try Str.From("==[?<ClientName>\\w+](?:БГД[^A-Z]opq(?!345))xyz{2,3}");
    const regex = try Regex.New(alloc, pattern);
    defer alloc.destroy(regex);
    defer regex.deinit();
    regex.printGroups();

    const input = try Str.From("==MikeБГДopqxyzz");
    defer input.deinit();
    if (regex.find(input, Str.Index.strStart())) |found| {
        mtl.debug(@src(), "Regex matched at {}", .{found});
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

// QRegularExpression("(?<![a-zA-Z\\.])\\d+(\\.\\d+)?(?!\\.)");
// Must not start with a letter or a dot => (?<![a-zA-Z\\.])
// numbers must follow => \\d+
// then possibly a dot followed by an array of numbers => (\\.\\d+)?
// but not ending in a number => (?!\\.)

// (?<name>...) – Named capture group called “name” matching any three characters:
// /Testing (?<num>\d{3})/
// const regex = /Testing (?<num>\d{3})/
// let str = "Testing 123";
// str = str.replace(regex, "Hello $<num>")
// console.log(str); // "Hello 123"

// Sometimes it can be useful to reference a named capture group inside of a query itself.
// This is where “back references” can come into play.
// \k<name>Reference named capture group “name” in a search query
// Say you want to match:
// Hello there James. James, how are you doing?
// But not:
// Hello there James. Frank, how are you doing?
// While you could write a regex that repeats the word “James” like the following:
// /.*James. James,.*/
// A better alternative might look something like this:
// /.*(?<name>James). \k<name>,.*/
// Now, instead of having two names hardcoded, you only have one.

// QRegularExpression re("(\\d\\d) (?<name>\\w+)");
// QRegularExpressionMatch match = re.match("23 Jordan");
// if (match.hasMatch()) {
//     QString number = match.captured(1); // first == "23"
//     QString name = match.captured("name"); // name == "Jordan"
// }


    //() - catpure group, referred by index number preceded by $, like $1
    //(?:) - non capture group
    
    // (?!) – negative lookahead
    // (?<!) – negative lookbehind
    // (?=) – positive lookahead
    // (?<=) – positive lookbehind


}

