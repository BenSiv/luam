-- Timestamp normalization, validation, timezone-independent civil calendar
-- arithmetic (Howard Hinnant's Gregorian algorithm), and ISO-8601 / RFC 3339 helpers.

const dates = {}

function pad_to_length(input, total_length, pad_char)
    if pad_char == nil then
        pad_char = "0"
    end
    while #input < total_length do
        input = input .. pad_char
    end
    return input
end

function is_leap_year(year)
    if type(year) != "number" or math.floor(year) != year then
        return false
    end
    return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)
end

const MONTH_DAYS = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}

function days_in_month(year, month)
    if type(year) != "number" or type(month) != "number" then
        return nil
    end
    if math.floor(year) != year or math.floor(month) != month then
        return nil
    end
    if month < 1 or month > 12 then
        return nil
    end
    if month == 2 and is_leap_year(year) then
        return 29
    end
    return MONTH_DAYS[month]
end

-- Converts a civil `YYYY-MM-DD` string (or timestamp starting with `YYYY-MM-DD`)
-- into integer days since `1970-01-01` using pure integer arithmetic (never
-- affected by host TZ or DST). Returns `nil` if invalid.
function civil_days(ymd)
    if type(ymd) != "string" then
        return nil
    end
    ys, ms, ds = string.match(ymd, "^%s*([%+%-]?%d%d%d%d+)%-(%d%d)%-(%d%d)")
    if ys == nil then
        return nil
    end
    y = tonumber(ys)
    m = tonumber(ms)
    d = tonumber(ds)
    if y == nil or m == nil or d == nil then
        return nil
    end
    max_d = days_in_month(y, m)
    if max_d == nil or d < 1 or d > max_d then
        return nil
    end
    if m <= 2 then
        y = y - 1
    end
    era = math.floor(y / 400)
    yoe = y - (era * 400)
    mp = m + 9
    if m > 2 then
        mp = m - 3
    end
    doy = math.floor((153 * mp + 2) / 5) + d - 1
    doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

-- Inverse of `civil_days`: integer days since `1970-01-01` -> `"YYYY-MM-DD"`.
function ymd_from_days(days)
    if type(days) != "number" then
        return nil
    end
    z = math.floor(days) + 719468
    era = math.floor(z / 146097)
    doe = z - (era * 146097)
    yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    y = yoe + (era * 400)
    doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    mp = math.floor((5 * doy + 2) / 153)
    d = doy - math.floor((153 * mp + 2) / 5) + 1
    m = mp + 3
    if mp >= 10 then
        m = mp - 9
    end
    if m <= 2 then
        y = y + 1
    end
    if y < 0 then
        return string.format("-%04d-%02d-%02d", -y, m, d)
    end
    return string.format("%04d-%02d-%02d", y, m, d)
end

function add_days(ymd, delta_days)
    base = civil_days(ymd)
    delta = tonumber(delta_days)
    if base == nil or delta == nil then
        return nil
    end
    return ymd_from_days(base + math.floor(delta))
end

function diff_days(ymd_a, ymd_b)
    da = civil_days(ymd_a)
    db = civil_days(ymd_b)
    if da == nil or db == nil then
        return nil
    end
    return da - db
end

-- Formats Unix epoch seconds as UTC ISO-8601 `"YYYY-MM-DDTHH:MM:SSZ"`.
function format_iso8601(epoch_sec)
    n = tonumber(epoch_sec)
    if n == nil then
        return nil
    end
    sec_int = math.floor(n)
    days = math.floor(sec_int / 86400)
    rem = sec_int - (days * 86400)
    hh = math.floor(rem / 3600)
    mm = math.floor((rem % 3600) / 60)
    ss = rem % 60
    return string.format("%sT%02d:%02d:%02dZ", ymd_from_days(days), hh, mm, ss)
end

