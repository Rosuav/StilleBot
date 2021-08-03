//Monitor DeviCat's channel for quote commands and update a JSON file in the web site repo
//Note that the actual Markdown files are not edited by this.

constant CACHE_FILE = "../devicatoutlet.github.io/_quotes.json";
mapping json;

int message(object channel, mapping person, string msg)
{
	if (channel->name != "#devicat" || person->user != "candicat") return 0;
	//TODO: Record all emotes seen and their IDs. May save us the trouble of updating emotes in full.
	sscanf(msg, "#%d: %s", int idx, string quote);
	int save = 0;
	if (idx && quote) {
		if (sizeof(json->quotes) <= idx) json->quotes += ({Val.null}) * (idx - sizeof(json->quotes) + 1);
		if (json->quotes[idx] != quote) {json->quotes[idx] = quote; save = 1;}
	}
	if (!json->emotes) json->emotes = ([]);
	foreach (person->emotes || ({ }), [int|string id, int start, int end]) {
		//Note that measurement_offset doesn't apply here as it's an all-msgs hook
		string name = msg[start..end];
		if (has_value(name, '_')) continue; //Ignore emotes with _SQ or _HF etc - we can synthesize them from the base emotes
		if (json->emotes[name] != (string)id) {json->emotes[name] = (string)id; save = 1;}
	}
	if (save) Stdio.write_file(CACHE_FILE, Standards.JSON.encode(json, 7) + "\n");
	return 0;
}

protected void create(string name)
{
	catch {json = Standards.JSON.decode_utf8(Stdio.read_file(CACHE_FILE));};
	register_hook("all-msgs", mappingp(json) && message);
}
