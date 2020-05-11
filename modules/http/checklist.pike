inherit http_endpoint;

//Markdown; emote names will be replaced with their emotes, but will
//be greyed out if not available.
constant hypetrain = #"
HypeChimp HypeGhost HypeChest HypeFrog HypeCherry
HypeSideeye HypeBrain HypeZap HypeShip HypeSign
HypeYikes HypeRacer HypeCar HypeFirst HypeTrophy
HypeBlock HypeDaze HypeBounce HypeJewel HypeBlob
HypeLove HypePunk HypeKO HypePunch HypeFire
";
Regexp.PCRE.Studied words = Regexp.PCRE.Studied("\\w+");

mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	string user = req->variables->user;
	if (!user)
	{
		return render_template("checklist.md",
			(["backlink": "","text": words->replace(hypetrain, lambda(string w) {
				string md = G->G->emote_code_to_markdown[w];
				if (!md) return w;
				return replace(md, "/1.0", "/3.0");
			}),
		]));
	}
	object ret = Concurrent.resolve(0);
	mapping emotelist;
	if (!emotelist) //TODO: Cache this for a bit (and then skip this block if found in cache)
		ret = ret->then(lambda() {return twitch_api_request("https://api.twitch.tv/kraken/users/{{USER}}/emotes",
			0, (["username": user]));
			})->then(lambda(mapping info) {
				info->fetchtime = time();
				emotelist = info;
			});
	return ret->then(lambda() {
		return ([
			"data": Standards.JSON.encode(emotelist, 7),
			"type": "application/json",
		]);
	});
}
