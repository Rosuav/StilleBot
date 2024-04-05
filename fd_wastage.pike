constant listen_addr = "::", listen_port = 9876;

void http_handler(Protocols.HTTP.Server.Request req)
{
	int before = sizeof(get_dir("/proc/self/fd"));
	int garbo = gc(); //Disabling this check results in FDs accumulating.
	int after = sizeof(get_dir("/proc/self/fd"));
	werror("Garbage %O, closed %d files, now %d open\n", garbo, before - after, after);
	//The "Connection: close" header is vital to the sockets becoming garbage.
	//Without it, they are retained pending a followup request, which doesn't change the
	//fundamental issue but does mean that a call to gc() doesn't clean them up.
	req->response_and_finish((["data": "OK", "extra_heads": (["Connection": "close"])]));
	//req->response_and_finish((["data": "OK"]));
}

int main() {
	//If you don't have a cert, the first request is slower b/c generating self-signed.
	string cert = Stdio.read_file("certificate_local.pem");
	string key = Stdio.read_file("privkey_local.pem");
	array certs = cert && Standards.PEM.Messages(cert)->get_certificates();
	string pk = key && Standards.PEM.simple_decode(key);
	Protocols.HTTP.Server.SSLPort(http_handler, listen_port, listen_addr, pk, certs);
	return -1;
}
