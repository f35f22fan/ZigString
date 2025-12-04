const std = @import("std");
const mtl = @import("mtl.zig");
const io = @import("io.zig");
const String = @import("String.zig").String;
const Regex = @import("Regex.zig");

const ArrayList = std.ArrayList;
// var out = std.io.getStdOut().writer();
const Codepoint = String.Codepoint;
const Index = String.Index;
const Context = String.Context;
const E = error {NotFound, Other};
const alloc = std.heap.page_allocator;//std.testing.allocator;

const Shape = struct {
    ptr: *anyopaque,
    fnPtr: *const fn(ptr: *anyopaque) void,

    fn from(pointer: anytype) Shape {
        const T = @TypeOf(pointer);
        // mtl.debug(@src(), "{any}", .{T});
        const gen = struct {
            pub fn opaqueFn(ptr: *anyopaque) void {
                const shape: T = @ptrCast(@alignCast(ptr));
                shape.draw();
            }
        };

        return Shape {
            .ptr = pointer,
            .fnPtr = gen.opaqueFn,
            // .constFnPtr = gen.constOpaqueFn,
        };
    }

    fn draw(self: Shape) void {
        self.fnPtr(self.ptr);
    }
};

const Circle = struct {
    r: f32 = undefined,

    fn draw(self: *Circle) void {
        mtl.debug(@src(), "Circle::draw() r={d:.4}, area={d:.4}",
            .{self.r, self.r * self.r * std.math.pi});
    }
};

const Triangle = struct {
    side1: usize = undefined,
    side2: usize = undefined,
    side3: usize = undefined,

    fn draw(self: *Triangle) void {
        mtl.debug(@src(), "Triangle::draw() {}, {}, {}", .{self.side1, self.side2, self.side3});
    }
};

fn getString() struct {i64, []const u8} {
    return .{5, "Hello"};
}

pub fn main() !u8 {
    String.ctx = try Context.New(alloc);
    defer String.ctx.deinit();

    const pattern = \\[a-z]
        //[a-zA-Z0-9._%+-]+@[a-zA-Z0-9-]+\.
;
    const input = "at support@example.com";

//at support@example.com or sales@company.org
    try Regex.Search(alloc, pattern, input);

    if (true) {
        return 0;
    }

    const values = .{
        @as(u32, 1234),
        @as(f64, 12.34),
        true,
        "hi",
    } ++ .{false} ** 2;

    inline for (values, 0..) |v, i| {
        mtl.debug(@src(), "{} => {any}", .{i, v});
    }

    const len, const str = getString();
    mtl.debug(@src(), "len={}, str={s}", .{len, str});

    var all = ArrayList(Shape).init(alloc);
    defer all.deinit();

    var triangle = Triangle {.side1=3, .side2=4, .side3=7};
    try all.append(Shape.from(&triangle));

    var circle = Circle {.r = 5};
    try all.append(Shape.from(&circle));

    for (all.items) |item| {
        item.draw();

        // const T = @TypeOf(item.ptr);
        // mtl.debug(@src(), "{any}", .{T});
    }

    return 0;
}

pub fn getData() [2]u32 {
    return .{15, 32};
}

pub fn parseU64(buf: []const u8, radix: u8) !u64 {
    var x: u64 = 0;

    for (buf) |c| {
        const digit = charToDigit(c);
        mtl.debug(@src(), "{}", .{digit});
        if (digit >= radix) {
            return error.InvalidChar;
        }

        // x *= radix
        var ov = @mulWithOverflow(x, radix);
        if (ov[1] != 0) return error.OverFlow;

        // x += digit
        ov = @addWithOverflow(ov[0], digit);
        if (ov[1] != 0) return error.OverFlow;
        x = ov[0];
        mtl.debug(@src(), "x={}, ov[0]={}", .{x, ov[0]});
    }

    return x;
}

fn charToDigit(c: u8) u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'A'...'Z' => c - 'A' + 10,
        'a'...'z' => c - 'a' + 10,
        else => std.math.maxInt(u8),
    };
}
