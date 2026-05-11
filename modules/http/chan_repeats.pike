inherit http_websocket;
__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {return redirect("commands?repeats");}
