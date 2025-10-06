inherit annotated;

//fourthwall_access_token[channelid] = ({auth token, expiration time})
//If the expiration time is still in the future, use the auth token, otherwise fetch the refresh token from database.
@retain: mapping(int:array(string|int)) fourthwall_access_token = ([]);

@export: __async__ mapping|zero fourthwall_request(string|int userid, string method, string endpoint, mapping|void data) {
	if (stringp(userid)) userid = (int)userid;
	if (!fourthwall_access_token[userid] || fourthwall_access_token[userid][1] < time()) {
		werror("Renewing FW access token [%d]...\n", userid);
		mapping cfg = await(G->G->DB->load_config(0, "fourthwall"));
		mapping fw = await(G->G->DB->load_config(userid, "fourthwall"));
		object res = await(Protocols.HTTP.Promise.post_url("https://api.fourthwall.com/open-api/v1.0/platform/token",
			Protocols.HTTP.Promise.Arguments((["headers": ([
				"Content-Type": "application/x-www-form-urlencoded",
				"User-Agent": "MustardMine", //Having a user-agent that suggest that it's Mozilla will cause 403s from Fourth Wall's API.
				"Accept": "*/*",
			]), "data": Protocols.HTTP.http_encode_query(([
				"grant_type": "refresh_token",
				"client_id": cfg->clientid,
				"client_secret": cfg->secret,
				"refresh_token": fw->refresh_token,
			]))]))
		));
		mapping auth = Standards.JSON.decode_utf8(res->get());
		fourthwall_access_token[userid] = ({auth->access_token, time() + auth->expires_in - 2});
	}
	werror("Sending request [%d]: %s %s\n", userid, method, endpoint);
	object args = Protocols.HTTP.Promise.Arguments((["headers": ([
		"User-Agent": "MustardMine",
		"Accept": "*/*",
		"Authorization": "Bearer " + fourthwall_access_token[userid][0],
	])]));
	if (data) {args->headers["Content-Type"] = "application/json"; args->data = Standards.JSON.encode(data);}
	object res = await(Protocols.HTTP.Promise.do_method(method, "https://api.fourthwall.com/open-api/v1.0" + endpoint, args));
	if (res->headers["content-type"] == "application/json")
		return Standards.JSON.decode_utf8(res->get());
}
