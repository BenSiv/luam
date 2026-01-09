require("lsqlite3")

width = 78
function line(pref, suff)
    pref = pref or ''
    suff = suff or ''
   len = width - 2 - string.len(pref) - string.len(suff)
    print(pref .. string.rep('-', len) .. suff)
end

db, vm = nil
assert_, assert = assert, function (test)
    if (not test) then
        error(db.errmsg(db), 2)
    end
end

line(sqlite3.version())

os.remove('test.db')
db = sqlite3.open('test.db')

line(nil, 'db:exec')
db.exec(db, 'CREATE TABLE t(a, b)')

line(nil, 'prepare')
vm = db.prepare(db, 'insert into t values(?, :bork)')
assert(vm, db.errmsg(db))
assert(vm.bind_parameter_count(vm) == 2)
assert(vm.bind_values(vm, 2, 4) == sqlite3.OK)
assert(vm.step(vm) == sqlite3.DONE)
assert(vm.reset(vm) == sqlite3.OK)
assert(vm:bind_names{ 'pork', bork = 'nono' } == sqlite3.OK)
assert(vm.step(vm) == sqlite3.DONE)
assert(vm.reset(vm) == sqlite3.OK)
assert(vm:bind_names{ bork = 'sisi' } == sqlite3.OK)
assert(vm.step(vm) == sqlite3.DONE)
assert(vm.reset(vm) == sqlite3.OK)
assert(vm:bind_names{ 1 } == sqlite3.OK)
assert(vm.step(vm) == sqlite3.DONE)
assert(vm.finalize(vm) == sqlite3.OK)

line("select * from t", 'db:exec')

assert(db.exec(db, 'select * from t', function (ud, ncols, values, names)
    --table.setn(values, 2)
    print(unpack(values))
    return sqlite3.OK
end) == sqlite3.OK)

line("select * from t", 'db:prepare')

vm = db.prepare(db, 'select * from t')
assert(vm, db.errmsg(db))
print(vm.get_unames(vm))
while (vm.step(vm) == sqlite3.ROW) do
    print(vm.get_uvalues(vm))
end
assert(vm.finalize(vm) == sqlite3.OK)



line('udf', 'scalar')

function do_query(sql)
   r = nil
   vm = db.prepare(db, sql)
    assert(vm, db.errmsg(db))
    print('====================================')
    print(vm.get_unames(vm))
    print('------------------------------------')
    r = vm.step(vm)
    while (r == sqlite3.ROW) do
        print(vm.get_uvalues(vm))
        r = vm.step(vm)
    end
    assert(r == sqlite3.DONE)
    assert(vm.finalize(vm) == sqlite3.OK)
    print('====================================')
end

function udf1_scalar(ctx, v)
   ud = ctx.user_data(ctx)
    ud.r = (ud.r or '') .. tostring(v)
    ctx.result_text(ctx, ud.r)
end

db.create_function(db, 'udf1', 1, udf1_scalar, { })
do_query('select udf1(a) from t')


line('udf', 'aggregate')

function udf2_aggregate(ctx, ...)
   ud = ctx.get_aggregate_data(ctx)
    if (not ud) then
        ud = {}
        ctx.set_aggregate_data(ctx, ud)
    end
    ud.r = (ud.r or 0) + 2
end

function udf2_aggregate_finalize(ctx, v)
   ud = ctx.get_aggregate_data(ctx)
    ctx.result_number(ctx, ud and ud.r or 0)
end

db.create_aggregate(db, 'udf2', 1, udf2_aggregate, udf2_aggregate_finalize, { })
do_query('select udf2(a) from t')

if (true) then
    line(nil, '100 insert exec')
    db.exec(db, 'delete from t')
   t = os.time()
    for i = 1, 100 do
        db.exec(db, 'insert into t values('..i..', '..(i * 2 * -1^i)..')')
    end
    print('elapsed: '..(os.time() - t))
    do_query('select count(*) from t')

    line(nil, '100000 insert exec T')
    db.exec(db, 'delete from t')
   t = os.time()
    db.exec(db, 'begin')
    for i = 1, 100000 do
        db.exec(db, 'insert into t values('..i..', '..(i * 2 * -1^i)..')')
    end
    db.exec(db, 'commit')
    print('elapsed: '..(os.time() - t))
    do_query('select count(*) from t')

    line(nil, '100000 insert prepare/bind T')
    db.exec(db, 'delete from t')
   t = os.time()
   vm = db.prepare(db, 'insert into t values(?, ?)')
    db.exec(db, 'begin')
    for i = 1, 100000 do
        vm.bind_values(vm, i, i * 2 * -1^i)
        vm.step(vm)
        vm.reset(vm)
    end
    vm.finalize(vm)
    db.exec(db, 'commit')
    print('elapsed: '..(os.time() - t))
    do_query('select count(*) from t')

end

line(nil, "db:close")

assert(db.close(db) == sqlite3.OK)

line(sqlite3.version())
