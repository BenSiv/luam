-- database_adapter's MariaDB connections refuse to open unless the
-- session's sql_mode really contains NO_BACKSLASH_ESCAPES (see
-- get_mariadb_connection). This checks the flag parsing that decision
-- rests on; it needs no server.
database_adapter = require("database_adapter")

print("Testing sql_mode NO_BACKSLASH_ESCAPES detection...")

check = database_adapter.sql_mode_disables_backslash_escapes

assert(check("STRICT_TRANS_TABLES,NO_BACKSLASH_ESCAPES") == true, "flag at the end")
assert(check("NO_BACKSLASH_ESCAPES,STRICT_TRANS_TABLES") == true, "flag at the start")
assert(check("NO_BACKSLASH_ESCAPES") == true, "flag alone")
assert(check("strict_trans_tables,no_backslash_escapes") == true, "lowercase")
assert(check("STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION") == false, "flag missing")
assert(check("") == false, "empty mode")
assert(check(nil) == false, "mode could not be read")
assert(check("NO_BACKSLASH_ESCAPES_X") == false, "a longer flag name is not the flag")
assert(check("X_NO_BACKSLASH_ESCAPES") == false, "a flag that merely ends with the name is not the flag")

print("sql_mode detection tests passed")
