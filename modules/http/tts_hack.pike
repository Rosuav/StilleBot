inherit http_websocket;
inherit annotated;

constant markdown = #"# TTS hack

<audio controls id=player></audio>

<label>Voice: <select id=tts_voice></select></label>
<form id=send><label>Enter stuff: <input size=80 id=stuff></label> <button>Send</button></form>
";

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	return render(req, (["vars": (["ws_group": req->variables->key || ""])]));
}

@retain: multiset tts_hack_valid_keys = (<>);
string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!tts_hack_valid_keys[msg->group]) return "Nope";
}

mapping get_state(string group) {
	return (["voices": G->G->tts_config->avail_voices || ({ })]);
}

__async__ mapping|zero websocket_cmd_speak(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	string text = msg->text;
	if (!text || text == "") return 0;
	object alertbox = G->G->websocket_types->chan_alertbox;
	text = await(alertbox->filter_bad_words(text, "replace"));
	string tts = await(alertbox->text_to_speech(text, msg->voice || "en-GB/en-GB-Standard-A/FEMALE", "tts_hack"));
	return (["cmd": "speak", "text": text, "tts": tts]);
}

protected void create(string name) {::create(name);}
