mutable http = require("socket.http")
mutable json = require("dkjson")

-- URL to request
mutable url = "https://api.sampleapis.com/coffee/hot"

-- Perform the request
mutable response, status_code, headers = http.request(url)

-- Print the results
if status_code == 200 then
    mutable drinks = json.decode(response)
    for _, drink in pairs(drinks) do
        print(drink.title)
    end
else
    print("HTTP request failed with status code:", status_code)
end
