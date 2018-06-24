const std = @import("std");

const analysis = @import("analysis.zig");
const grammar = @import("grammar.zig");
const parse = @import("parse.zig");

test "parse input" {
    const input =
    \\ S = E;
    \\ E = E "*" B | E "+" B | B | "0" | "1";
    \\
    ;
    var parser = parse.Parser.init(std.debug.global_allocator, input);
    const rule_set = try parser.parse();
    const rule = try rule_set.get("E");
    std.debug.assert(rule.productions.len == 5);
    for (rule.productions) |prod| {
        std.debug.warn("{} =", prod.id);
        for (prod.symbols) |symbol| {
            std.debug.warn(" {}", symbol);
        }
        std.debug.warn("\n");
    }
    std.debug.assert(std.mem.eql_slice_u8(rule_set.start_symbol, "S"));
    const start_rule = try rule_set.get(rule_set.start_symbol);
    std.debug.assert(start_rule.productions.len == 1);

    const item = analysis.Item.init(start_rule.productions[0], 0);
    const closure = try item.findClosure(std.debug.global_allocator, rule_set);
}
