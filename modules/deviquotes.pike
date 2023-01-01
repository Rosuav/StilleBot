//Monitor DeviCat's channel for quote commands and update a JSON file in the web site repo
//Note that the actual Markdown files are not edited by this.
inherit hook;

constant CACHE_FILE = "../devicatoutlet.github.io/_quotes.json";
mapping json;

@hook_allmsgs:
int message(object channel, mapping person, string msg)
{
	if (channel->name != "#devicat" || person->user != "candicat") return 0;
	sscanf(msg, "#%d: %s", int idx, string quote);
	int save = 0;
	if (idx && quote) {
		if (sizeof(json->quotesnew) <= idx) json->quotesnew += ({Val.null}) * (idx - sizeof(json->quotesnew) + 1);
		if (json->quotesnew[idx] != quote) {json->quotesnew[idx] = quote; save = 1;}
	}
	//Record all emotes seen and their IDs so the Markdown builder knows what's an emote
	if (!json->emotes) json->emotes = ([]);
	foreach (person->emotes || ({ }), [string id, int start, int end]) {
		//Note that measurement_offset doesn't apply here as it's an all-msgs hook
		if (has_prefix(id, "/")) continue; //Ignore cheeremotes (highly unlikely that Candi will cheer anyway!)
		string name = msg[start..end];
		if (has_value(name, '_')) continue; //Ignore emotes with _SQ or _HF etc - we can synthesize them from the base emotes
		if (json->emotes[name] != id) {json->emotes[name] = id; save = 1;}
	}
	if (save) Stdio.write_file(CACHE_FILE, Standards.JSON.encode(json, 7) + "\n");
	return 0;
}

protected void create(string name)
{
	catch {json = Standards.JSON.decode_utf8(Stdio.read_file(CACHE_FILE));};
	if (json) ::create(name); //Hack: Don't initialize self if no JSON file
}
