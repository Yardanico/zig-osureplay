const std = @import("std");
const warn = std.debug.warn;
const pf = @import("parse-float.zig");

const c = @cImport({
    @cInclude("lzma_header.h");
    @cInclude("easylzma/simple.h");
});

// Taken from std/debug/leb128.zig
fn readULEB128(comptime T: type, in_stream: var) !T {
    const ShiftT = @IntType(false, std.math.log2(T.bit_count));

    var result: T = 0;
    var shift: usize = 0;

    while (true) {
        const byte = try in_stream.readByte();

        if (shift > T.bit_count)
            return error.Overflow;

        var operand: T = undefined;
        if (@shlWithOverflow(T, byte & 0x7f, @intCast(ShiftT, shift), &operand))
            return error.Overflow;

        result |= operand;

        if ((byte & 0x80) == 0)
            return result;

        shift += 7;
    }
}

fn readString(in_stream: var, alloc: *std.mem.Allocator) ![]u8 {
    var res: []u8 = undefined;
    const is_str_present = try in_stream.readByte();
    if (is_str_present == 11) {
        const len = try readULEB128(u64, in_stream);
        var data: []u8 = try alloc.alloc(u8, len);
        try in_stream.readNoEof(data);
        return data;
    }
    return "";
}

inline fn isDigit(ch: u8) bool {
    return (ch >= '0' and ch <= '9') or ch == '-' or ch == '.';
}

pub const ReplayAction = struct {
    time_since_previous: i64 = undefined,
    x: f64 = undefined,
    y: f64 = undefined,
    key_mouse_set: i32 = undefined,

    fn init(data: []const u8) !ReplayAction {
        var res = ReplayAction{};
        // Entries are in "w|x|y|z" format, first is a long int,
        // second and third are floats, fourth is a int
        var it = std.mem.tokenize(data, "|");
        var current_var: usize = 0;
        while (it.next()) |item| : (current_var += 1) {
            switch (current_var) {
                0 => res.time_since_previous = try std.fmt.parseInt(i64, item, 10),
                1 => res.x = try pf.parse_float(item),
                2 => res.y = try pf.parse_float(item),
                3 => res.key_mouse_set = try std.fmt.parseInt(i32, item, 10),
                else => return error.InvalidReplayFile,
            }
        }
        return res;
    }
};

pub const PlayMode = packed enum {
    Standard,
    Taiko,
    CTB,
    Mania,
};

pub const OsuReplay = struct {
    play_mode: PlayMode,
    game_version: i32,
    beatmap_hash: []const u8,
    player_name: []const u8,
    replay_hash: []const u8,
    count_300s: i16,
    count_100s: i16,
    count_50s: i16,
    count_gekis: i16,
    count_katus: i16,
    count_misses: i16,
    total_score: i32,
    max_combo: i16,
    is_fc: bool,
    mod_list: i32,
    life_bar_graph: []const u8,
    unix_timestamp: i64,
    replay_data: std.ArrayList(ReplayAction) = undefined,
    online_score_id: i64 = 0,
    alloc: *std.mem.Allocator,

    pub fn init(st: var, alloc: *std.mem.Allocator) !OsuReplay {
        var r = OsuReplay{
            .play_mode = @intToEnum(PlayMode, @truncate(u2, try st.readByte())),
            .game_version = try st.readIntLittle(i32),
            .beatmap_hash = try readString(st, alloc),
            .player_name = try readString(st, alloc),
            .replay_hash = try readString(st, alloc),
            .count_300s = try st.readIntLittle(i16),
            .count_100s = try st.readIntLittle(i16),
            .count_50s = try st.readIntLittle(i16),
            .count_gekis = try st.readIntLittle(i16),
            .count_katus = try st.readIntLittle(i16),
            .count_misses = try st.readIntLittle(i16),
            .total_score = try st.readIntLittle(i32),
            .max_combo = try st.readIntLittle(i16),
            .is_fc = (try st.readByte()) != 0,
            .mod_list = try st.readIntLittle(i32),
            .life_bar_graph = try readString(st, alloc),
            .unix_timestamp = @divFloor(((try st.readIntLittle(i64)) - 621355968000000000), 10000000),
            .alloc = alloc,
        };
        // Read length of LZMA-compressed data
        const in_data_len = try st.readIntLittle(u32);
        // Allocate and read compressed data into a buffer
        var lzma_data = try alloc.alloc(u8, in_data_len);
        defer alloc.free(lzma_data);
        try st.readNoEof(lzma_data);
        // Variables for output from the LZMA decompression
        var out_data: []u8 = "";
        defer alloc.free(out_data);
        var out_len: usize = undefined;

        const error_code = c.simpleDecompress(c.elzma_file_format.ELZMA_lzma, &lzma_data[0], in_data_len, @ptrCast([*c][*c]u8, &out_data.ptr), &out_len);
        if (error_code != 0) {
            return error.InvalidReplayFile;
        }
        // Create an array list which we will use to hold all parsed ReplayAction objects
        r.replay_data = std.ArrayList(ReplayAction).init(alloc);

        // Iterate over indexes of the string. If we find a comma,
        // parse a replay action starting from start_entry to i,
        // then set new start_entry value
        var it = std.mem.tokenize(out_data[0..out_len], ",");
        while (it.next()) |item| {
            try r.replay_data.append(try ReplayAction.init(item));
        }
        alloc.free(it.buffer);

        r.online_score_id = try st.readIntLittle(i64);
        return r;
    }

    fn deinit(self: *OsuReplay) void {
        self.alloc.free(self.beatmap_hash);
        self.alloc.free(self.player_name);
        self.alloc.free(self.replay_hash);
        self.alloc.free(self.life_bar_graph);
        self.replay_data.deinit();
    }
};

test "Replay parsing" {
    const fs = std.fs;
    const io = std.io;
    const c_alloc = std.heap.c_allocator;

    const expect = std.testing.expect;

    var file = try fs.File.openRead("resources/cookiezi817.osr");
    const file_len = try file.getEndPos();
    var file_data: []u8 = try c_alloc.alloc(u8, file_len);
    _ = try file.read(file_data);
    file.close();

    var buf_stream = io.SliceInStream.init(file_data);
    const st = &buf_stream.stream;
    var r = try OsuReplay.init(st, c_alloc);

    expect(r.play_mode == PlayMode.Standard);
    expect(r.game_version == 20151228);
    expect(std.mem.eql(u8, r.beatmap_hash, "d7e1002824cb188bf318326aa109469d"));
    expect(std.mem.eql(u8, r.player_name, "Cookiezi"));
    expect(r.count_300s == 1165);
    expect(r.count_100s == 8);
    expect(r.count_50s == 0);
    expect(r.count_gekis == 254);
    expect(r.count_katus == 7);
    expect(r.count_misses == 0);
    expect(r.total_score == 72389038);
    expect(r.max_combo == 1773);
    expect(r.is_fc == false);
    expect(r.replay_data.len == 16160);

    r.deinit();
    c_alloc.free(file_data);
}
