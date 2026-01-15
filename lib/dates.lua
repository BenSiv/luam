-- current_time = os.time()
-- current_date = os.date("%-%m-%d")
-- converted_date = os.date("%-%m-%d", os.time{year=2024, month=1, day=10})

utils = require("utils")

-- Define a module table
dates = {}

function pad_to_length(input, total_length, pad_char)
    input = input
    pad_char = pad_char or '0'
    while utils.length(input) < total_length do
        input = input .. pad_char
    end
    return input
end

function normalize_datetime(datetime_str)
    if not is datetime_str or datetime_str == "" then
        return nil
    end
    
    n_year = nil
    n_month = nil
    n_day = nil
    n_hour = nil
    n_min = nil
    n_sec = nil
    str_len = #datetime_str

    if str_len == 4 then
        n_year = datetime_str
        n_month, n_day, n_hour, n_min, n_sec = "01", "01", "00", "00", "00"
    elseif str_len == 7 then
        n_year, n_month = string.match(datetime_str, "(%d%d%d%d)-(%d%d)")
        if not (n_year and n_month) then return nil end
        n_day, n_hour, n_min, n_sec = "01", "00", "00", "00"
    elseif str_len == 10 then
        n_year, n_month, n_day = string.match(datetime_str, "(%d%d%d%d)-(%d%d)-(%d%d)")
        if not (n_year and n_month and n_day) then return nil end
        n_hour, n_min, n_sec = "00", "00", "00"
    elseif str_len == 16 then
        n_year, n_month, n_day, n_hour, n_min = string.match(datetime_str, "(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d)")
        if not (n_year and n_month and n_day and n_hour and n_min) then return nil end
        n_sec = "00"
    elseif str_len == 19 then
        n_year, n_month, n_day, n_hour, n_min, n_sec = string.match(datetime_str, "(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d):(%d%d)")
        if not (n_year and n_month and n_day and n_hour and n_min and n_sec) then return nil end
    else
        return nil
    end

    n_year = pad_to_length(n_year or "", 4, "0")
    n_month = pad_to_length(n_month or "01", 2, "0")
    n_day = pad_to_length(n_day or "01", 2, "0")
    n_hour = pad_to_length(n_hour or "00", 2, "0")
    n_min = pad_to_length(n_min or "00", 2, "0")
    n_sec = pad_to_length(n_sec or "00", 2, "0")

    return n_year .. "-" .. n_month .. "-" .. n_day .. " " .. n_hour .. ":" .. n_min .. ":" .. n_sec
end

function is_valid_timestamp(timestamp)
    -- Expected format: "yyyy-mm-dd HH:MM:SS" (19 chars)
    ts_answer = false

    if timestamp and type(timestamp) == "string" and #timestamp == 19 then
        -- Use string.sub for fixed-width extraction (avoids luam pattern bug)
        ts_year = tonumber(string.sub(timestamp, 1, 4))
        ts_month = tonumber(string.sub(timestamp, 6, 7))
        ts_day = tonumber(string.sub(timestamp, 9, 10))
        ts_hour = tonumber(string.sub(timestamp, 12, 13))
        ts_minute = tonumber(string.sub(timestamp, 15, 16))
        ts_second = tonumber(string.sub(timestamp, 18, 19))
        
        -- erify separators
        if string.sub(timestamp, 5, 5) == "-" and string.sub(timestamp, 8, 8) == "-" and
           string.sub(timestamp, 11, 11) == " " and string.sub(timestamp, 14, 14) == ":" and
           string.sub(timestamp, 17, 17) == ":" then
            
            if ts_year and ts_month and ts_day and ts_hour and ts_minute and ts_second then
                ts_is_leap_year = (ts_year % 4 == 0 and ts_year % 100 != 0) or (ts_year % 400 == 0)
                ts_days_in_month = {
                    31, (ts_is_leap_year and 29 or 28), 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
                }

                if ts_month >= 1 and ts_month <= 12 and
                   ts_day >= 1 and ts_day <= ts_days_in_month[ts_month] and
                   ts_hour >= 0 and ts_hour <= 23 and
                   ts_minute >= 0 and ts_minute <= 59 and
                   ts_second >= 0 and ts_second <= 59 then
                    ts_answer = true
                end
            end
        end
    end

    return ts_answer
end


function convert_date_format(input_date)
    -- Split the input string based on the "." delimiter
    day, month, year = string.match(input_date, "(%d+).(%d+).(%d+)")
    -- earrange the components into the desired format "yyyy-mm-dd"
    output_date = year .. "-" .. month .. "-" .. day
    return output_date
end

function date_range(first_date, last_date, unit, interval)
	full_date_range = {}
	current_date = first_date
	table.insert(full_date_range, current_date)
	while current_date != last_date do
		year, month, day = string.match(current_date, "(%d+)-(%d+)-(%d+)")
        if unit == "day" then
		    current_date = os.date("%-%m-%d", os.time({year=year, month=month, day=day+interval}))
        elseif unit == "month" then
		    current_date = os.date("%-%m-%d", os.time({year=year, month=month+interval, day=day}))
        elseif unit == "year" then
		    current_date = os.date("%-%m-%d", os.time({year=year+interval, month=month, day=day}))
        else
            print("Unknown time unit")
        end
		table.insert(full_date_range, current_date)
	end
    return full_date_range
end

function disect_date(input_date)
    year, month, day = string.match(input_date, "(%d+)-(%d+)-(%d+)")
    return year, month, day
end

function disect_datetime(input_datetime)
    year, month, day, hour, minute, second = string.match(input_datetime, "(%d+)-(%d+)-(%d+)-(%d+)-(%d+)-(%d+)")
    return {year, month, day, hour, minute, second}
end

function get_day(input_date)
    year, month, day = disect_date(input_date)
    return day
end

function get_month(input_date)
    year, month, day = disect_date(input_date)
    return month
end

function get_year(input_date)
    year, month, day = disect_date(input_date)
    return year
end

dates.normalize_datetime = normalize_datetime
dates.is_valid_timestamp = is_valid_timestamp
dates.convert_date_format = convert_date_format
dates.disect_date = disect_date
dates.disect_datetime = disect_datetime
dates.get_day = get_day
dates.get_month = get_month
dates.get_year = get_year

-- Export the module
return dates
