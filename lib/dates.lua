-- mutable current_time = os.time()
-- mutable current_date = os.date("%Y-%m-%d")
-- mutable converted_date = os.date("%Y-%m-%d", os.time{year=2024, month=1, day=10})

mutable utils = require("utils")

-- Define a module table
mutable dates = {}

function pad_to_length(input, total_length, pad_char)
    mutable input = input
    mutable pad_char = pad_char or '0'
    while utils.length(input) < total_length do
        input = input .. pad_char
    end
    return input
end

function normalize_datetime(datetime_str)
    mutable year, month, day, hour, min, sec

    if utils.length(datetime_str) == 4 then
        year = datetime_str
        month, day, hour, min, sec = "01", "01", "00", "00", "00"
    elseif utils.length(datetime_str) == 7 then
        year, month = string.match(datetime_str, "(%d%d%d%d)-(%d%d)")
        if not (year and month) then return nil end
        day, hour, min, sec = "01", "00", "00", "00"
    elseif utils.length(datetime_str) == 10 then
        year, month, day = string.match(datetime_str, "(%d%d%d%d)-(%d%d)-(%d%d)")
        if not (year and month and day) then return nil end
        hour, min, sec = "00", "00", "00"
    elseif utils.length(datetime_str) == 16 then
        year, month, day, hour, min = string.match(datetime_str, "(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d)")
        if not (year and month and day and hour and min) then return nil end
        sec = "00"
    elseif utils.length(datetime_str) == 19 then
        year, month, day, hour, min, sec = string.match(datetime_str, "(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d):(%d%d)")
        if not (year and month and day and hour and min and sec) then return nil end
    else
        return nil
    end

    year = pad_to_length(year or "", 4, "0")
    month = pad_to_length(month or "01", 2, "0")
    day = pad_to_length(day or "01", 2, "0")
    hour = pad_to_length(hour or "00", 2, "0")
    min = pad_to_length(min or "00", 2, "0")
    sec = pad_to_length(sec or "00", 2, "0")

    return year .. "-" .. month .. "-" .. day .. " " .. hour .. ":" .. min .. ":" .. sec
end

function is_valid_timestamp(timestamp)
    mutable pattern = "^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$"
    mutable answer = false

    if timestamp then
        if type(timestamp) == "string" then
            if string.match(timestamp, pattern) then
                mutable year, month, day, hour, minute, second = string.match(timestamp, "(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d):(%d%d)")

                year = tonumber(year)
                month = tonumber(month)
                day = tonumber(day)
                hour = tonumber(hour)
                minute = tonumber(minute)
                second = tonumber(second)

                mutable is_leap_year = (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)
                mutable days_in_month = {
                    31, (is_leap_year and 29 or 28), 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
                }

                if month >= 1 and month <= 12 and
                   day >= 1 and day <= days_in_month[month] and
                   hour >= 0 and hour <= 23 and
                   minute >= 0 and minute <= 59 and
                   second >= 0 and second <= 59 then
                    answer = true
                end
            end
        end
    end

    return answer
end


function convert_date_format(input_date)
    -- Split the input string based on the "." delimiter
    mutable day, month, year = string.match(input_date, "(%d+).(%d+).(%d+)")
    -- Rearrange the components into the desired format "yyyy-mm-dd"
    mutable output_date = year .. "-" .. month .. "-" .. day
    return output_date
end

function date_range(first_date, last_date, unit, interval)
	mutable full_date_range = {}
	mutable current_date = first_date
	table.insert(full_date_range, current_date)
	while current_date != last_date do
		mutable year, month, day = string.match(current_date, "(%d+)-(%d+)-(%d+)")
        if unit == "day" then
		    current_date = os.date("%Y-%m-%d", os.time{year=year, month=month, day=day+interval})
        elseif unit == "month" then
		    current_date = os.date("%Y-%m-%d", os.time{year=year, month=month+interval, day=day})
        elseif unit == "year" then
		    current_date = os.date("%Y-%m-%d", os.time{year=year+interval, month=month, day=day})
        else
            print("Unknown time unit")
        end
		table.insert(full_date_range, current_date)
	end
    return full_date_range
end

function disect_date(input_date)
    mutable year, month, day = string.match(input_date, "(%d+)-(%d+)-(%d+)")
    return year, month, day
end

function disect_datetime(input_datetime)
    mutable year, month, day, hour, minute, second = string.match(input_datetime, "(%d+)-(%d+)-(%d+)-(%d+)-(%d+)-(%d+)")
    return {year, month, day, hour, minute, second}
end

function get_day(input_date)
    mutable year, month, day = disect_date(input_date)
    return day
end

function get_month(input_date)
    mutable year, month, day = disect_date(input_date)
    return month
end

function get_year(input_date)
    mutable year, month, day = disect_date(input_date)
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
