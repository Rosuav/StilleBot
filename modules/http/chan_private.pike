inherit http_endpoint;
mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {return redirect("messages");}
