laws = require("laws")

print("Testing laws library...")

-- 1. Deterministic PRNG repeatability & seed divergence
r1 = laws.rng(42)
r2 = laws.rng(42)
r3 = laws.rng(43)
gen_int = laws.int(-1000, 1000)
same_all = true
diff_any = false
for i = 1, 25 do
    v1 = gen_int.generate(r1, 50).value
    v2 = gen_int.generate(r2, 50).value
    v3 = gen_int.generate(r3, 50).value
    if v1 != v2 then same_all = false end
    if v1 != v3 then diff_any = true end
end
assert(same_all == true, "same seed must produce identical sequence")
assert(diff_any == true, "different seeds must diverge")

-- 2. True universal & algebraic laws pass cleanly
function prop_addition_commutative(p)
    return (p[1] + p[2]) == (p[2] + p[1])
end

function op_abs(x)
    return math.abs(x)
end

function op_negate(x)
    return -x
end

function op_concat(a, b)
    return a .. b
end

function op_add(x, y)
    return x + y
end

function op_strlen(s)
    return string.len(s)
end

function sort_once(xs)
    c = {}
    for i, v in ipairs(xs) do c[i] = v end
    table.sort(c)
    return c
end

function sort_twice(xs)
    c = {}
    for i, v in ipairs(xs) do c[i] = v end
    table.sort(c)
    table.sort(c)
    return c
end

function le_num(a, b)
    return a <= b
end

function op_double(x)
    return x * 2
end

laws.forall("addition is commutative", laws.tuple(laws.int(-500, 500), laws.int(-500, 500)), prop_addition_commutative)
laws.idempotent("math.abs is idempotent", laws.int(-1000, 1000), op_abs)
laws.involution("negation is an involution", laws.int(-1000, 1000), op_negate)
laws.homomorphism(
    "string.len is a monoid homomorphism from (.. , '') to (+, 0)",
    laws.text({max_len = 20}),
    laws.text({max_len = 20}),
    op_concat,
    op_add,
    op_strlen
)
laws.commutative_diagram(
    "sorting twice equals sorting once",
    laws.list(laws.int(-50, 50), {max_len = 15}),
    sort_once,
    sort_twice
)
laws.monotone(
    "x * 2 is monotone non-decreasing",
    laws.int(-200, 200),
    laws.int(-200, 200),
    le_num,
    le_num,
    op_double
)

-- 3. Counterexample shrinking finds the exact minimal boundary
function prop_below_48(n)
    return n < 48, "exceeded 47"
end

ok_int, fail_int = laws.check("bounded below 48", laws.int(0, 10000), prop_below_48, {trials = 200, max_size = 10000, seed = 20261117})
assert(ok_int == false, "expected integer law to fail")
assert(fail_int.shrunk == 48, "expected integer shrinker to find exact boundary 48, got " .. tostring(fail_int.shrunk))

function prop_no_negatives(xs)
    neg_count = 0
    for _, v in ipairs(xs) do
        if v < 0 then neg_count = neg_count + 1 end
    end
    return neg_count == 0, "contains a negative element"
end

ok_list, fail_list = laws.check("sum of list stays below 10 unless two positives exist", laws.list(laws.int(-20, 20), {max_len = 20}), prop_no_negatives, {trials = 100, seed = 7})
assert(ok_list == false, "expected list law to fail")
assert(#fail_list.shrunk == 1 and fail_list.shrunk[1] == -1,
    "expected list shrinker to isolate {-1}, got " .. laws.format(fail_list.shrunk))

function prop_record_a_below_10(r)
    return r.a < 10, "a >= 10"
end

ok_rec, fail_rec = laws.check("record shrinking", laws.record({
    a = laws.int(0, 100),
    b = laws.text({min_len = 1, max_len = 12, alphabet = "xyz"}),
}), prop_record_a_below_10, {trials = 100, seed = 99})
assert(ok_rec == false, "expected record law to fail")
assert(fail_rec.shrunk.a == 10 and fail_rec.shrunk.b == "x",
    "expected record shrinker to minimize {a = 10, b = \"x\"}, got " .. laws.format(fail_rec.shrunk))

-- 4. Stateful state-machine verification & trace shrinking
function bucket_init()
    return {a = 50, b = 50}, {total = 100}
end

function always_applicable(_)
    return true
end

