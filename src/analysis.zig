const std = @import("std");

const grammar = @import("grammar.zig");

fn hashUSize(x: usize) u32 {
    const array = []usize{ x };
    return std.mem.hash_slice_u8(@sliceToBytes(array[0..array.len]));
}

fn eqlUSize(lhs: usize, rhs: usize) bool {
    return lhs == rhs;
}

pub const Item = struct {
    production: *const grammar.Production,
    marker: usize,

    pub fn init(production: *const grammar.Production, marker: usize) Item {
        std.debug.assert(marker <= production.symbols.len);
        return Item{
            .production = production,
            .marker = marker,
        };
    }

    const VisitedSet = std.HashMap(usize, bool, hashUSize, eqlUSize);

    const ErrorSet = error {
        OutOfMemory,
    };

    pub fn findClosure(self: *const Item, allocator: *std.mem.Allocator, rule_set: *const grammar.RuleSet) ![]Item {
        var items = std.ArrayList(Item).init(allocator);
        var visited = VisitedSet.init(allocator);
        defer visited.deinit();
        try self.findClosureHelper(rule_set, &items, &visited);
        return items.toOwnedSlice();
    }

    fn findClosureHelper(self: *const Item,
                         rule_set: *const grammar.RuleSet,
                         items: *std.ArrayList(Item),
                         visited: *VisitedSet) ErrorSet!void {
        if (visited.contains(self.production.id)) {
            return;
        }

        try items.append(self.*);
        const old_entry = try visited.put(self.production.id, true);
        std.debug.assert(old_entry == null);

        std.debug.assert(self.marker <= self.production.symbols.len);
        if (self.marker == self.production.symbols.len) {
            return;
        }

        const marked_symbol = self.production.symbols[self.marker];
        const marked_rule = rule_set.get(marked_symbol) catch return;

        for (marked_rule.productions) |marked_production| {
            const item = Item.init(marked_production, 0);
            try item.findClosureHelper(rule_set, items, visited);
        }
    }
};
