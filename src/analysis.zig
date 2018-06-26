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
    prod_id: usize,
    marker: usize,

    pub fn init(prod_id: usize, marker: usize) Item {
        return Item{
            .prod_id = prod_id,
            .marker = marker,
        };
    }

    const VisitedSet = std.HashMap(usize, void, hashUSize, eqlUSize);

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
        if (visited.contains(self.prod_id)) {
            return;
        }

        try items.append(self.*);

        const prod = rule_set.prod_list.at(self.prod_id);
        std.debug.assert(self.prod_id == prod.id);
        const old_entry = try visited.put(self.prod_id, {});
        std.debug.assert(old_entry == null);

        std.debug.assert(self.marker <= prod.symbols.len);
        if (self.marker == prod.symbols.len) {
            return;
        }

        const marked_symbol = prod.symbols[self.marker];
        const marked_prods = rule_set.get(marked_symbol) catch return;

        for (marked_prods) |marked_prod| {
            const item = Item.init(marked_prod.id, 0);
            try item.findClosureHelper(rule_set, items, visited);
        }
    }
};
