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
    const prods = try rule_set.get("E");
    std.debug.assert(prods.len == 5);
    for (prods) |prod| {
        std.debug.warn("{} =", prod.id);
        for (prod.symbols) |symbol| {
            std.debug.warn(" {}", symbol);
        }
        std.debug.warn("\n");
    }
    std.debug.assert(std.mem.eql_slice_u8(rule_set.start_symbol, "S"));
    const start_prods = try rule_set.get(rule_set.start_symbol);
    std.debug.assert(start_prods.len == 1);

    const item = analysis.Item.init(start_prods[0].id, 0);
    const closure = try item.findClosure(std.debug.global_allocator, rule_set);
    defer std.debug.global_allocator.free(closure);
    for (closure) |closure_item| {
        const prod = rule_set.prod_list.at(closure_item.prod_id);
        std.debug.warn("{}:", prod.name);
        for (prod.symbols) |symbol, i| {
            std.debug.warn(" ");
            if (i == closure_item.marker) {
                std.debug.warn("*");
            }
            std.debug.warn("{}", symbol);
        }
        std.debug.warn("\n");
    }
}
