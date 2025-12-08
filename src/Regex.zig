const std = @import("std");
const ArrayList = std.ArrayList;
const String = @import("String.zig");
const Grapheme = String.Grapheme;
const GraphemeRange = String.GraphemeRange;
const Direction = String.Direction;
const Index = String.Index;
const Slice = String.Slice;
const Charset = String.Charset;
const CaseSensitive = String.CaseSensitive;
const Args = String.Args;
const StringIterator = String.StringIterator;
const Iterator = String.Iterator;
const mtl = String.mtl;
const Cp = String.Codepoint;
const Regex = @This();
const Allocator = std.mem.Allocator;
const IdType = u16;

const TraceLA: bool = false; // Debug Look Ahead
const TraceLB: bool = false; // Debug Look Behind
const TraceAnyOf: bool = false;
const TraceGroupResult: bool = true;

const State = struct {
    looking_behind: bool = false,
};

pub const FindParams = struct {
    qtty: Qtty = Qtty.One(),
    cs: CaseSensitive = .Yes,
    from: Index = Index.strStart(),
};

const Error = error {
    BadRange,
    Parsing,
};

pub const EvalAs = enum(u8) {
    Or,
    Not,
};

pub const Item = struct {
    data: ItemData = undefined,
    lb: ?*Group = null,

    pub fn deinit(self: Item) void {
        self.data.deinit();
    }

    fn checkBehind(item: *Item, haystack: *const String, from: Index) bool {
        const lb_group = item.lb orelse return true;
        if (!lb_group.anyLookBehind()) {
            unreachable;
        }

        var regex = lb_group.regex;

        regex.setLookingBehind(true);
        mtl.debug(@src(), "group_{?} from:{} negative_lb:{}",
            .{lb_group.id, from, lb_group.look_around.negative_lookbehind});
        const idx = lb_group.matches(haystack, from);
        mtl.debug(@src(), "group_{?} result:{?}", .{lb_group.id, idx});
        regex.setLookingBehind(false);

        return (idx != null);
    }

    inline fn isMeta(self: Item, param: Meta) bool {
        return self.data.isMeta(param);
    }

    inline fn isRange(self: Item) bool {
        return self.data.isRange();
    }

    pub fn isAnyChar(self: Item) bool {
        return self.data.isAnyChar(Meta.SymbolAnyChar);
    }

    pub fn isNot(self: Item) bool {
        return self.data.isMeta(Meta.Not);
    }

    pub fn isName(self: Item) bool {
        return self.data.isName();
    }

    pub fn isOr(self: Item) bool {
        return self.data.isMeta(Meta.Or);
    }

    pub fn isQtty(self: Item) bool {
        return self.data.isQtty();
    }

    pub fn isString(self: Item) bool {
        return self.data.isString();
    }

    pub fn newGroup(g: Group) Item {
        return Item {
            .data = ItemData {.group = g }
        };
    }

    pub fn newMeta(m: Meta) Item {
        return Item{
            .data = ItemData {.meta = m},
        };
    }

    pub fn newName(s: String) Item {
        return Item {
            .data = ItemData {.name = s},
        };
    }

    pub fn newQtty(q: Qtty) Item {
        return Item {
            .data = ItemData {.qtty = q},
        };
    }

    pub fn newRange(r: GraphemeRange) Item {
        return Item {
            .data = ItemData {.range = r},
        };
    }

    pub fn newString(s: String) Item {
        return Item {
            .data = ItemData{.str = s},
        };
    }
};

