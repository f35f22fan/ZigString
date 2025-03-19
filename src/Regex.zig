const std = @import("std");
const ArrayList = std.ArrayList;
const Str = @import("String.zig");
const mtl = Str.mtl;
const Cp = Str.Codepoint;
const Regex = @This();
const Allocator = std.mem.Allocator;

const Meta = enum(u8) {
    Dot,
    Plus,
    Asterisk,
    Question,
    Not,
    Or,
    Greater,
    Lesser,
    NonCapture,
    NegativeLookAhead,
    NegativeLookBehind,
    PositiveLookAhead,
    PositiveLookBehind,
};

const TokenEnum = enum(u8) {
    group,
    qtty,
    meta,
    str,
};

const Token = union(TokenEnum) {
    group: Group,
    qtty: Qtty,
    meta: Meta,
    str: Str,

    inline fn isMeta(self: Token, param: Meta) bool {
        switch(self) {
            .meta => |m| return (m == param),
            else => return false,
        }
    }

    pub fn isDot(self: Token) bool {
        return self.isMeta(Meta.Dot);
    }

    pub fn isNot(self: Token) bool {
        return self.isMeta(Meta.Not);
    }

    pub fn isAsterisk(self: Token) bool {
        return self.isMeta(Meta.Asterisk);
    }

    pub fn isQuestion(self: Token) bool {
        return self.isMeta(Meta.Question);
    }

    pub fn isPlus(self: Token) bool {
        return self.isMeta(Meta.Plus);
    }

    pub fn isOr(self: Token) bool {
        return self.isMeta(Meta.Or);
    }

    pub fn isGreater(self: Token) bool {
        return self.isMeta(Meta.Greater);
    }

    pub fn isLesser(self: Token) bool {
        return self.isMeta(Meta.Lesser);
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

    pub fn zeroOrMore(self: Qtty) bool { // x*
        if (self.a != 0) return false;
        return self.b_inf();
    }

    pub fn zeroOrOne(self: Qtty) bool { // x?
        if (self.a != 0) return false;
        if (self.b) |n| return (n == 1);
        return false;
    }

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
    id: u16,

    pub fn New(regex: *Regex) Group {
        var g = Group{.regex = regex, .id = regex.next_id};
        regex.next_id += 1;
        g.tokens = ArrayList(Token).init(regex.alloc);

        return g;
    }

    pub fn format(self: Group, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}Id={}{s} ", .{Str.COLOR_ORANGE, self.id, Str.COLOR_DEFAULT});
        for (self.tokens.items) |t| {
            switch (t) {
                .group => {},
                // .group => |g| {
                //     try writer.print("g{}", .{g});
                // },
                .qtty => |q| {
                    try writer.print("{s}{}{s} ", .{Str.COLOR_GREEN, q, Str.COLOR_DEFAULT});
                },
                .meta => |m| {
                    try writer.print("{s}{}{s} ", .{Str.COLOR_CYAN, m, Str.COLOR_DEFAULT});
                },
                .str => |s| {
                    try writer.print("{s}{s}{}{s}{s} ", .{Str.COLOR_BLACK, Str.BGCOLOR_YELLOW, s, Str.BGCOLOR_DEFAULT, Str.COLOR_DEFAULT});
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
        var need_create_new = false;
        var it = Str.Iterator.New(&self.regex.pattern, index);
        while (it.next()) |gr| {
            if (gr.eqAscii('[')) {
                if (self.hasContent()) {
                    var g = Group.New(self.regex);
                    g.setSquare();
                    const newg = it.next() orelse return Str.Error.Other;
                    it.continueFrom(try g.analyze(newg.idx));
                    try self.appendGroup(g);
                    return it.idx;
                } else {
                    self.setSquare();
                }
            } else if (gr.eqAscii(']')) {
                need_create_new = self.is_enclosed();
            } else if (gr.eqAscii('(')) {
                if (self.hasContent()) {
                    var g = Group.New(self.regex);
                    g.setRound();
                    const newg = it.next() orelse return Str.Error.Other;
                    it.continueFrom(try g.analyze(newg.idx));
                    try self.appendGroup(g);
                    return it.idx;
                } else {
                    self.setRound();
                }
            } else if (gr.eqAscii(')')) {
                need_create_new = self.is_enclosed();
            } else if (gr.eqAscii('*')) {
                try self.appendMeta(Meta.Asterisk);
            } else if (gr.eqAscii('?')) {
                const s: *Str = &self.regex.pattern;
                if (s.matches("?:", gr.idx)) |idx| {
                    it.continueFrom(idx);
                    try self.appendMeta(Meta.NonCapture);
                } else if (s.matches("?!", gr.idx)) |idx| {
                    it.continueFrom(idx);
                    try self.appendMeta(Meta.NegativeLookAhead);
                } else if (s.matches("?<!", gr.idx)) |idx| {
                    it.continueFrom(idx);
                    try self.appendMeta(Meta.NegativeLookBehind);
                } else if (s.matches("?=", gr.idx)) |idx| {
                    it.continueFrom(idx);
                    try self.appendMeta(Meta.PositiveLookAhead);
                } else if (s.matches("?<=", gr.idx)) |idx| {
                    it.continueFrom(idx);
                    try self.appendMeta(Meta.PositiveLookBehind);
                } else if (s.matches("?<", gr.idx)) |idx| { //(?<name>\\w+) = name = e.g."Jordan"
                    it.continueFrom(idx);
                    // named capture
                }
            } else if (gr.eqAscii('+')) {
                try self.appendMeta(Meta.Plus);
            } else if (gr.eqAscii('^')) {
                try self.appendMeta(Meta.Not);
            } else if (gr.eqAscii('.')) {
                try self.appendMeta(Meta.Dot);
            } else if (gr.eqAscii('|')) {
                try self.appendMeta(Meta.Or);
            } else if (gr.eqAscii('>')) {
                try self.appendMeta(Meta.Greater);
            } else if (gr.eqAscii('<')) {
                try self.appendMeta(Meta.Lesser);
            } else if (self.tokens.items.len > 0 and gr.eqAscii('^')) {
                self.not = true;
            } else {
                if (need_create_new) {
                    need_create_new = false;
                    var g = Group.New(self.regex);
                    try g.addGrapheme(gr);
                    const newg = it.next() orelse return Str.Error.Other;
                    it.continueFrom(try g.analyze(newg.idx));
                    try self.appendGroup(g);
                    return it.idx;
                } else {
                    try self.addGrapheme(gr);
                }
            }
        }

        return it.idx;
    }

    inline fn appendGroup(self: *Group, g: Group) !void {
        try self.tokens.append(Token {.group = g});
    }

    inline fn appendMeta(self: *Group, m: Meta) !void {
        try self.tokens.append(Token {.meta = m});
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
next_id: u16 = 0,

// Regex takes ownership over `pattern`
pub fn New(alloc: Allocator, pattern: Str) !Regex {
    var r = Regex {
        .pattern = pattern,
        .tokens = ArrayList(Token).init(alloc),
        .alloc = alloc,
        .groups = ArrayList(Group).init(alloc),
    };
    mtl.debug(@src(), "pattern: {}", .{pattern});
    var g: Group = Group.New(&r);
    _ = try g.analyze(Str.strStart());
    try r.groups.append(g);

    return r;
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
    const pattern = try Str.From("==[^abc](?:12[^A-Z]opq(?!345))xyz");
    const regex = try Regex.New(alloc, pattern);
    defer regex.deinit();
    regex.printGroups();

    // var qtty = Qtty{};
    // try qtty.setFixedRange(3, 5);
    // mtl.debug(@src(), "{}", .{qtty});
    // qtty.setOneOrMore();
    // mtl.debug(@src(), "{}", .{qtty});
    // qtty.setZeroOrMore();
    // mtl.debug(@src(), "{}", .{qtty});
    // qtty.setExactNumber(28);
    // mtl.debug(@src(), "{}", .{qtty});
    // qtty.setNOrMore(4);
    // mtl.debug(@src(), "{}", .{qtty});

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

