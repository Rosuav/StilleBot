//Monitor DeviCat's channel for quote commands and update a JSON file in the web site repo
//Note that the actual Markdown files are not edited by this.

constant CACHE_FILE = "../devicatoutlet.github.io/_quotes.json";

int message(object channel, mapping person, string msg)
{
	if (channel->name != "#devicat" || person->login != "candicat") return 0;
	sscanf(msg, "#%d: %s", int idx, string quote); if (!idx || !quote) return 0;
	mapping json = Standards.JSON.decode_utf8(Stdio.read_file(CACHE_FILE));
	if (sizeof(json->quotes) <= idx) json->quotes += ({Val.null}) * (idx - sizeof(json->quotes) + 1);
	json->quotes[idx] = quote;
	Stdio.write_file(CACHE_FILE, Standards.JSON.encode(json, 7) + "\n");
	return 0;
}

protected void create(string name)
{
	register_hook("all-msgs", file_stat(CACHE_FILE) && message);
}