const ItemData = union(enum) {
    group: Group,
    qtty: Qtty,
    meta: Meta,
    str: String,
    name: String,
    range: GraphemeRange,

    inline fn isMeta(self: ItemData, param: Meta) bool {
        switch(self) {
            .meta => |m| return (m == param),
            else => return false,
        }
    }

    inline fn isRange(self: ItemData) bool {
        switch(self) {
            .range => return true,
            else => return false,
        }
    }

    pub fn isAnyChar(self: ItemData) bool {
        return self.isMeta(Meta.SymbolAnyChar);
    }

    pub fn isNot(self: ItemData) bool {
        return self.isMeta(Meta.Not);
    }

    pub fn isName(self: ItemData) bool {
        switch (self) {
            .name => return true,
            else => return false,
        }
    }

    pub fn isOr(self: ItemData) bool {
        return self.isMeta(Meta.Or);
    }

    pub fn isQtty(self: ItemData) bool {
        switch (self) {
            .qtty => return true,
            else => return false,
        }
    }

    pub fn isString(self: ItemData) bool {
        switch (self) {
            .str => return true,
            else => return false,
        }
    }

    pub fn deinit(self: ItemData) void {
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

    pub fn From(tokens_iter: *Iterator(Item)) LookAround {
        var la: LookAround = .{};
        const token = tokens_iter.peekFirst() orelse return la;
            
        switch (token.data) {
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

    pub fn overrideWith(self: *LookAround, la: LookAround) void {
        if (!self.negative_lookahead) {
            self.negative_lookahead = la.negative_lookahead;
        }

        if (!self.positive_lookahead) {
            self.positive_lookahead = la.positive_lookahead;
        }

        if (!self.negative_lookbehind) {
            self.negative_lookbehind = la.negative_lookbehind;
        }

        if (!self.positive_lookbehind) {
            self.positive_lookbehind = la.positive_lookbehind;
        }
    }
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

pub const Qtty = struct {
    a: i64 = 1,
    b: i64 = 1,
    greedy: bool = true,

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

    pub fn asManyAsPossible(self: Qtty) bool {
        return self.b == inf();
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
        const lazy = if (self.greedy) "" else "(lazy)";
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

    pub fn satisfiedBy(self: Qtty, count: usize) bool {
        return count >= self.a;
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

    pub fn loop(self: *const Qtty, count: usize) bool {
        return count < self.a or self.greedy;
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
    
    pub fn New(a: i64, b: ?i64) Qtty {
        return Qtty {
            .a = a,
            .b = if (b) |n| n else 1,
        };
    }

    inline fn shouldBreakAfter(self: Qtty, count: usize) bool {
        if (self.greedy) {
            return count >= self.b;
        }

        return count >= self.a;
    }
};

pub const Match = enum(u8) {
    AnyOf,
    All,
};

pub const Group = struct {
    match_type: Match = .All,
    regex: *Regex,
    token_arr: ArrayList(ArrayList(Item)) = undefined,
    id: ?IdType = null,
    parent_id: ?IdType = null,
    captures: ArrayList(Slice) = undefined,
    capture_index: usize = 0,
    look_around: LookAround = .{},
    start: ?Index = null,

    pub fn New(regex: *Regex, parent: ?*Group) Group {
        const parent_id = if (parent) |p| p.id else null;
        var new_group = Group{.regex = regex, .id = regex.next_group_id, .parent_id = parent_id};
        regex.next_group_id += 1;
        new_group.token_arr = ArrayList(ArrayList(Item)).init(regex.alloc);
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
        if (self.regex.lookingBehind()) {
            return;
        }
        // mtl.debug(@src(), "======group.id={?}, slice:({}-{}){dt}", .{self.id, slice.start.gr, slice.end.gr, slice});

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

    pub fn addGrapheme(tokens: *ArrayList(Item), gr: Grapheme) !void {
        // If the last token is a string add to it, otherwise append a new string Item and add to it:
        const len = tokens.items.len;
        if (len > 0 and tokens.items[len-1].isString()) {
            const t = &tokens.items[len-1];
            switch (t.data) {
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
            try tokens.append(Item.newString(s));
        }
    }

    fn addName(arr: *ArrayList(Item), s: String) !void {
        try arr.append(Item.newName(s));
    }

    fn addQtty(arr: *ArrayList(Item), qtty: Qtty) !void {
        try arr.append(Item.newQtty(qtty));
    }

    fn addStr(arr: *ArrayList(Item), s: String) !void {
        try arr.append(Item.newString(s));
    }

    fn addAscii(arr: *ArrayList(Item), s: []const u8) !void {
        const item = Item.newString(try String.FromAscii(s));
        // mtl.debug(@src(), "item:{}", .{item});
        try arr.append(item);
    }

    fn addUtf8(arr: *ArrayList(Item), s: []const u8) !void {
        try arr.append(Item.newString(try String.From(s)));
    }

    fn adjustLookBehinds(self: *Group, parent: ?LookAround) void {
        if (parent) |p| {
            self.look_around.overrideWith(p);
        }

        for (self.token_arr.items) |arr| {
            for (arr.items) |*item| {
                // _ = item;
                switch (item.data) {
                    .group => |*subgroup| {
                        subgroup.adjustLookBehinds(self.look_around);
                    },
                    else => {}
                }
            }
        }
    }

    fn analyzeTokens(self: *Group) !void {
        for (self.token_arr.items) |*arr| {
            var token_iter = Iterator(Item).New(arr.items);
            while (token_iter.nextPtr()) |t| {
                // mtl.debug(@src(), "------------{}", .{t});
                switch (t.data) {
                    .str => |*s| {
                        var new_tokens = ArrayList(Item).init(self.regex.alloc);
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

    inline fn anyLookBehind(self: *const Group) bool {
        return self.look_around.anyLookBehind();
    }

    pub fn canCapture(self: *const Group) bool {
        for (self.token_arr.items) |*arr| {
            if (startsWithMeta(arr.items, Meta.NonCapture))
                return false;
        }

        return true;
    }

    fn createArgs(self: Group) Args {
        return Args{.cs=self.regex.params.cs, .look_ahead = !self.regex.lookingBehind()};
    }

    fn endsWithMeta(slice: []const Item, meta: Meta) bool {
        if (slice.len == 0) {
            return false;
        }

        return slice[slice.len - 1].isMeta(meta);
    }

    pub fn findNextChars(self: *Group, item: *Item, haystack: Slice, from: Index, meta: Meta, qtty: Qtty) ?Index {
        const positive_lookahead = self.look_around.positive_lookahead;
        var ret_idx: ?Index = null;
        var string_iter = haystack.iteratorFrom(from);
        var count: usize = 0;
        var found_enough = false;
        
        const direction: Direction = if (self.regex.lookingBehind()) .Back else .Forward;
        if (direction == .Back) {
            _ = string_iter.go(direction);
        }

        while (string_iter.go(direction)) |gr| {
            if (self.anyLookBehind()) {
                // mtl.debug(@src(), "Look behind: {dt}, at:{}", .{gr, gr.idx});
            }

            var found_next_one = false;
            switch (meta) {
                .SymbolWordChar => {
                    found_next_one = gr.isWordChar(self.regex.charset);
                    // mtl.debug(@src(), "SymbolWordChar:\"{dt}\", ({})", .{gr, found_next_one});
                },
                .SymbolNonWordChar => {
                    found_next_one = !gr.isWordChar(self.regex.charset);
                },
                .SymbolNumber => {
                    found_next_one = gr.isNumber();
                    // mtl.debug(@src(), "SymbolNumber:\"{dt}\", ({}), LookingBehind:{}",
                    //  .{gr, found_next_one, self.lookingBehind()});
                },
                .SymbolNonNumber => {
                    found_next_one = !gr.isNumber();
                },
                .SymbolWhitespace => {
                    found_next_one = gr.isWhitespace();
                    // mtl.debug(@src(), "SymbolWhitespace, ({}), LookingBehind:{}",
                    // .{found_next_one, self.lookingBehind()});
                },
                .SymbolNonWhitespace => {
                    found_next_one = !gr.isWhitespace();
                    // mtl.debug(@src(), "SymbolNonWhitespace, ({})", .{found_next_one});
                },
                else => {
                    mtl.debug(@src(), "Symbol(Other):\"{dt}\", ({})", .{gr, found_next_one});
                }
            }

            if (!found_next_one) {
                break;
            }

            ret_idx = if (self.regex.lookingBehind()) string_iter.position else gr.idx.plusGrapheme(gr);
            count += 1;
            
            if (qtty.shouldBreakAfter(count)) {
                found_enough = true;
                break;
            }
        }

        if (found_enough) {
            if (positive_lookahead) {
                ret_idx = from;
            }
        }

        if (ret_idx != null) {
            if (!item.checkBehind(haystack.str, from)) {
                ret_idx = null;
            }
        }

        if (ret_idx == null) {
            return null;
        }
        
        return if (self.matchAnyOf()) from else ret_idx;
    }

    pub fn format(self: Group, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        if (fmt.len > 0) {
            if (std.mem.eql(u8, fmt, "id")) {
                try writer.print("Group:{?}", .{self.id});
                return;
            }
        }

        try writer.print("{s}Group:{?} {} (parent:{?}) {s}", .{mtl.COLOR_ORANGE,
        self.id, self.match_type, self.parent_id, mtl.COLOR_DEFAULT});
        for (self.token_arr.items, 0..) |arr, array_index| {
            for (arr.items, 0..) |t, item_index| {
                if (array_index > 0 and item_index == 0) {
                    try printMeta(writer, .Or);
                }
                switch (t.data) {
                    .group => |g| {
                        try writer.print("{s}Group={?}{s} ", .{mtl.COLOR_BLUE, g.id, mtl.COLOR_DEFAULT});
                    },
                    .qtty => |q| {
                        try writer.print("{s}{}{s} ", .{mtl.COLOR_GREEN, q, mtl.COLOR_DEFAULT});
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
                        try writer.print("{s}{}{s} ", .{mtl.COLOR_MAGENTA, r, mtl.COLOR_DEFAULT});
                    }
                }
            }
        }
    }

    pub fn getCaptureByName(self: *const Group, name: String) ?*const ArrayList(Slice) {
        for (self.token_arr.items) |arr| {
            for (arr.items) |*t| {
                switch (t.data) {
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

    fn getNextQtty(tokens_iter: *Iterator(Item), looking_behind: bool) Qtty {
        if (tokens_iter.peekNext()) |next_token| {
            switch(next_token.data) {
                .qtty => |q| {
                    if (!looking_behind) {
                        _ = tokens_iter.next(); // if so then need to advance
                    }
                    return q;
                },
                else => {},
            }
        }

        return Qtty.One();
    }

    pub fn hasContent(self: Group) bool {
        for (self.token_arr.items) |arr| {
            if (arr.items.len > 0) {
                return true;
            }
        }

        return false;
    }

    pub fn isRoot(self: Group) bool {
       return self.parent_id == null;
    }

    fn matchAnyOf(self: *const Group) bool {
        return self.match_type == .AnyOf;
    }

    const RangeMatch = union(enum) {
        GoToNextItem,
        Null,
        Pos: Index,
    };

    fn matchRange(self: *const Group, range: GraphemeRange, input: *const String,
    at: Index, qtty: Qtty, starts_with_not: bool, has_more: bool) RangeMatch {
        var count: usize = 0;
        var result: ?Index = null;
        var pos = at;
        const any_lookbehind = self.anyLookBehind();
        while (qtty.loop(count)) {
            const gr = input.charAtIndex(pos) orelse return .Null;
            const success = gr.within(range, self.regex.params.cs);
            // mtl.debug(@src(), "gr: {dt}, result:{}, range: {}", .{gr, success, range});
            if (!success) {
                if (self.matchAnyOf() and !starts_with_not) {
                    // mtl.debug(@src(), "CONTINUE_NEXT at:{?} pos:{}", .{at, pos});
                    return if (has_more) .GoToNextItem else .Null;
                }

                break;
            }

            if (any_lookbehind) {
                pos.goLeftBy(gr);
            } else {
                pos.goRightBy(gr);
            }

            result = pos;
            count += 1;
            if (qtty.shouldBreakAfter(count)) {
                break;
            }
        }

        if (!starts_with_not and !qtty.satisfiedBy(count)) {
            mtl.debug(@src(), "group_{?} {} VS {}", .{self.id, qtty, count});
            return .Null;
        }

        const found = result != null;
        if (self.matchAnyOf()) {
            if (starts_with_not) {
                // mtl.debug(@src(), "group_{?}, result:{?}", .{self.id, result});
                if (found) {
                    return .Null; // match failed
                } else {
                    return .GoToNextItem;
                }
            } else {
                if (found) {
                    // in case of success for .AnyOf no need to try to match all elements inside []
                    return RangeMatch{.Pos = at};
                } else {
                    return .GoToNextItem;
                }
            }
        } else {
            if (starts_with_not) {
                if (found) {
                    return .Null;
                } else {
                    return .GoToNextItem;
                }
            } else {
                if (found) {
                    return .GoToNextItem;
                } else {
                    return .Null;
                } 
            }
        }

        return .Null;
    }

    fn matchAll(self: *const Group, haystack: Slice, needles: Slice, qtty: Qtty, not: bool) ?Index {
        if (qtty.a == 0 and !qtty.greedy) {
            return haystack.start;
        }

        if (self.regex.lookingBehind()) {
            const idx = self.matchAllBehind(haystack, needles, qtty, not);
            // mtl.debug(@src(), "haystack: {dt}, needles:{}, result:{?}", .{haystack, needles, idx});
            return idx;
        }

        if (qtty.exactNumber(1)) {
            if (self.regex.lookingBehind()) {
                mtl.trace(@src());
            }
            const args = Args {.cs=self.regex.params.cs};
            const past_match = matchStr(not, needles, haystack, args);
            if (self.look_around.anyNegative()) {
                return if (past_match == null) haystack.start else null; // must not advance
            } else if (self.look_around.anyPositive()) {
                return if (past_match == null) null else haystack.start; // must not advance
            } else {
                return past_match;
            }
        }
        // If got here it means that desired qtty > 1, thus one needs to isolate
        // the last grapheme that qtty refers to.
        const last_gr_index = needles.beforeLast(); // when "abc?" or "abc+"
        const needles_minus_last = needles.leftSlice(last_gr_index);
        // mtl.debug(@src(), "needles_base:{dt}, needles:{dt}, haystack:{dt}",
            // .{needles_minus_last, needles, haystack});
        var at = haystack.start;
        {
            const args = self.createArgs();
            const index_after = matchStr(not, needles_minus_last, haystack, args);
            if (index_after) |after| {
                at = after;
            } else {
                if (self.look_around.anyNegative()) {
                    return haystack.start; // means match
                } else if (self.look_around.anyPositive()) {
                    return null; // means no match
                }
            }
        }

        const last_char_slice = needles.midSlice(last_gr_index);
        // mtl.debug(@src(), "base_str:{dt}, last_char:{}", .{base_str, last_char_str});
        var count: usize = 0;
        
        while (true) {
            const args = self.createArgs();
            if (matchStr(not, last_char_slice, haystack.midSlice(at), args)) |idx_after| {
                count += 1;
                at = idx_after;
                if (count == qtty.b) {
                    break;
                }
            } else {
                break;
            }
        }

        if (count >= qtty.a) {
            return if (self.look_around.positive_lookahead) haystack.start else at;
        }

        return null;
    }

    fn matchAllBehind(self: *const Group, haystack: Slice, needles: Slice, qtty: Qtty, not: bool) ?Index {
        const last_gr = needles.lastChar() orelse return null;
        if (TraceLB) {
            mtl.debug(@src(), "group_{?} haystack: {dt}, needles: {dt}, last_char:{dt}, qtty: {}",
            .{self.id, haystack, needles, last_gr, qtty});
        }
        
        const negative = self.look_around.negative_lookbehind or not;
        var count: usize = 0;
        var haystack_iter = haystack.iteratorFromEnd();
        var at: ?Index = null;
        while (haystack_iter.prev()) |char| {
            // mtl.debug(@src(), "{dt} vs {dt}", .{char, last_gr});
            const found = char.eq(last_gr, .Yes);
            if (found) {
                at = char.idx;
                count += 1;
            } else {
                break;
            }

            if (qtty.shouldBreakAfter(count)) {
                break;
            }
        }

        if (count < qtty.a) {
            const result = if (negative) haystack.end else null;
            mtl.debug(@src(), "count({}) < qtty.a({}) for {dt}, not_value={}, result={?}",
                .{count, qtty.a, last_gr, negative, result});
            
            return result;
        }

        const base = needles.slice(.{}, needles.beforeLast());
        const from = at orelse return null;
        const h = haystack.leftSlice(from);
        var retval: ?Index = null;
        if (h.endsWith(base)) |pos| {
            retval = if (not) null else pos;
        } else {
            if (negative) {
                retval = haystack.findIndexFromEnd(base.size());
            } else {
                retval = null;
            }
        }

        if (TraceLB) {
            mtl.debug(@src(), "group_{?} count: {}, h:{dt}, retval:{?}", .{self.id, count, h, retval});
        }

        return retval;
    }

    fn matchAnyChar(self: *const Group, any_of: Slice, compare_to: Grapheme,
    args: Args, starts_with_not: bool) bool {
        const any_lb = self.anyLookBehind();
        var anyof_iter = if (any_lb) any_of.iteratorFromEnd() else any_of.iterator();
        const direction: Direction = if (any_lb) .Back else .Forward;
        var retval = false;
        while (anyof_iter.go(direction)) |anyof_gr| {
            const found = anyof_gr.eq(compare_to, args.cs);
            
            if (starts_with_not) {
                if (found) {
                    retval = false; // none of them must match, so it's a failure
                    break;
                } else {
                    retval = true;
                    continue;
                }
            }
            if (found) {
                retval = true;
                break;
            }
        }

        if (TraceAnyOf or (TraceLB and any_lb)) {
            mtl.debug(@src(),
            "group_{?} retval:{?}, args.from:{}, compare anyof {dt}, to:{dt}, lb:{}, looking_behind:{}, not:{}",
                .{self.id, retval, args.from, any_of, compare_to, any_lb, self.regex.lookingBehind(),
                starts_with_not});
        }

        return retval;
    }

    fn matchStr(starts_with_not: bool, needles: Slice, haystack: Slice, args: Args) ?Index {
        if (haystack.matchesSlice(needles, args)) |past_idx| {
            return if (starts_with_not) null else past_idx;
        }
        
        return null;
    }

    pub fn matches(self: *Group, haystack: *const String, from: Index) ?Index {
        const args = Args {.from = from, .cs = self.regex.params.cs };
        var result: ?Index = null;
        var arr_idx: usize = 0;
        var skip = false;
        for (self.token_arr.items, 0..) |*arr, i| {
            if (arr.items.len == 0) {
                continue;
            }

            if (!self.regex.lookingBehind() and self.anyLookBehind()) {
                result = from;
                skip = true;
                continue;
            }
            
            arr_idx = i;
            if (self.matchesArray(arr, haystack, args)) |idx_after| {
                skip = false;
                result = idx_after;
                break;
            }
        }

        if (!self.isRoot() and TraceGroupResult and !skip) {
            if (arr_idx > 0) {
                mtl.debug(@src(), "TraceResult group_{?} from:{} {s}arr_idx:{}{s} result:{?}",
                .{self.id, from.gr, mtl.COLOR_ORANGE, arr_idx, mtl.COLOR_DEFAULT, result});
            } else {
                const ch = haystack.charAtIndex(from);
                mtl.debug(@src(), "TraceResult group_{?} from:{} '{?}' result:{?}, any_lb:{}",
                .{self.id, from.gr, ch, result, self.anyLookBehind()});
            }
        }

        if (from.gr > self.regex.params.from.gr) {
            // mtl.debug(@src(), "params.from=>{}", .{from});
            self.regex.params.from = from;
        }

        return result;
    }

    fn matchesArray(self: *Group, tokens: *ArrayList(Item), input: *const String, args: Args) ?Index {
        var items_iter = Iterator(Item).New(tokens.items);
        var direction: Direction = undefined;
        if (self.regex.lookingBehind()) {
            direction = .Back;
            items_iter.toEnd();
        } else {
            if (self.anyLookBehind()) {
                mtl.debug(@src(), "{?}", .{self.id});
                // must be performed after the token in front of it matches.
                return args.from;
            }
            direction = .Forward;
        }

        if (startsWithMeta(tokens.items, .SymbolStartOfLine)) {
            if (args.from.cp != 0) {
                const prev_gr = input.prev(args.from) orelse return null;
                if (!prev_gr.eqCp('\n')) {
                    return null;
                }
            }
        }

        var at: ?Index = args.from;
        var at_copy: ?Index = at;
        const starts_with_not = startsWithMeta(tokens.items, .Not);
        next_item: while (items_iter.go(direction)) |item| {
            if (at == null) {
                at = at_copy;
            }
            // mtl.debug(@src(), "group.id={?} at:{?} item:{} items_iter.at:{}", .{self.id, at, item, items_iter.at});
            const has_more = items_iter.hasMore(direction);
            const qtty = getNextQtty(&items_iter, self.regex.lookingBehind());
            const last_at = at orelse return null;
            at_copy = last_at;
            at = null;
            const haystack = if (self.regex.lookingBehind()) input.leftSlice(last_at) else input.midSlice(last_at);
            switch (item.data) {
                .str => |*needles_str| {
                    const needles = needles_str.asSlice();
                    if (self.match_type == .All) {
                        if (self.matchAll(haystack, needles, qtty, starts_with_not)) |after_last| {
                            if (!item.checkBehind(input, last_at)) {
                                return null;
                            }
                            at = after_last;
                            // mtl.debug(@src(), "group_{?} result:{}, str:{dt}, at:{}", .{self.id, after_last, needles, last_at});
                        } else {
                            // mtl.debug(@src(), "group_{?}, result:null, str:{dt}, at:{}", .{self.id, needles, last_at});
                            return null;
                        }
                    } else { // == .AnyOf
                        var idx: Index = undefined;
                        if (self.anyLookBehind()) {
                            idx = haystack.prevIndex(last_at) orelse return null;
                        } else {
                            idx = last_at;
                        }
                        const compare_to = haystack.charAtIndex(idx) orelse {
                            mtl.trace(@src());
                            return null;
                        };
                        
                        if (self.matchAnyChar(needles, compare_to, .{.from=last_at, .cs=args.cs}, starts_with_not)) {
                            if (!item.checkBehind(input, last_at)) {
                                return null;
                            }
                            
                            at = last_at;
                            self.regex.params.from = last_at;
                            if (TraceAnyOf) {
                                mtl.debug(@src(), "matchAnyChar result:{}", .{last_at});
                            }
                        } else {
                            if (TraceAnyOf) {
                                mtl.debug(@src(), "matchAnyChar result:null", .{});
                            }
                            return null;
                        }
                    }
                },
                .meta => |m| {
                    switch (m) {
                        .SymbolWordChar => {
                            at = self.findNextChars(item, haystack, last_at, m, qtty) orelse return null;
                            // mtl.debug(@src(), "SymbolWordChar at:{?}", .{at});
                        },
                        .SymbolWordBoundary => {
                            if (!haystack.isWordBoundary(last_at, self.regex.charset)) {
                                return null;
                            }
                            if (!item.checkBehind(input, last_at)) {
                                return null;
                            }
                        },
                        .SymbolNonWordBoundary => {
                            if (haystack.isWordBoundary(last_at, self.regex.charset)) {
                                return null;
                            }
                            if (!item.checkBehind(input, last_at)) {
                                return null;
                            }
                        },
                        .SymbolNumber => {
                            at = self.findNextChars(item, haystack, last_at, m, qtty) orelse return null;
                        },
                        .SymbolNonNumber => {
                            at = self.findNextChars(item, haystack, last_at, m, qtty) orelse return null;
                        },
                        .SymbolWhitespace => {
                            const idx = self.findNextChars(item, haystack, last_at, m, qtty);
                            at = idx orelse return null;
                        },
                        .SymbolNonWhitespace => {
                            at = self.findNextChars(item, haystack, last_at, m, qtty) orelse return null;
                        },
                        .SymbolEndOfLine => {
                            if (haystack.charAtIndex(last_at)) |gr| {
                                if (gr.eqCp('\n')) {
                                    at = last_at;
                                }
                            }
                        },
                        else => |v| {
                            at = at_copy;
                            // mtl.debug(@src(), "UNTREATED META:{}", .{v});
                            _ = &v;
                        }
                    }

                    if (at != null) {
                        if (self.matchAnyOf()) {
                            break :next_item;
                        }
                    }
                },
                .group => |*sub_group| {
                    // mtl.debug(@src(), "SUB_GROUP: {?}, start: {}", .{sub_group.id, at});
                    
                    var count: usize = 0;
                    var now_at = last_at;
                    while (qtty.loop(count)) {
                        if (sub_group.matches(input, now_at)) |after_last| {
                            now_at = after_last;
                        } else {
                            break;
                        }
                        count += 1;

                        if (qtty.shouldBreakAfter(count)) {
                            break;
                        }
                        // otherwise keep finding as many as possible
                    }

                    if (count < qtty.a) {
                        return null;
                    }

                    if (!item.checkBehind(input, last_at)) {
                        return null;
                    }
                    at = now_at;
                },
                .range => |range| {
                    // mtl.debug(@src(), "group_{?} {} at:{?}", .{self.id, range, at});
                    switch (self.matchRange(range, input, last_at, qtty, starts_with_not, has_more)) {
                        .GoToNextItem => {
                            continue :next_item;
                        },
                        .Null => {
                            break :next_item;
                        },
                        .Pos => |pos| {
                            if (!item.checkBehind(input, last_at)) {
                                // mtl.debug(@src(), "group_{?}", .{self.id});
                                return null;
                            }
                            at = pos;
                            break :next_item;
                        }
                    }
                },
                else => |v| {
                    _ = &v;
                    // mtl.debug(@src(), "UNTREATED => {}", .{v});
                }
            }
        }

        const last_at = at orelse {
            // mtl.debug(@src(), "group_{?} at:null", .{self.id});
            return null;
        };
        self.regex.params.from = last_at;
        if (self.matchAnyOf()) {
            const gr = input.charAtIndex(last_at) orelse return null;
            if (self.anyLookBehind()) {
                at = args.from.minusGrapheme(gr);
            } else {
                at = args.from.plusGrapheme(gr);
            }
            if (TraceAnyOf) {
                mtl.debug(@src(), "was:{}, is:{?}", .{last_at, at});
            }
        }

        
        if (!last_at.isPast(input) and startsWithMeta(tokens.items, .SymbolEndOfLine)) {
            const gr = input.charAtIndex(last_at) orelse return null;
            if (!gr.eqCp('\n')) {
                return null;
            }
        }

        self.addCapture(input.slice(args.from, last_at)) catch return null;

        return at;
    }

    fn parseIntoTokens(self: *Group, index: Index) !Index {
        var str_iter = StringIterator.New(&self.regex.pattern, index);
        var ret_idx: ?Index = null;
        const new_array = ArrayList(Item).init(self.regex.alloc);
        try self.token_arr.append(new_array);
        var current_arr: *ArrayList(Item) = &self.token_arr.items[0];

        var plb: ?*Group = null;
        var nlb: ?*Group = null;
        _ = &plb;
        _ = &nlb;

        while (str_iter.next()) |gr| {
            if (gr.eqCp('[')) {
                if (self.hasContent() or self.isRoot()) {
                    var new_group = Group.New(self.regex, self);
                    new_group.match_type = .AnyOf;
                    const newg = str_iter.next() orelse return error.Other;
                    str_iter.continueFrom(try new_group.parseIntoTokens(newg.idx));
                    try current_arr.append(Item.newGroup(new_group));
                } else {
                    self.match_type = .AnyOf;
                }
            } else if (gr.eqCp(']')) {
                ret_idx = gr.idx.addRaw(1);
                break;
            } else if (gr.eqCp('(')) {
                if (self.hasContent() or self.isRoot()) {
                    var new_group = Group.New(self.regex, self);
                    new_group.match_type = .All;
                    const newg = str_iter.next() orelse return error.Other;
                    str_iter.continueFrom(try new_group.parseIntoTokens(newg.idx));
                    try current_arr.append(Item.newGroup(new_group));
                } else {
                    self.match_type = .All;
                }
            } else if (gr.eqCp(')')) {
                ret_idx = gr.idx.addRaw(1);
                break;
            } else if (gr.eqCp('?')) {
                const s: *String = &self.regex.pattern;
                if (s.matchesAscii("?:", .{.from=gr.idx})) |idx| {
                    str_iter.continueFrom(idx);
                    try current_arr.append(Item.newMeta(.NonCapture));
                    // self.non_capture = true;
                } else if (s.matchesAscii("?!", .{.from=gr.idx})) |idx_past| {
                    str_iter.continueFrom(idx_past);
                    try current_arr.append(Item.newMeta(.NegativeLookAhead));
                } else if (s.matchesAscii("?=", .{.from=gr.idx})) |idx| {
                    str_iter.continueFrom(idx);
                    try current_arr.append(Item.newMeta(.PositiveLookAhead));
                } else if (s.matchesAscii("?<!", .{.from=gr.idx})) |idx| {
                    str_iter.continueFrom(idx);
                    try current_arr.append(Item.newMeta(.NegativeLookBehind));
                } else if (s.matchesAscii("?<=", .{.from=gr.idx})) |idx| {
                    str_iter.continueFrom(idx);
                    try current_arr.append(Item.newMeta(.PositiveLookBehind));
                } else if (s.matchesAscii("?<", .{.from=gr.idx})) |idx| { //(?<name>\\w+) = name = e.g."Jordan"
                    str_iter.continueFrom(idx);
                    // named capture
                    if (s.indexOfAscii(">", .{.from = idx.addRaw("?<".len)})) |closing_idx| {
                        const name = try s.betweenIndices(idx, closing_idx);
                        // mtl.debug(@src(), "Name: \"{}\"", .{name});
                        try current_arr.append(Item.newMeta(.NamedCapture));
                        try addName(current_arr, name);
                        str_iter.continueFrom(closing_idx.addRaw(1)); // go past ">"
                    }
                } else { // just "?"
                    try addQtty(current_arr, Qtty.ZeroOrOne());
                }
            } else if (gr.eqCp('{')) {
                const s: *String = &self.regex.pattern;
                if (s.indexOfAscii("}", .{.from = gr.idx.addRaw(1)})) |idx| {
                    const qtty_in_curly = try s.betweenIndices(gr.idx.addRaw("}".len), idx);
                    defer qtty_in_curly.deinit();
                    str_iter.continueFrom(idx.addRaw("}".len));
                    const qtty = try Qtty.FromCurly(qtty_in_curly);
                    try addQtty(current_arr, qtty);
                } else {
                    mtl.debug(@src(), "Not found closing '}}'", .{});
                }
            } else if (gr.eqCp('\\')) {
                const symbol = str_iter.next() orelse break;
                if (symbol.eqCp('d')) {
                    try current_arr.append(Item.newMeta(.SymbolNumber));
                } else if (symbol.eqCp('D')) {
                    try current_arr.append(Item.newMeta(.SymbolNonNumber));
                } else if (symbol.eqCp('w')) {
                    try current_arr.append(Item.newMeta(.SymbolWordChar));
                } else if (symbol.eqCp('W')) {
                    try current_arr.append(Item.newMeta(.SymbolNonWordChar));
                } else if (symbol.eqCp('s')) {
                    try current_arr.append(Item.newMeta(.SymbolWhitespace));
                } else if (symbol.eqCp('S')) {
                    try current_arr.append(Item.newMeta(.SymbolNonWhitespace));
                } else if (symbol.eqCp('.')) {
                    try addAscii(current_arr, "."); // literally the dot character
                } else if (symbol.eqCp('b')) {
                    try current_arr.append(Item.newMeta(.SymbolWordBoundary));
                } else if (symbol.eqCp('B')) {
                    try current_arr.append(Item.newMeta(.SymbolNonWordBoundary));
                } else if (symbol.eqCp('|')) {
                    try addAscii(current_arr, "|");
                }
            } else if (gr.eqCp('^')) {
                if (gr.idx.gr == 0) {
                    try current_arr.append(Item.newMeta(.SymbolStartOfLine));
                } else {
                    try current_arr.append(Item.newMeta(.Not));
                }
            } else if (gr.eqCp('+')) {
                if (self.match_type == .AnyOf) {
                    try addGrapheme(current_arr, gr);
                } else {
                    var qtty = Qtty.OneOrMore();
                    if (str_iter.next()) |ng| {
                        if (ng.eqCp('?')) {
                            qtty.greedy = false;
                        } else {
                            str_iter.continueFrom(gr.idx.addRaw(1));
                        }
                    }
                    try addQtty(current_arr, qtty);
                }
            } else if (gr.eqCp('*')) {
                if (self.match_type == .AnyOf) {
                    try addGrapheme(current_arr, gr);
                } else {
                    var qtty = Qtty.ZeroOrMore();
                    if (str_iter.next()) |ng| {
                        if (ng.eqCp('?')) {
                            qtty.greedy = false;
                        } else {
                            str_iter.continueFrom(gr.idx.addRaw(1));
                        }
                    }
                    try addQtty(current_arr, qtty);
                }
            } else if (gr.eqCp('\n')) {
                try current_arr.append(Item.newMeta(.SymbolNewLine));
            } else if (gr.eqCp('\t')) {
                try current_arr.append(Item.newMeta(.SymbolTab));
            } else if (gr.eqCp('.')) {
                // mtl.debug(@src(), "anyof: {}", .{self.match_type});
                if (self.match_type == .AnyOf) {
                    try addGrapheme(current_arr, gr);
                } else {
                    try current_arr.append(Item.newMeta(.SymbolAnyChar));
                }
            } else if (gr.eqCp('$')) {
                try current_arr.append(Item.newMeta(.SymbolEndOfLine));
            } else if (gr.eqCp('|')) {
                if (current_arr.items.len == 0) {
                    return error.Parsing;
                }
                const new_arr = ArrayList(Item).init(self.regex.alloc);
                try self.token_arr.append(new_arr);
                current_arr = &self.token_arr.items[self.token_arr.items.len - 1];
            } else {
                try addGrapheme(current_arr, gr);
            }
        }

        try self.analyzeTokens();

        if (self.token_arr.items.len > 0) {
            var items_iter = Iterator(Item).New(self.token_arr.items[0].items);
            self.look_around = LookAround.From(&items_iter);
        }

        return if (ret_idx) |idx| idx else str_iter.position;
    }

    fn parseRange(s: String, tokens: *ArrayList(Item)) !void {
        const idx = s.indexOfAscii("-", .{}) orelse return;
        var iter = s.iteratorFrom(idx);
        const prev_idx = iter.prevFrom(idx) orelse return;
        const next_idx = iter.nextFrom(idx) orelse return;
        const cp1 = prev_idx.getCodepoint() orelse return;
        const cp2 = next_idx.getCodepoint() orelse return;
        // mtl.debug(@src(), "{dt} cp1:{}, cp2:{}", .{s, cp1, cp2});
        if (cp1 > cp2) {
            mtl.debug(@src(), "Error: {}({}) > {}({})", .{prev_idx, cp1, next_idx, cp2});
            return;
        }
        const range = GraphemeRange.New(cp1, cp2);
        // mtl.debug(@src(), "Range: {}", .{range});
        
        if (s.size() == 3) {
            try tokens.append(Item.newRange(range));
            return;
        }

        var left: String = .{};
        var right: String = .{};
        if (prev_idx.idx.gr != 0 and next_idx.idx.gr != 0) {
            left = try s.betweenIndices(.{}, prev_idx.idx);
        }

        const str_end = s.beforeLast();
        if (next_idx.idx.gr < str_end.gr) {
            const next_gr = iter.nextIndex() orelse return;
            right = try s.midIndex(next_gr);
        }
        
        if (!right.isEmpty()) {
            const len = tokens.items.len;
            try parseRange(right, tokens);
            const items_added = len != tokens.items.len;
            if (items_added) {
                right.deinit();
            } else {
                try tokens.append(Item.newString(right));
            }
        } else {
            right.deinit();
        }

        try tokens.append(Item.newRange(range));
        if (!left.isEmpty()) {
            try tokens.append(Item.newString(left));
        } else {
            left.deinit();
        }
    }

    fn prepareForNewSearch(self: *Group) void {
        self.capture_index = 0;
        self.captures.clearAndFree();

        for (self.token_arr.items) |*arr| {
            for (arr.items) |*t| {
                switch (t.data) {
                    .group => |*g| {
                        g.prepareForNewSearch();
                    },
                    else => {}
                }
            
            }
        }
    }

    fn printMeta(writer: anytype, m: Meta) !void {
         try writer.print("{s}{}{s} ", .{mtl.COLOR_CYAN, m, mtl.COLOR_DEFAULT});
    }

    pub fn printTokens(self: Group, writer: anytype) void {
        writer.print("{}\n", .{self}) catch {};
        for (self.token_arr.items, 0..) |arr, i| {
            _ = i;
            // mtl.debug(@src(), "Group Array={}", .{i});
            for (arr.items) |item| {
                switch (item.data) {
                    .group => |*g| {
                        g.printTokens(writer);
                    },
                    else => {},
                }
            }
        }
    }

    pub fn registerLookBehinds(self: *Group, lb: ?*Group) ?*Group {
        // mtl.debug(@src(), "group.id={?}", .{self.id});
        var my_lb: ?*Group = lb;
        for (self.token_arr.items) |*arr| {
            for (arr.items) |*item| {
                switch (item.data) {
                    .group => |*subgroup| {
                        if (subgroup.anyLookBehind()) {
                            my_lb = subgroup;
                        } else if (my_lb) |lb_unwrapped| {
                            item.lb = lb_unwrapped;
                            // mtl.debug(@src(), "set lb on item:{}", .{item});
                            my_lb = null;
                        } else {
                            my_lb = subgroup.registerLookBehinds(my_lb);
                        }
                        
                    },
                    else => {
                        if (my_lb) |lb_unwrapped| {
                            // mtl.debug(@src(), "set lb group.id:{?} on item:{?}", .{lb_unwrapped.id, item});
                            item.lb = lb_unwrapped;
                            my_lb = null;
                        }
                    },
                }
            }
        }

        return my_lb;
    }

    pub fn setCaptureIndex(self: *Group, index: usize) usize {
        var new_index = index;
        if (self.canCapture()) {
            self.capture_index = new_index;
            new_index += 1;
        }

        for (self.token_arr.items) |*arr| {
            for (arr.items) |*t| {
                switch (t.data) {
                    .group => |*g| {
                        new_index = g.setCaptureIndex(new_index);
                    },
                    else => {}
                }
            }
        }

        return new_index;
    }

    pub fn shouldCapture(self: *const Group) bool {
        const la = self.look_around;

        return la.non_capture or la.negative_lookahead or
            la.positive_lookahead or la.negative_lookbehind or
            la.positive_lookbehind;
    }

    fn startsWithMeta(slice: []const Item, meta: Meta) bool {
        if (slice.len == 0) {
            return false;
        }

        return slice[0].isMeta(meta);
    }
};

tokens: ArrayList(Item),
pattern: String,
alloc: Allocator,
top_group: Group = undefined,
next_group_id: IdType = 0,
found: ?Slice = null,
input: *const String = undefined,
params: FindParams = .{},
count: isize = 0,
charset: Charset = .Ascii,
state: State = .{},

// Regex takes ownership over `pattern`
pub fn New(alloc: Allocator, pattern: String) !*Regex {
    errdefer pattern.deinit();
    const regex = try alloc.create(Regex);
    errdefer alloc.destroy(regex);
    regex.* = Regex {
        .alloc = alloc,
        .pattern = pattern,
        .tokens = ArrayList(Item).init(alloc),
    };
    
    var top_group: Group = Group.New(regex, null);
    errdefer top_group.deinit();
    _ = try top_group.parseIntoTokens(String.strStart());
    regex.top_group = top_group;
    _ = regex.top_group.registerLookBehinds(null);
    regex.top_group.adjustLookBehinds(null);

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

pub fn findNext(self: *Regex) ?Index {
    self.found = null;
    self.top_group.prepareForNewSearch();
    var string_iter = self.input.iteratorFrom(self.params.from);

    while (string_iter.next()) |gr| {
        if (self.params.from.gr > gr.idx.gr) {
            string_iter.continueFrom(self.params.from);
            string_iter.first_time = false;
            continue;
        }
        
        if (self.top_group.matches(self.input, gr.idx)) |end_pos| {
            const next_slice = self.input.slice(gr.idx, end_pos);
            self.found = next_slice;
            return end_pos;
        }
    }

    _ = self.top_group.setCaptureIndex(1);    

    return null;
}

pub fn format(self: *const Regex, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = options;
    _ = fmt;
    _ = &writer;
    const charset = if (self.charset == .Ascii) "ASCII" else "Unicode";
    try writer.print("Regex(\\w={s}): {dt}\n", .{charset, self.pattern});
    self.top_group.printTokens(writer);
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

fn lookingBehind(self: *const Regex) bool {
    return self.state.looking_behind;
}

fn setLookingBehind(self: *Regex, flag: bool) void {
    self.state.looking_behind = flag;
}

pub fn Search(alloc: Allocator, pattern: []const u8, input: []const u8) !void {
    const regex_pattern = try String.From(pattern);

    const regex = Regex.New(alloc, regex_pattern) catch |e| {
        mtl.debug(@src(), "Can't create regex: {}", .{e});
        return e;
    };
    defer regex.deinit();
    // const charset = if (regex.charset == .Ascii) "ASCII" else "Unicode";
    // mtl.debug(@src(), "Regex(\\w={s}): {dt}", .{charset, regex_pattern});
    // regex.printGroups();
    mtl.debug(@src(), "{}", .{regex});

    const input_str = try String.From(input);
    defer input_str.deinit();
    regex.setParams(&input_str, .{.qtty = .All(), .cs = .Yes});
    try input_str.printGraphemes(@src());

    for (0..std.math.maxInt(usize)) |i| {
        var first_time = true;
        if (regex.searchNext()) |currently_at| {
            if (first_time) {
                first_time = false;
                mtl.debug(@src(), "{s}Search #{} =======>{s}", .{mtl.COLOR_ORANGE, i, mtl.COLOR_DEFAULT});
            }
            mtl.debug(@src(), "{s}Success!{s} Search ended at {}, found: {?dt}\n",
            .{mtl.BGCOLOR_ORANGE, mtl.BGCOLOR_DEFAULT, currently_at, regex.found});
            if (currently_at.gr >= input_str.size()) {
                break;
            }
        } else {
            break;
        }
    }
}

pub fn searchNext(self: *Regex) ?Index {
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

pub fn setParams(self: *Regex, input: *const String, params: FindParams) void {
    self.input = input;
    self.params = params;
    self.count = 0;
}

test "Test regex" {
    const alloc = std.testing.allocator;
    String.ctx = try String.Context.New(alloc);
    defer String.ctx.deinit();

    if (false) {
        const pattern = \\(?<=[abc]xyz+\s)(\s\d{2,}ab)
;
        const input = "bxyz  789ab cxyzz  012ab";
        try Search(alloc, pattern, input);
    }

    if (false) {
        //[a-zA-Z0-9._%+-]+@[a-zA-Z0-9-]+(\.[a-zA-Z]{2,})+
        const pattern = \\[\w._%+-]+@[\w-]+(\.[\w]{2,})+
;
        const input = "at support@example.рф \u{AE} \u{1f4a9} or sales@company.co.uk";

//at support@example.com or sales@company.org
        try Search(alloc, pattern, input);
    }

    if (true) {
        const pattern =
\\=(=-){2,5}(AB|CD{2})[EF|^GH](?=Mi\S{2})(?<ClientName>\w+)(?:БГД[^zyA-Z0-9c]opq(?!05))xyz{2,3}(?=\d{2,}$)
;
        const input = "A==-=-CDDKMikeБГДaopqxyzz567\n";
        try Search(alloc, pattern, input);
    }

    if (false) {
        const pattern =
\\[^zyA-Z0-9c]opq
;
        const input = "aopqxyz";
        try Search(alloc, pattern, input);
    }
}

//() - catpure group, referred by index number preceded by $, like $1
//(?:) - non capture group
    
// (?!) – negative lookahead
// (?=) – positive lookahead

// (?<!) – negative lookbehind
// (?<=) – positive lookbehind

// \b\w+(?<!s)\b. This is definitely not the same as \b\w+[^s]\b
