const std = @import("std");
const ArrayList = std.ArrayList;
const Str = @import("String.zig");
const mtl = Str.mtl;
const Cp = Str.Codepoint;
const Regex = @This();
const Allocator = std.mem.Allocator;
const IdType = i16;

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

const TokenEnum = enum(u8) {
    group,
    qtty,
    meta,
    str,
    name,
};

const Token = union(TokenEnum) {
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

const Error = error {
    BadRange,
};

pub const Qtty = struct {
    a: i64 = 1,
    b: ?i64 = null,
    
    pub inline fn inf() i64 {
        return std.math.maxInt(i64);
    }
    /// format implements the `std.fmt` format interface for printing types.
    pub fn format(self: Qtty, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        var buf: [8]u8 = undefined;
        var s: []const u8 = undefined;
        if (self.b) |bnum| {
            if (self.b_inf()) {
                try writer.print("Qtty[{}+]", .{self.a});
            } else {
                s = if (self.b_inf()) "+" else try std.fmt.bufPrint(&buf, "{}", .{bnum});
                try writer.print("Qtty[{}..{s}]", .{self.a, s});
            }
        } else {
            try writer.print("Qtty[{}]", .{self.a});
        }
    }

    pub fn setExactNumber(self: *Qtty, a: i64) void {
        self.a = a;
        self.b = null;
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
        if (self.a != 0) return false;
        return self.b_inf();
    }

    pub fn ZeroOrOne() Qtty { return Qtty {.a = 0, .b = 1}; }
    pub fn zeroOrOne(self: Qtty) bool { // x?
        if (self.a != 0) return false;
        if (self.b) |n| return (n == 1);
        return false;
    }

    pub fn OneOrMore() Qtty { return Qtty {.a = 1, .b = inf()}; }
    pub fn oneOrMore(self: Qtty) bool { // x+
        if (self.a != 1) return false;
        return self.b_inf();
    }

    pub fn nOrMore(self: Qtty) bool {
        return self.b_inf();
    }

    pub fn fixedRange(self: Qtty) bool { // x{a,b}
        if (self.b) |k| {
            return k != inf();
        }
        return false;
    }

    pub fn New(a: i64, b: ?i64) Qtty {
        return Qtty {
            .a = a,
            .b = b,
        };
    }

    pub inline fn b_inf(self: Qtty) bool {
        return if (self.b) |x| {
            return x == inf();
        } else {
            return false;
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

    pub fn New(regex: *Regex, parent: ?*Group) Group {
        const parent_id: IdType = if (parent) |p| p.id else -1;
        var g = Group{.regex = regex, .id = regex.next_group_id, .parent_id = parent_id};
        regex.next_group_id += 1;
        
        // mtl.debug(@src(), "g.id={}, p.id={}", .{g.id, parent_id});
        g.tokens = ArrayList(Token).init(regex.alloc);

        return g;
    }

    inline fn printColoredText(writer: anytype, s: Str) !void {
        try writer.print("{s}{s}{}{s}{s} ", .{Str.COLOR_BLACK, Str.BGCOLOR_YELLOW, s, Str.BGCOLOR_DEFAULT, Str.COLOR_DEFAULT});
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
                    try printColoredText(writer, s);
                },
                .name => |s| {
                    try printColoredText(writer, s);
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

    fn analyze(self: *Group, index: Str.Index) !Str.Index {
        var it = Str.Iterator.New(&self.regex.pattern, index);
        while (it.next()) |gr| {
            if (gr.eqAscii('[')) {
                if (self.hasContent()) {
                    var g = Group.New(self.regex, self);
                    g.setSquare();
                    const newg = it.next() orelse return Str.Error.Other;
                    it.continueFrom(try g.analyze(newg.idx));
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
                    it.continueFrom(try g.analyze(newg.idx));
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
                    if (s.indexOf2(">", .{.from = idx.addRaw(2)})) |end_idx| {
                        const name = try s.betweenIndices(idx, end_idx);
                        // mtl.debug(@src(), "Name: \"{}\"", .{name});
                        try self.addMeta(Meta.NamedCapture);
                        try self.addName(name);
                        it.continueFrom(end_idx.addRaw(1)); // go past ">"
                    }
                } else { // just "?"
                    try self.addQtty(Qtty.ZeroOrOne());
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
                try self.addQtty(Qtty.OneOrMore());
            } else if (gr.eqAscii('*')) {
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
    }

    pub fn hasContent(self: Group) bool {
        return self.tokens.items.len > 0;
    }

    pub fn is_enclosed(self: Group) bool {
        return self.enclosed != Enclosed.None;
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

// Regex takes ownership over `pattern`
pub fn New(alloc: Allocator, pattern: Str) !*Regex {
    const ptr = try alloc.create(Regex);
    ptr.* = Regex {
        .pattern = pattern,
        .tokens = ArrayList(Token).init(alloc),
        .alloc = alloc,
        .groups = ArrayList(Group).init(alloc),
    };
    
    mtl.debug(@src(), "Regex: {}", .{pattern});
    
    var g: Group = Group.New(ptr, null);
    _ = try g.analyze(Str.strStart());
    try ptr.groups.append(g);

    return ptr;
}

pub fn deinit(self: Regex) void {
    for (self.tokens.items) |g| {
        g.deinit();
    }
    self.pattern.deinit();
    for (self.groups.items) |g| {
        g.deinit();
    }
    self.groups.deinit();
}

pub fn getGroup(self: *Regex, id: IdType) ?*Group {
    for (self.groups.items) |*g| {
        if (g.id == id) {
            return g;
        }
    }

    return null;
}

pub fn printGroups(self: Regex) void {
    for (self.groups.items) |g| {
        g.printTokens();
    }
}

test "Test regex" {
    const alloc = std.testing.allocator;
    Str.ctx = try Str.Context.New(alloc);
    defer Str.ctx.deinit();

// ?: means make the capturing group a non capturing group, i.e. don't include its match as a back-reference.
// ?! is the negative lookahead. The regex will only match if the capturing group does not match.
    const pattern = try Str.From("==[?<ClientName>\\w+](?:12[^A-Z]opq(?!345))xyz");
    const regex = try Regex.New(alloc, pattern);
    defer alloc.destroy(regex);
    defer regex.deinit();
    regex.printGroups();

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