-- Parses ISO-8601 / RFC 3339 (`YYYY-MM-DD[T ]HH:MM:SS[.sss][Z|+HH:MM|-HH:MM]`).
-- Returns `epoch_sec, parts_tbl` or `nil, err_string`.
function parse_iso8601(str)
    if type(str) != "string" then
        return nil, "timestamp must be a string"
    end
    trimmed = string.trim(str)
    ys, ms, ds, hhs, mms, sss, rest = string.match(
        trimmed,
        "^([%+%-]?%d%d%d%d+)%-(%d%d)%-(%d%d)[Tt ](%d%d):(%d%d):(%d%d)(.*)$"
    )
    if ys == nil then
        return nil, "invalid ISO-8601 timestamp format"
    end

    ymd_str = ys .. "-" .. ms .. "-" .. ds
    days = civil_days(ymd_str)
    if days == nil then
        return nil, "invalid calendar date in timestamp"
    end

    hh = tonumber(hhs)
    mm = tonumber(mms)
    ss = tonumber(sss)
    if hh == nil or mm == nil or ss == nil or hh < 0 or hh > 23 or mm < 0 or mm > 59 or ss < 0 or ss > 60 then
        return nil, "invalid time-of-day in timestamp"
    end

    frac_sec = 0.0
    tz_part = rest
    if string.starts_with(tz_part, ".") then
        digits = string.match(tz_part, "^%.(%d+)")
        if digits == nil then
            return nil, "invalid fractional seconds"
        end
        frac_val = tonumber("0." .. digits)
        if frac_val != nil then
            frac_sec = frac_val
        end
        tz_part = string.sub(tz_part, #digits + 2)
    end

    offset_sec = 0
    if tz_part == "" or tz_part == "Z" or tz_part == "z" then
        offset_sec = 0
    else
        sign_ch, off_h_s, off_m_s = string.match(tz_part, "^([%+%-])(%d%d):?(%d%d)$")
        if sign_ch == nil then
            return nil, "invalid timezone offset in timestamp"
        end
        off_h = tonumber(off_h_s)
        off_m = tonumber(off_m_s)
        if off_h == nil or off_m == nil or off_h > 23 or off_m > 59 then
            return nil, "timezone offset out of range"
        end
        offset_sec = off_h * 3600 + off_m * 60
        if sign_ch == "-" then
            offset_sec = -offset_sec
        end
    end

    utc_sec = (days * 86400) + (hh * 3600) + (mm * 60) + ss - offset_sec + frac_sec
    parts = {
        year = tonumber(ys),
        month = tonumber(ms),
        day = tonumber(ds),
        hour = hh,
        min = mm,
        sec = ss,
        frac = frac_sec,
        offset_sec = offset_sec,
    }
    return utc_sec, parts
end

-- Legacy helpers preserved 100% backward-compatibly:

function normalize_datetime(datetime_str)
    if datetime_str == nil or datetime_str == "" then
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
        if n_year == nil or n_month == nil then
            return nil
        end
        n_day, n_hour, n_min, n_sec = "01", "00", "00", "00"
    elseif str_len == 10 then
        n_year, n_month, n_day = string.match(datetime_str, "(%d%d%d%d)-(%d%d)-(%d%d)")
        if n_year == nil or n_month == nil or n_day == nil then
            return nil
        end
        n_hour, n_min, n_sec = "00", "00", "00"
    elseif str_len == 16 then
        n_year, n_month, n_day, n_hour, n_min = string.match(datetime_str, "(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d)")
        if n_year == nil or n_month == nil or n_day == nil or n_hour == nil or n_min == nil then
            return nil
        end
        n_sec = "00"
    elseif str_len == 19 then
        n_year, n_month, n_day, n_hour, n_min, n_sec = string.match(datetime_str, "(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d):(%d%d)")
        if n_year == nil or n_month == nil or n_day == nil or n_hour == nil or n_min == nil or n_sec == nil then
            return nil
        end
    else
        return nil
    end

    n_year = pad_to_length(n_year, 4, "0")
    n_month = pad_to_length(n_month, 2, "0")
    n_day = pad_to_length(n_day, 2, "0")
    n_hour = pad_to_length(n_hour, 2, "0")
    n_min = pad_to_length(n_min, 2, "0")
    n_sec = pad_to_length(n_sec, 2, "0")

    return n_year .. "-" .. n_month .. "-" .. n_day .. " " .. n_hour .. ":" .. n_min .. ":" .. n_sec
end

function is_valid_timestamp(timestamp)
    if timestamp == nil or type(timestamp) != "string" or #timestamp != 19 then
        return false
    end

    if string.sub(timestamp, 5, 5) != "-" or string.sub(timestamp, 8, 8) != "-" or
       string.sub(timestamp, 11, 11) != " " or string.sub(timestamp, 14, 14) != ":" or
       string.sub(timestamp, 17, 17) != ":" then
        return false
    end

    ts_year = tonumber(string.sub(timestamp, 1, 4))
    ts_month = tonumber(string.sub(timestamp, 6, 7))
    ts_day = tonumber(string.sub(timestamp, 9, 10))
    ts_hour = tonumber(string.sub(timestamp, 12, 13))
    ts_minute = tonumber(string.sub(timestamp, 15, 16))
    ts_second = tonumber(string.sub(timestamp, 18, 19))

    if ts_year == nil or ts_month == nil or ts_day == nil or ts_hour == nil or ts_minute == nil or ts_second == nil then
        return false
    end

    max_days = days_in_month(ts_year, ts_month)
    if max_days == nil then
        return false
    end

    return ts_day >= 1 and ts_day <= max_days and
           ts_hour >= 0 and ts_hour <= 23 and
           ts_minute >= 0 and ts_minute <= 59 and
           ts_second >= 0 and ts_second <= 59
end

function convert_date_format(input_date)
    day, month, year = string.match(input_date, "(%d+).(%d+).(%d+)")
    return year .. "-" .. month .. "-" .. day
end

function date_range(first_date, last_date, unit, interval)
    full_date_range = {}
    current_date = first_date
    table.insert(full_date_range, current_date)
    while current_date != last_date do
        year, month, day = string.match(current_date, "(%d+)-(%d+)-(%d+)")
        if unit == "day" then
            current_date = add_days(current_date, interval)
        elseif unit == "month" then
            current_date = os.date("%Y-%m-%d", os.time({year = tonumber(year), month = tonumber(month) + interval, day = tonumber(day)}))
        elseif unit == "year" then
            current_date = os.date("%Y-%m-%d", os.time({year = tonumber(year) + interval, month = tonumber(month), day = tonumber(day)}))
        else
            error("Unknown time unit: " .. tostring(unit))
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
    _, _, day = disect_date(input_date)
    return day
end

function get_month(input_date)
    _, month, _ = disect_date(input_date)
    return month
end

function get_year(input_date)
    year, _, _ = disect_date(input_date)
    return year
end

dates.is_leap_year = is_leap_year
dates.days_in_month = days_in_month
dates.civil_days = civil_days
dates.ymd_from_days = ymd_from_days
dates.add_days = add_days
dates.diff_days = diff_days
dates.format_iso8601 = format_iso8601
dates.parse_iso8601 = parse_iso8601

dates.normalize_datetime = normalize_datetime
dates.is_valid_timestamp = is_valid_timestamp
dates.convert_date_format = convert_date_format
dates.date_range = date_range
dates.disect_date = disect_date
dates.disect_datetime = disect_datetime
dates.get_day = get_day
dates.get_month = get_month
dates.get_year = get_year

return dates
