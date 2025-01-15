const std = @import("std");
const mtl = @import("mtl.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
pub const BitData = @This();

const Error = error {
    Other,
};

data: ArrayList(u8) = undefined,
pending: bool = false,
pos: u3 = 0,
value: u8 = 0,

pub fn New(alloc: Allocator) BitData {
    return BitData {
        .data = ArrayList(u8).init(alloc),
    };
}

pub fn deinit(self: BitData) void {
    self.data.deinit();
}

pub fn addBits(self: *BitData, bits: u3) !void {
    self.pending = true;
    const u3_as_u8: u8 = bits;
    //mtl.debug(@src(), "u3=0b{b:0>3}", .{u3_as_u8});

    switch (self.pos) {
        0...5 => {
            self.value |= (u3_as_u8 << self.pos);
            if (self.pos == 5) {
                try self.data.append(self.value);
                self.value = 0;
                self.pos = 0;
                self.pending = false;
            } else {
                self.pos += 3;
            }
        },
        6 => {
            self.value |= u3_as_u8 << 6;
            try self.data.append(self.value);
            self.value = u3_as_u8 >> 2;
            self.pos = 1;
        },
        7 => {
            self.value |= u3_as_u8 << 7;
            try self.data.append(self.value);
            self.value = u3_as_u8 >> 1;
            self.pos = 2;
        },
    }
}

pub fn byteCount(self: BitData) usize {
    return self.data.items.len;
}

pub fn bytes(self: BitData) []const u8 {
    return self.data.items;
}

pub fn finish(self: *BitData) !void {
    if (self.pending) {
        try self.data.append(self.value);
        self.pending = false;
    }
}

pub fn printBits(self: BitData) void {
    std.debug.print("ByteCount={}, <Bits> ", .{self.byteCount()});
    for (self.data.items) |item| {
        for (0..8) |bindex| {
            const bi: u3 = @intCast(7 - bindex);
            const b: u1 = @intCast((item >> bi) & 0b1);
            std.debug.print("{}", .{b});
        }
        //std.debug.print("={b:0>8}({d}) ", .{item, item});
        std.debug.print(" ", .{});
    }
    std.debug.print("</Bits>\n", .{});
}