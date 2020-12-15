const std = @import("std");
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const builtin = std.builtin;

fn serialize(comptime T: type, data: T, l: *ArrayList(u8)) !void {
    const info = @typeInfo(T);
    switch (info) {
        .Int => {
            const N = @sizeOf(T);
                    comptime var i: usize = 0;
                    inline while (i < N) : (i += 1) {
                        const byte: u8 = @truncate(u8, data >> (8 * i));
                        try l.append(byte);
                    }
        },
        .Bool => {
            if (data) {
                try l.append(1);
            } else {
                try l.append(0);
            }
        },
        else => {
            return error.UnknownType;
        },
    }
}

test "serializes uint8" {
    var data: u8 = 0x55;
    const serialized_data = [_]u8{0x55};
    const exp = serialized_data[0..serialized_data.len];

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(u8, data, &list);
    expect(std.mem.eql(u8, list.items, exp));
}

test "serializes uint16" {
    var data: u16 = 0x5566;
    const serialized_data = [_]u8{ 0x66, 0x55 };
    const exp = serialized_data[0..serialized_data.len];

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(u16, data, &list);
    expect(std.mem.eql(u8, list.items, exp));
}

test "serializes uint32" {
    var data: u32 = 0x55667788;
    const serialized_data = [_]u8{ 0x88, 0x77, 0x66, 0x55 };
    const exp = serialized_data[0..serialized_data.len];

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(u32, data, &list);
    expect(std.mem.eql(u8, list.items, exp));
}

test "serializes bool" {
    var data = false;
    var serialized_data = [_]u8{0x00};
    var exp = serialized_data[0..serialized_data.len];

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(bool, data, &list);
    expect(std.mem.eql(u8, list.items, exp));

    data = true;
    serialized_data = [_]u8{0x01};
    exp = serialized_data[0..serialized_data.len];

    var list2 = ArrayList(u8).init(std.testing.allocator);
    defer list2.deinit();
    try serialize(bool, data, &list2);
    expect(std.mem.eql(u8, list2.items, exp));
}
