const std = @import("std");
const ArrayList = std.ArrayList;
const String = @import("String.zig");
const Grapheme = String.Grapheme;
const Direction = String.Direction;
const Index = String.Index;
const Slice = String.Slice;
const Charset = String.Charset;
const CharsetArgs = String.CharsetArgs;
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
const TraceGroupResult: bool = true;

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

pub const GraphemeRange = struct {
    a: Cp,
    b: Cp,

    pub fn New(a: Cp, b: Cp) GraphemeRange {
        return .{.a = a, .b = b};
    }

    pub fn within(self: GraphemeRange, input: Slice, cs: CaseSensitive) bool {
        var cp = input.charAtIndexOneCp(input.start) orelse return false;
        if (cs == .Yes) {
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

pub const Item = struct {
    data: ItemData = undefined,
    lb: ?*Group = null,

    pub fn deinit(self: Item) void {
        self.data.deinit();
    }

    fn checkBehind(item: *Item, haystack: *const String, from: Index) bool {
        const lb_group = item.lb orelse return true;
        if (!lb_group.anyLookBehind()) {
            mtl.trace(@src());
            return false;
        }

        lb_group.look_around.looking_behind = true;
        mtl.debug(@src(), "lb_group.id:{?}, from:{}", .{lb_group.id, from});
        const idx = lb_group.matches(haystack, from);
        mtl.debug(@src(), "<<<<<<<===== idx:{?}", .{idx});
        lb_group.look_around.looking_behind = false;

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
    looking_behind: bool = false,
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
        if (self.lookingBehind()) {
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
        try arr.append(Item.newString(try String.FromAscii(s)));
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
        return Args{.cs=self.regex.params.cs, .look_ahead = !self.lookingBehind()};
    }

    fn endsWithMeta(slice: []const Item, meta: Meta) bool {
        if (slice.len == 0) {
            return false;
        }

        return slice[slice.len - 1].isMeta(meta);
    }

    // returns past last found grapheme, or null
    pub fn findNextChars(self: *Group, item: *Item, haystack: Slice, from: Index, meta: Meta, qtty: Qtty) ?Index {
        const positive_lookahead = self.look_around.positive_lookahead;
        var ret_idx: ?Index = null;
        var string_iter = haystack.iteratorFrom(from);
        var count: usize = 0;
        var found_enough = false;
        
        const direction: Direction = if (self.lookingBehind()) .Back else .Forward;
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
                    found_next_one = gr.isWordChar(self.regex.csa);
                    // mtl.debug(@src(), "SymbolWordChar:\"{dt}\", ({})", .{gr, found_next_one});
                },
                .SymbolNonWordChar => {
                    found_next_one = !gr.isWordChar(self.regex.csa);
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

            ret_idx = if (self.lookingBehind()) string_iter.position else gr.idx.plusGrapheme(gr);
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

        // if (self.anyLookBehind()) {
        //     mtl.debug(@src(), "Found Enough: count:{}, needed:{}, from:{}, ret_idx:{?}", .{count, qtty, from, ret_idx});
        // }

        return ret_idx;
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
                switch (t.data) {
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

    fn lookingBehind(self: Group) bool {
        return self.look_around.looking_behind;
    }

    fn matchAll(self: *const Group, haystack: Slice, needles: Slice, qtty: Qtty, not: bool) ?Index {
        if (qtty.a == 0 and !qtty.greedy) {
            return haystack.start;
        }

        if (self.lookingBehind()) {
            const idx = self.matchAllBehind(haystack, needles, qtty, not);
            // mtl.debug(@src(), "haystack: {dt}, needles:{}, result:{?}", .{haystack, needles, idx});
            return idx;
        }

        if (qtty.exactNumber(1)) {
            if (self.lookingBehind()) {
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
        mtl.debug(@src(), "needles_base:{dt}, needles:{dt}, haystack:{dt}",
            .{needles_minus_last, needles, haystack});
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
        _ = self;
        const last_gr = needles.lastChar() orelse return null;
        // mtl.debug(@src(), "haystack: {dt}, needles: {dt}, last_char:{dt}, qtty: {}", .{haystack, needles, last_gr, qtty});

        var count: usize = 0;
        _ = &count;
        var haystack_iter = haystack.iteratorFromEnd();
        var at: ?Index = null;
        while (haystack_iter.prev()) |char| {
            // mtl.debug(@src(), "{dt} vs {dt}", .{char, last_gr});
            if (char.eq(last_gr, .Yes)) {
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
            mtl.debug(@src(), "not enough: {} for {dt}", .{count, last_gr});
            return null;
        }

        const base = needles.slice(.{}, needles.beforeLast());
        const from = at orelse return null;
        const h = haystack.leftSlice(from);
        var retval: ?Index = null;
        if (h.endsWith(base)) |pos| {
            retval = if (not) null else pos;
        } else {
            if (not) {
                retval = haystack.findIndexFromEnd(base.size());
            } else {
                retval = null;
            }
        }

        if (TraceLB) {
            mtl.debug(@src(), "count: {}, h:{dt}, retval:{?}", .{count, h, retval});
        }

        return retval;
    }

    fn matchAnyChar(self: *const Group, any_of: Slice, haystack: Slice, args: Args, not: bool) ?Index {
        const negative_lookahead = self.look_around.negative_lookahead;
        const hgr = haystack.charAtIndex(args.from) orelse return null;
        const any_lb = self.anyLookBehind();
        var string_iter = if (any_lb) any_of.iteratorFromEnd() else any_of.iterator();
        const direction: Direction = if (any_lb) .Back else .Forward;
        var retval: ?Index = null;
        while (string_iter.go(direction)) |gr| {
            const gr_match = gr.eq(hgr, args.cs);
            if (not) {
                if (gr_match) {
                    return null;
                }
            } else if (gr_match) {
                if (negative_lookahead) {
                    retval = args.from;
                    break;
                } else if (any_lb) {
                    retval = args.from.minusGrapheme(gr);
                    break;
                } else {
                    retval = args.from.plusGrapheme(gr);
                    break;
                }
            }
        }

        if (not) {
            if (any_lb) {
                retval = args.from.minusGrapheme(hgr);
            } else {
                retval = args.from.plusGrapheme(hgr);
            }
        }

        if (TraceLB and any_lb) {
            mtl.debug(@src(), "retval:{?}, args.from:{}, hgr:{dt}, any_of:{dt}, haystack:{dt}, lb:{}, looking_behind:{}",
                .{retval, args.from, hgr, any_of, haystack, any_lb, self.lookingBehind()});
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
        for (self.token_arr.items, 0..) |*arr, i| {
            if (arr.items.len == 0) {
                continue;
            }
            
            arr_idx = i;
            if (self.matchesArray(arr, haystack, args)) |idx_after| {
                result = idx_after;
                break;
            }
        }

        if (TraceGroupResult) {
            mtl.debug(@src(), "TraceResult from:{}, group_{?}, arr_idx:{} result:{?}", .{from.gr, self.id, arr_idx, result});
        }

        return result;
    }

    fn matchesArray(self: *Group, tokens: *ArrayList(Item), input: *const String, args: Args) ?Index {
        var items_iter = Iterator(Item).New(tokens.items);
        var direction: Direction = undefined;
        if (self.lookingBehind()) {
            direction = .Back;
            items_iter.toEnd();
        } else {
            if (self.look_around.anyLookBehind()) {
                // must be performed after the token in front of it matches.
                return args.from;
            }
            direction = .Forward;
        }

        var at = args.from;
        if (startsWithMeta(tokens.items, .SymbolStartOfLine)) {
            if (at.cp != 0) {
                const prev_gr = input.prev(at) orelse return null;
                if (!prev_gr.eqCp('\n')) {
                    return null;
                }
            }
        }
// if previous token is a look_behind, call it.
        const not = startsWithMeta(tokens.items, .Not);
        while (items_iter.go(direction)) |item| {
            // mtl.debug(@src(), "item:{}, items_iter.at:{}", .{item, items_iter.at});
            const qtty = getNextQtty(&items_iter, self.lookingBehind());
            const haystack = if (self.lookingBehind()) input.leftSlice(at) else input.midSlice(at);
            switch (item.data) {
                .str => |*needles_str| {
                    const needles = needles_str.asSlice();
                    if (self.match_type == .All) {
                        if (self.matchAll(haystack, needles, qtty, not)) |after_last| {
                            if (!item.checkBehind(input, at)) {
                                return null;
                            }
                            // mtl.debug(@src(), "after matchAll() at:{}, after_last:{}", .{at, after_last});
                            at = after_last;
                        } else {
                            return null;
                        }
                    } else { // == .AnyOf
                        if (self.matchAnyChar(needles, haystack, .{.from=at, .cs=args.cs}, not)) |idx_after| {
                            // mtl.debug(@src(), "AnyOf: idx_after:{?}, at:{}, lb:{}",
                                // .{idx_after, at, self.anyLookBehind()});
                            if (!item.checkBehind(input, at)) {
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
                            at = self.findNextChars(item, haystack, at, m, qtty) orelse return null;
                        },
                        .SymbolWordBoundary => {
                            if (!haystack.isWordBoundary(at)) {
                                return null;
                            }
                            if (!item.checkBehind(input, at)) {
                                return null;
                            }
                        },
                        .SymbolNonWordBoundary => {
                            if (haystack.isWordBoundary(at)) {
                                return null;
                            }
                            if (!item.checkBehind(input, at)) {
                                return null;
                            }
                        },
                        .SymbolNumber => {
                            const idx = self.findNextChars(item, haystack, at, m, qtty);
                            // mtl.debug(@src(), "(SymbolNumber) group:{?}, at:{?}", .{self.id, idx});
                            at = idx orelse return null;
                            
                        },
                        .SymbolNonNumber => {
                            at = self.findNextChars(item, haystack, at, m, qtty) orelse return null;
                        },
                        .SymbolWhitespace => {
                            const idx = self.findNextChars(item, haystack, at, m, qtty);
                            // mtl.debug(@src(), "(SymbolWhitespace) group:{?}, at:{?}", .{self.id, idx});
                            at = idx orelse return null;
                        },
                        .SymbolNonWhitespace => {
                            at = self.findNextChars(item, haystack, at, m, qtty) orelse return null;
                        },
                        else => |v| {
                            _ = v;
                            // mtl.debug(@src(), "UNTREATED META => {}", .{v});
                        }
                    }
                },
                .group => |*sub_group| {
                    // mtl.debug(@src(), "SUB_GROUP: {?}, start: {}", .{sub_group.id, at});
                    var count: usize = 0;
                    const group_started_at = at;
                    while (count < qtty.a or qtty.greedy) {
                        if (sub_group.matches(input, at)) |after_last| {
                            at = after_last;
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

                    if (!item.checkBehind(input, group_started_at)) {
                        return null;
                    }
                },
                .range => |range| {
                    var flag = range.within(haystack.midSlice(at), self.regex.params.cs);
                    if (not) {
                        flag = !flag;
                    }
                    if (!flag) {
                        // mtl.debug(@src(), "{} failed.", .{range});
                        return null;
                    }
                    if (!item.checkBehind(input, at)) {
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
                const gr = input.charAtIndex(at) orelse return null;
                at = at.plusGrapheme(gr);
                if (not) {
                    // mtl.debug(@src(), "="**20, .{});
                }
                self.addCapture(gr.slice()) catch return null;
            },
            else => {},
        }

        if (!at.isPast(input) and startsWithMeta(tokens.items, .SymbolEndOfLine)) {
            const gr = input.charAtIndex(at) orelse return null;
            if (!gr.eqCp('\n')) {
                return null;
            }
        }

        self.addCapture(input.slice(args.from, at)) catch return null;

        // if (self.anyLookBehind()) {
        //     mtl.debug(@src(), "group.id={?}, at:{?}", .{self.id, at});
        // }

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
                if (self.hasContent()) {
                    var new_group = Group.New(self.regex, self);
                    new_group.match_type = .AnyOf;
                    const newg = str_iter.next() orelse return error.Other;
                    str_iter.continueFrom(try new_group.parseIntoTokens(newg.idx));
                    // try addGroup(current_arr, new_group);
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
                    // try addGroup(current_arr, new_group);
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
                    // mtl.debug(@src(), "qtty_in_curly: {}", .{qtty});
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
                    // try addMeta(current_arr, Meta.SymbolWordChar);
                    try current_arr.append(Item.newMeta(.SymbolWordChar));
                } else if (symbol.eqCp('W')) {
                    // try addMeta(current_arr, Meta.SymbolNonWordChar);
                    try current_arr.append(Item.newMeta(.SymbolNonWordChar));
                } else if (symbol.eqCp('s')) {
                    // try addMeta(current_arr, Meta.SymbolWhitespace);
                    try current_arr.append(Item.newMeta(.SymbolWhitespace));
                } else if (symbol.eqCp('S')) {
                    // try addMeta(current_arr, Meta.SymbolNonWhitespace);
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
                    // self.must_start_on_line = true;
                    try current_arr.append(Item.newMeta(.SymbolStartOfLine));
                } else {
                    // mtl.debug(@src(), "Adding .Not to {?}, current_arr.len={}", .{self.id, current_arr.items.len});
                    try current_arr.append(Item.newMeta(.Not));
                }
            } else if (gr.eqCp('+')) {
                var q = Qtty.OneOrMore();
                if (str_iter.next()) |ng| {
                    if (ng.eqCp('?')) {
                        q.greedy = false;
                    } else {
                        str_iter.continueFrom(gr.idx.addRaw(1));
                    }
                }
                try addQtty(current_arr, q);
            } else if (gr.eqCp('*')) {
                var q = Qtty.OneOrMore();
                if (str_iter.next()) |ng| {
                    if (ng.eqCp('?')) {
                        q.greedy = false;
                    } else {
                        str_iter.continueFrom(gr.idx.addRaw(1));
                    }
                }
                try addQtty(current_arr, Qtty.ZeroOrMore());
            } else if (gr.eqCp('\n')) {
                try current_arr.append(Item.newMeta(.SymbolNewLine));
            } else if (gr.eqCp('\t')) {
                try current_arr.append(Item.newMeta(.SymbolTab));
            } else if (gr.eqCp('.')) {
                try current_arr.append(Item.newMeta(.SymbolAnyChar));
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

        if (ret_idx) |idx| {
            return idx;
        }

        return str_iter.position;
    }

    fn parseRange(s: String, tokens: *ArrayList(Item)) !void {
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
            try tokens.append(Item.newRange(range));
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
         try writer.print("{s}{}{s} ", .{String.COLOR_CYAN, m, String.COLOR_DEFAULT});
    }

    pub fn printTokens(self: Group) void {
        mtl.debug(@src(), "{}", .{self});
        for (self.token_arr.items, 0..) |arr, i| {
            _ = i;
            // mtl.debug(@src(), "Group Array={}", .{i});
            for (arr.items) |item| {
                switch (item.data) {
                    .group => |*g| {
                        g.printTokens();
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
csa: CharsetArgs = .{},

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
    self.found = null;
    self.top_group.prepareForNewSearch();
    var string_iter = self.input.iteratorFrom(self.params.from);
    
    while (string_iter.next()) |gr| {
        // const slice = self.input.midSlice(gr.idx);
        // mtl.debug(@src(), "slice: {dt}", .{slice});
        if (self.top_group.matches(self.input, gr.idx)) |end_pos| {
            string_iter.continueFrom(end_pos);
            const next_slice = self.input.slice(gr.idx, end_pos);
            self.found = next_slice;
            return end_pos;
        }
    }

    _ = self.top_group.setCaptureIndex(1);    

    return null;
}

fn Search(alloc: Allocator, pattern: []const u8, input: []const u8) !void {
    const regex_pattern = try String.From(pattern);

    const regex = Regex.New(alloc, regex_pattern) catch |e| {
        mtl.debug(@src(), "Can't create regex: {}", .{e});
        return e;
    };
    defer regex.deinit();
    mtl.debug(@src(), "Regex: {dt}", .{regex_pattern});
    regex.printGroups();

    const input_str = try String.From(input);
    defer input_str.deinit();
    regex.setParams(&input_str, .{.qtty = .All(), .cs = .Yes});
    try input_str.printGraphemes(@src());

    for (0..std.math.maxInt(usize)) |i| {
        mtl.debug(@src(), "New Search #{} =======>", .{i});
        if (regex.searchNext()) |currently_at| {
            mtl.debug(@src(), "Success! Search ended at {}, found: {?dt}", .{currently_at, regex.found});
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

pub fn printGroups(self: Regex) void {
    self.top_group.printTokens();
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

    if (true) {
        const pattern =
\\=(=-){2,5}(AB|CD{2})[EF|^GH](?<ClientName>\w+)(?:БГД[^zyA-Z0-9c1-3]opq(?!05))xyz{2,3}(?=\d{2,})$
;
        const input = "A==-=-CDDKMikeБГДaopqxyzz567\n";
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

// Excel formula example: =SUM(B1+0.3,20.9,-2.4+3*MAX(18,7),B2,C1:C2,MIN(A1,5))*(-3+2)