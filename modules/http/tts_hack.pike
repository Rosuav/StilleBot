inherit http_websocket;
inherit annotated;

constant markdown = #"# TTS hack

<audio controls id=player></audio>

<label>Voice: <select id=tts_voice></select></label>
<form id=send><label>Enter stuff: <input size=80 id=stuff></label> <button>Send</button></form>
";

//Map a group name to the last-sighted TTS rate schedule
//This won't be perfect, but it's only for the drop-down, so it's not that big a deal if it's wrong.
mapping tts_rate = ([]);
__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	string key = req->variables->key || "";
	if (key != "") {
		mapping premium = await(G->G->DB->load_config(0, "premium_accounts"));
		tts_rate[key] = premium[(string)req->misc->session->user->?id]->?tts_rate;
	}
	return render(req, (["vars": (["ws_group": key])]));
}

@retain: multiset tts_hack_valid_keys = (<>);
string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!tts_hack_valid_keys[msg->group]) return "Nope";
}

mapping get_state(string group) {
	return (["voices": G->G->tts_config->avail_voices[?tts_rate[group]] || ({ })]); //If no TTS rate set, use RATE_STANDARD (0)
}

__async__ mapping|zero websocket_cmd_speak(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	string text = msg->text;
	if (!text || text == "") return 0;
	object alertbox = G->G->websocket_types->chan_alertbox;
	text = await(alertbox->filter_bad_words(text, "replace"));
	werror("TTS Hack %O -> %O\n", msg->voice, msg->text);
	string tts = await(alertbox->text_to_speech(text, msg->voice || "en-GB/en-GB-Standard-A/FEMALE", (int)conn->session->user->?id));
	return (["cmd": "speak", "text": text, "tts": tts]);
}

protected void create(string name) {::create(name);}
