const std = @import("std");
pub const Num = @This();


value: ?i128 = null,
//currency: []const u8 = "$",
string: ?[]const u8 = null,

pub fn New(n: i128) Num {
    return Num {.value=n};
}

pub fn format(self: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    var value = self.value orelse 0;
    if (self.value == null) {
        if (self.string) |string| {
            value = std.fmt.parseInt(i128, string, 10) catch 0;
        } else return;
    }
    const is_negative = (value < 0);
    //try writer.writeAll(self.currency);
    var buffer: [64]u8 = undefined;
    var string_value = try std.fmt.bufPrint(&buffer, "{d:.2}", .{value});
    if (is_negative) string_value = string_value[1..];

    const decimal_index = std.mem.indexOfScalar(u8, string_value, '.') orelse string_value.len;
    var index: usize = 0;
    for (string_value[0..decimal_index], 0..) |c, i| {
        if (i > 0 and (decimal_index - i) % 3 == 0) {
            try writer.writeAll("_");
            index += 1;
        }
        try writer.writeByte(c);
        index += 1;
    }
    try writer.writeAll(string_value[decimal_index..]);
}