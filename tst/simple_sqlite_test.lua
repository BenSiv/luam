print("Testing sqlite3 module...")
sqlite3 = nil
ok = pcall({function()
    sqlite3 = require({"sqlite3"})
end})

if ok then
    print("Successfully loaded sqlite3 module.")
    if sqlite3.api and sqlite3.api.open then
        print("sqlite3.api.open found.")
        db = nil
        if sqlite3.api then
           print("sqlite3.api found. Module loaded successfully.")
        else
           print("sqlite3.api missing.")
        end
    else
        print("sqlite3.api.open NOT found.")
    end
else
    print("Failed to load sqlite3 module.")
end