function bucket_transfer_args(_)
    return laws.int(0, 20)
end

function bucket_move_a_to_b(sut, amt)
    actual = math.min(sut.a, amt)
    sut.a = sut.a - actual
    sut.b = sut.b + actual
end

function bucket_move_b_to_a(sut, amt)
    actual = math.min(sut.b, amt)
    sut.b = sut.b - actual
    sut.a = sut.a + actual
end

function bucket_check_conservation(sut, model)
    if sut.a < 0 or sut.b < 0 then
        return false, "negative bucket"
    end
    if (sut.a + sut.b) != model.total then
        return false, "total drifted"
    end
    return true
end

laws.state_machine({
    name = "conserved_two_bucket_transfer",
    trials = 30,
    max_steps = 20,
    seed = 1234,
    init = bucket_init,
    commands = {
        {
            name = "move_a_to_b",
            applicable = always_applicable,
            args = bucket_transfer_args,
            run = bucket_move_a_to_b,
        },
        {
            name = "move_b_to_a",
            applicable = always_applicable,
            args = bucket_transfer_args,
            run = bucket_move_b_to_a,
        },
    },
    invariants = {
        {
            name = "conservation_and_non_negativity",
            check = bucket_check_conservation,
        },
    },
})

-- Buggy state machine (idempotent archive bug: archiving an already-archived
-- item decrements active_count a second time!) must be caught AND shrunk to
-- the minimal 3-step trace: create -> archive -> archive.
teardown_calls = 0

function buggy_pool_init()
    return {items = {}, count = 0, next_id = 1}, {n = 0}
end

function buggy_pool_teardown(_)
    teardown_calls = teardown_calls + 1
end

function buggy_create_args(_)
    return laws.text({min_len = 1, max_len = 6, alphabet = "abc"})
end

function buggy_create_run(sut, title)
    id = sut.next_id
    sut.next_id = id + 1
    sut.items[id] = {title = title, archived = false}
    sut.count = sut.count + 1
    return id
end

function buggy_create_next_model(m, _, _)
    m.n = m.n + 1
end

function buggy_has_items(m)
    return m.n >= 1
end

function buggy_item_id_args(m)
    return laws.int(1, m.n)
end

function buggy_valid_item_id(m, id)
    return id >= 1 and id <= m.n
end

function buggy_noop_run(_, _)
end

function buggy_archive_run(sut, id)
    sut.items[id].archived = true
    -- BUG: decrements count unconditionally even when already archived!
    sut.count = sut.count - 1
end

function buggy_check_active_count(sut, _)
    real_active = 0
    for _, item in pairs(sut.items) do
        if not item.archived then
            real_active = real_active + 1
        end
    end
    if sut.count != real_active then
        return false, string.format("count=%d vs real_active=%d", sut.count, real_active)
    end
    return true
end

ok_sm, fail_sm = laws.check_state_machine({
    name = "buggy_double_archive_pool",
    trials = 50,
    max_steps = 25,
    seed = 20261117,
    init = buggy_pool_init,
    teardown = buggy_pool_teardown,
    commands = {
        {
            name = "create",
            weight = 3,
            args = buggy_create_args,
            run = buggy_create_run,
            next_model = buggy_create_next_model,
        },
        {
            name = "noop_touch",
            weight = 3,
            applicable = buggy_has_items,
            args = buggy_item_id_args,
            valid_args = buggy_valid_item_id,
            run = buggy_noop_run,
        },
        {
            name = "archive",
            weight = 2,
            applicable = buggy_has_items,
            args = buggy_item_id_args,
            valid_args = buggy_valid_item_id,
            run = buggy_archive_run,
        },
    },
    invariants = {
        {
            name = "count_matches_unarchived_items",
            check = buggy_check_active_count,
        },
    },
})

assert(ok_sm == false, "expected buggy state machine to fail")
assert(fail_sm.shrunk_length == 3,
    "expected trace shrinker to isolate minimal 3-step reproducer (create -> archive -> archive), got " .. tostring(fail_sm.shrunk_length))
assert(fail_sm.steps[1].cmd.name == "create" and fail_sm.steps[2].cmd.name == "archive" and fail_sm.steps[3].cmd.name == "archive",
    "unexpected shrunk command sequence")
assert(teardown_calls > 0, "teardown must run on every trace execution")

print("laws library tests passed")
