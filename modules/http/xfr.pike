//Transfer session cookies from sikorsky.rosuav.com to *.mustardmine.com
inherit http_endpoint;

mapping xfr_cookie = ([]); //NOT retained and not shared either.
__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	string host = deduce_host(req->request_headers);
	if (string sess = host == "sikorsky.rosuav.com" && req->misc->session->cookie) {
		m_delete(xfr_cookie, xfr_cookie[sess]); //If we already have another, remove it
		string xfr = MIME.encode_base64("xf-" + random_string(9));
		xfr_cookie[xfr] = sess; xfr_cookie[sess] = xfr;
		return redirect("https://sikorsky.mustardmine.com/xfr?goal=" + xfr);
	}
	if (string xfr = host == "sikorsky.mustardmine.com" && req->variables->goal) {
		string sess = m_delete(xfr_cookie, xfr); m_delete(xfr_cookie, sess);
		if (!sess) return redirect("https://mustardmine.com/");
		mapping new_session = await(G->G->DB->load_session(sess));
		if (sizeof(new_session) <= 1) return redirect("https://mustardmine.com/");
		//Merge the sessions. Priority goes to the sikorsky.rosuav.com session if there's
		//a conflict, including the session token.
		req->misc->session |= new_session;
	}
	return redirect("https://mustardmine.com/");
}

