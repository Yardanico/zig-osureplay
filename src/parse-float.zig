const std = @import("std");

const c = @cImport({
    @cInclude("stdlib.h");
});

const powtens = [_]f64{
    1e0,  1e1,  1e2,  1e3,  1e4,  1e5,  1e6,  1e7,  1e8,  1e9,
    1e10, 1e11, 1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19,
    1e20, 1e21, 1e22,
};

fn is_digit(b: u8) bool {
    return (b >= '0' and b <= '9');
}

fn is_ident_char(b: u8) bool {
    return (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or (b >= '0' and b <= '9') or b == '_';
}

// https://github.com/nim-lang/Nim/blob/c94647aecad6ed7fd12152800437a6cda11e06e6/lib/system/strmantle.nim#L137
// Nim implementation of float parsing. The fast path is faster than
// fmt.parseFloat by about 3 times on my PC. The slow path uses c_strtod function from libc
pub fn parse_float(s: []const u8) !f64 {
    var num: f64 = 0.0;
    var i: usize = 0;
    var start: usize = 0;
    var sign: f64 = 1.0;
    var kdigits: i64 = 0;
    var fdigits: i64 = 0;
    var exponent: i64 = 0;
    var integer: u64 = 0;
    var frac_exponent: i64 = 0;
    var exp_sign: i64 = 1;
    var first_digit: i64 = -1;
    var has_sign: bool = false;

    if (i < s.len and (s[i] == '+' or s[i] == '-')) {
        has_sign = true;
        if (s[i] == '-') {
            sign = -1.0;
        }
        i += 1;
    }

    if (i + 2 < s.len and (s[i] == 'N' or s[i] == 'n')) {
        if (s[i + 1] == 'A' or s[i + 1] == 'a') {
            if (s[i + 2] == 'N' or s[i + 2] == 'n') {
                if (i + 3 >= s.len or !is_ident_char(s[i + 3])) {
                    return std.math.nan(f64);
                }
            }
        }
        return error.InvalidFloat;
    }

    if (i + 2 < s.len and (s[i] == 'I' or s[i] == 'i')) {
        if (s[i + 1] == 'N' or s[i + 1] == 'n') {
            if (s[i + 2] == 'F' or s[i + 2] == 'f') {
                if (i + 3 >= s.len or !is_ident_char(s[i + 3])) {
                    return std.math.inf(f64) * sign;
                }
            }
        }
        return error.InvalidFloat;
    }

    if (i < s.len and is_digit(s[i])) {
        first_digit = s[i] - '0';
    }
    // Integer part
    while (i < s.len and is_digit(s[i])) {
        kdigits += 1;
        integer = integer * 10 + @intCast(u64, s[i] - '0');
        i += 1;
        while (i < s.len and s[i] == '_') {
            i += 1;
        }
    }
    if (i < s.len and s[i] == '.') {
        i += 1;

        if (kdigits <= 0) {
            while (i < s.len and s[i] == '0') {
                frac_exponent += 1;
                i += 1;
                while (i < s.len and s[i] == '_') {
                    i += 1;
                }
            }
        }

        if (first_digit == -1 and i < s.len and is_digit(s[i])) {
            first_digit = (s[i] - '0');
        }
        while (i < s.len and is_digit(s[i])) {
            fdigits += 1;
            frac_exponent += 1;
            integer = integer * 10 + (s[i] - '0');
            i += 1;

            while (i < s.len and s[i] == '_') {
                i += 1;
            }
        }
    }

    if ((kdigits + fdigits) <= 0 and (i == start or (i == start + 1 and has_sign))) {
        return error.InvalidFloat;
    }

    if ((i + 1) < s.len and (s[i] == 'e' or s[i] == 'E')) {
        i += 1;
        if (s[i] == '+' or s[i] == '-') {
            if (s[i] == '-') {
                exp_sign = -1;
            }

            i += 1;
        }
        if (!is_digit(s[i])) {
            return error.InvalidFloat;
        }
        while (i < s.len and is_digit(s[i])) {
            exponent = exponent * 10 + @intCast(i64, s[i] - '0');
            i += 1;
        }
    }
    var real_exponent = exp_sign * exponent - frac_exponent;
    const exp_negative = real_exponent < 0;
    var abs_exponent = @intCast(usize, try std.math.absInt(real_exponent));
    if (abs_exponent > 999) {
        if (exp_negative) {
            num = 0.0 * sign;
        } else {
            num = std.math.inf_f64 * sign;
        }
        return num;
    }

    const digits = kdigits + fdigits;
    if (digits <= 15 or (digits <= 16 and first_digit <= 8)) {
        if (abs_exponent <= 22) {
            if (exp_negative) {
                num = sign * @intToFloat(f64, integer) / powtens[abs_exponent];
            } else {
                num = sign * @intToFloat(f64, integer) * powtens[abs_exponent];
            }
            return num;
        }

        const slop = @intCast(usize, 15 - kdigits - fdigits);
        if (abs_exponent <= 22 + slop and !exp_negative) {
            num = sign * @intToFloat(f64, integer) * powtens[slop] * powtens[abs_exponent - slop];
            return num;
        }
    }
    // Slow path if the fast one didn't work
    var t: [500]u8 = [_]u8{0} ** 500;
    var ti: usize = 0;
    const maxlen = t.len - "e+000".len;
    i = 0;
    if (i < s.len and s[i] == '.') {
        i += 1;
    }
    while (i < s.len and (is_digit(s[i]) or s[i] == '+' or s[i] == '-')) {
        if (ti < maxlen) {
            t[ti] = s[i];
            ti += 1;
        }
        i += 1;
        while (i < s.len and (s[i] == '.' or s[i] == '_')) : (i += 1) {}
    }

    t[ti] = 'E';
    ti += 1;
    if (exp_negative) {
        t[ti] = '-';
    } else {
        t[ti] = '+';
    }
    ti += 4;

    t[ti - 1] = @intCast(u8, ('0' + @mod(abs_exponent, 10)));
    abs_exponent = @divTrunc(abs_exponent, 10);
    t[ti - 2] = @intCast(u8, ('0' + @mod(abs_exponent, 10)));
    abs_exponent = @divTrunc(abs_exponent, 10);
    t[ti - 3] = @intCast(u8, ('0' + @mod(abs_exponent, 10)));
    abs_exponent = @divTrunc(abs_exponent, 10);

    var temp: []u8 = undefined;
    num = c.strtod(&t, @ptrCast([*c][*c]u8, &temp.ptr));

    return num;
}
