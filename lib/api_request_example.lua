http = require("socket.http")
json = require("dkjson")

-- UL to request
url = "https://api.sampleapis.com/coffee/hot"

-- Perform the request
response, status_code, headers = http.request(url)

-- Print the results
if status_code == 200 then
    drinks = json.decode(response)
    for _, drink in pairs(drinks) do
        print(drink.title)
    end
else
    print("HP request failed with status code:", status_code)
end
