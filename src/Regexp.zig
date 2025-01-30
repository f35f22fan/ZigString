const std = @import("std");
const ArrayList = std.ArrayList;
const Str = @import("String.zig");
const mtl = Str.mtl;
const Cp = Str.Codepoint;
const Regexp = @This();

pub const Repeat = enum(u8) {
    Once,
    OnceOrMore,
    ZeroOrMore,
};

const Range = struct {Cp, ?Cp};

pub const EvalAs = enum(u8) {
    Or,
    Not,
};

const OneOrAll = enum(u8) {
    One,
    All,
};

const Group = struct {
    str: Str,
    ooa: OneOrAll,
    pub fn deinit(self: Group) void {
        self.str.deinit();
    }
};

global_search: bool = true,
case_sensitive: bool = true,
groups: ArrayList(Group),
ctor_str: Str,

pub fn Compile(s: Str) !Regexp {
    var r = Regexp {
        .ctor_str = s,
        .groups = ArrayList(Group).init(Str.ctx.a),
    };

    try r.analyze();

    return r;
}

fn analyze(self: *Regexp) !void {
    mtl.debug(@src(), "analyzing={}", .{self.ctor_str});
    var index = Str.strStart();
    while (index.next(&self.ctor_str)) |grapheme| {
        mtl.debug(@src(), "{}={}", .{grapheme.idx, grapheme});
    }
}

pub fn deinit(self: Regexp) void {
    for (self.groups.items) |g| {
        g.deinit();
    }
    self.ctor_str.deinit();
}

test "Test regexp" {
    const alloc = std.testing.allocator;
    Str.ctx = try Str.Context.New(alloc);
    defer Str.ctx.deinit();

    const regexp = try Regexp.Compile(try Str.From("[abc]"));
    defer regexp.deinit();

    mtl.debug(@src(), "testing regexp={}", .{regexp.ctor_str});
}

