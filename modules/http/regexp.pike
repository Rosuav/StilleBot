inherit http_websocket;

mapping regex_cache = ([]);

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	return render(req, ([
		"vars": (["ws_group": ""]),
	]));
}

mapping get_state(string group, string|void id) {return ([]);}

void websocket_cmd_test(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	object re = regex_cache[msg->regexp];
	mapping ret = (["cmd": "testresult", "regexp": msg->regexp, "text": msg->text]);
	if (mixed ex = !re && catch (re = regex_cache[msg->regexp] = Regexp.PCRE(msg->regexp))) {
		ret->error = ex[0]; ret->errorloc = -1;
		//If sscanf fails, just leave the full text in ret->error.
		sscanf(ret->error, "error calling pcre_compile [%d]: %s", ret->errorloc, ret->error);
	}
	else {
		int|array match = re->exec(msg->text);
		ret->matches = arrayp(match);
		if (arrayp(match)) ret->matchtext = map(match / 2) {return msg->text[__ARGS__[0][0]..__ARGS__[0][1]-1];};
	}
	conn->sock->send_text(Standards.JSON.encode(ret, 4));
}
