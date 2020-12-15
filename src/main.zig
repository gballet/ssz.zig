const std = @import("std");
const ArrayList = std.ArrayList;

fn serialize(comptime T: type, data: T, l: *ArrayList(u8)) !void {
    const info = @typeInfo(T);
    switch (info) {
        else => {
            return error.UnknownType;
        },
    }
}
