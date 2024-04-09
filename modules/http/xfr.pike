//Transfer session cookies from sikorsky.rosuav.com to *.mustardmine.com
inherit http_endpoint;

mapping xfr_cookie = ([]); //NOT retained and not shared either.
__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	string host = deduce_host(req->request_headers);
	if (string dest = host == "sikorsky.rosuav.com" && req->misc->session->cookie && req->variables->dest) {
		//Set a default destination
		if ((<"sikorsky.mustardmine.com", "gideon.mustardmine.com", "mustardmine.com">)[dest])
			req->misc->session->autoxfr = dest;
		return redirect("https://mustardmine.com/");
	}
	if (string sess = host == "sikorsky.rosuav.com" && req->misc->session->cookie) {
		m_delete(xfr_cookie, xfr_cookie[sess]); //If we already have another, remove it
		string xfr = MIME.encode_base64("xf-" + random_string(9));
		xfr_cookie[xfr] = sess; xfr_cookie[sess] = xfr;
		call_out(m_delete, 60, xfr_cookie, sess);
		call_out(m_delete, 60, xfr_cookie, xfr);
		if (sscanf(req->request_headers->referer || "r", "https://sikorsky.rosuav.com/%s", string path) && path)
			req->misc->session->xfr_redirect = path;
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
		if (string path = m_delete(req->misc->session, "xfr_redirect"))
			return redirect("https://mustardmine.com/" + path);
	}
	sscanf(req->request_headers->referer || "r", "https://sikorsky.rosuav.com/%s", string path);
	return redirect("https://mustardmine.com/" + (path || ""));
}

