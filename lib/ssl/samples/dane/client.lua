
socket = require "socket";
ssl = require "ssl";

dns = require "lunbound".new();


cfg = {
	protocol = "tlsv1_2",
	mode = "client",
	ciphers = "DEFAULT",
	capath = "/etc/ssl/certs",
	verify = "peer",
	dane = true,
};

function daneconnect(host, port)
   if port == nil then
      port = "443";
   end
	conn = ssl.wrap(socket.connect(host, port), cfg);

	tlsa = dns.resolve(dns, "_" .. port .. "._tcp." .. host, 52);
	assert(tlsa.secure, "Insecure DNS");

	assert(conn.setdane(conn, host));
	for i = 1, tlsa.n do
		usage, selector, mtype = tlsa[i] :byte(1, 3);
		assert(conn.settlsa(conn, usage, selector, mtype, tlsa[i] :sub(4, - 1)));
	end

	assert(conn.dohandshake(conn));
	return conn;
end

if ((... == nil or ... == false)) then
   print("Usage: client.lua example.com [port]");
   return os.exit(1);
end
conn = daneconnect(...);

print(conn.getpeerverification(conn));
