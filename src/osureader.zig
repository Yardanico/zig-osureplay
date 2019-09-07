const std = @import("std");
const fs = std.fs;
const io = std.io;
const warn = std.debug.warn;
const c_alloc = std.heap.c_allocator;

const osureplay = @import("osureplay.zig");

pub fn main() !void {
    const args = try std.process.argsAlloc(c_alloc);
    defer std.process.argsFree(c_alloc, args);
    var fname: []const u8 = "";
    for (args) |arg, i| {
        if (i == 1) {
            fname = arg;
            break;
        }
    }
    warn("Parsing {}\n", fname);
    var file = try fs.File.openRead(fname);
    const file_len = try file.getEndPos();
    var file_data: []u8 = try c_alloc.alloc(u8, file_len);
    defer c_alloc.free(file_data);
    _ = try file.read(file_data);
    file.close();

    var buf_stream = io.SliceInStream.init(file_data);
    const st = &buf_stream.stream;
    var r = try osureplay.OsuReplay.init(st, c_alloc);
    defer r.deinit();
    warn("Played by {} at {}\n", r.player_name, "todo: datetime");
    warn("Game mode - {}\n", r.play_mode);
    warn("Game version - {}\n", r.game_version);
    warn("Beatmap hash - {}, replay hash - {}\n", r.beatmap_hash, r.replay_hash);
    warn("Number of 300's - {}, 100's - {}, 50's - {}\n", r.count_300s, r.count_100s, r.count_50s);
    warn("Number of gekis - {}, katus - {}\n", r.count_gekis, r.count_katus);
    warn("Number of misses - {}\n", r.count_misses);
    warn("Total score - {}\n", r.total_score);
    warn("Max combo - {}\n", r.max_combo);
    warn("Is FC? - {}\n", r.is_fc);
    warn("Mods used - {}\n", r.mod_list);
    warn("Number of replay data events - {}\n", r.replay_data.len);
}
