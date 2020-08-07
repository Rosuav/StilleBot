//Probe the websocket half-closing bug
/* Symptom:
Can only close the connection in both directions simultaneously.
/usr/local/pike/8.1.13/lib/modules/SSL.pmod/File.pike:644:
    SSL.File(Stdio.File("socket", "192.168.0.19 52112", 777), SSL.ServerConnection(ready))->close("w",UNDEFINED,UNDEFINED)
/usr/local/pike/8.1.13/lib/modules/Protocols.pmod/WebSocket.pmod:873:
    Protocols.WebSocket.Connection(2, SSL.File(Stdio.File("socket", "192.168.0.19 52112", 777), SSL.ServerConnection(ready)), server, buffer mode)->send(Protocols.WebSocket.Frame(FRAME_CLOSE, fin: 1, rsv: 0, 2 bytes))
/usr/local/pike/8.1.13/lib/modules/Protocols.pmod/WebSocket.pmod:841:
    Protocols.WebSocket.Connection(2, SSL.File(Stdio.File("socket", "192.168.0.19 52112", 777), SSL.ServerConnection(ready)), server, buffer mode)->close(1001,UNDEFINED)
/usr/local/pike/8.1.13/lib/modules/Protocols.pmod/WebSocket.pmod:796:
    Protocols.WebSocket.Connection(2, SSL.File(Stdio.File("socket", "192.168.0.19 52112", 777), SSL.ServerConnection(ready)), server, buffer mode)->websocket_in(SSL.File(Stdio.File("socket", "192.168.0.19 52112", 777), SSL.ServerConnection(ready)),_static_modules._Stdio()->Buffer(0 bytes, read=[..7] data=[8..7] free=[8..224] allocated))
/usr/local/pike/8.1.13/lib/modules/Protocols.pmod/WebSocket.pmod:761:
    Protocols.WebSocket.Connection(2, SSL.File(Stdio.File("socket", "192.168.0.19 52112", 777), SSL.ServerConnection(ready)), server, buffer mode)->websocket_in()
/usr/local/pike/8.1.13/lib/modules/SSL.pmod/File.pike:1241:
    SSL.File(Stdio.File("socket", "192.168.0.19 52112", 777), SSL.ServerConnection(ready))->internal_poll()
-:1: Pike.Backend(0)->`()(3600.0)
*/

object httpserver;

void http_handler(Protocols.HTTP.Server.Request req)
{
	req->response_and_finish(([
		"data": "Hello, world\n",
		"type": "text/plain",
		"extra_heads": (["Connection": "close"]), //Do I still need this?
	]));
}

void ws_msg(Protocols.WebSocket.Frame frm, mapping conn)
{
	mixed data;
	if (catch {data = Standards.JSON.decode(frm->text);}) return; //Ignore frames that aren't text or aren't valid JSON
	write("Message: %O\n", data);
}

void ws_close(int reason, mapping conn)
{
	write("Closing socket %O\n", conn->sock);
	m_delete(conn, "sock"); //De-floop
}

void ws_handler(array(string) proto, Protocols.WebSocket.Request req)
{
	if (req->not_query != "/ws")
	{
		req->response_and_finish((["error": 404, "type": "text/plain", "data": "Not found"]));
		return;
	}
	Protocols.WebSocket.Connection sock = req->websocket_accept(0);
	sock->set_id((["sock": sock])); //Minstrel Hall style floop
	sock->onmessage = ws_msg;
	sock->onclose = ws_close;
	write("Got socket %O\n", sock);
}

int main()
{
	array certs = Standards.PEM.Messages(Stdio.read_file("certificate.pem"))->get_certificates();
	string pk = Standards.PEM.simple_decode(Stdio.read_file("privkey.pem"));
	int port = 8808;
	httpserver = Protocols.WebSocket.SSLPort(http_handler, ws_handler, port, "::", pk, certs);
	write("Listening on https://%s:%d/\n", Standards.X509.decode_certificate(certs[0])->subject_str(), port);
	return -1;
}
