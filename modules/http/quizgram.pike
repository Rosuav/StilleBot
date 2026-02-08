inherit http_endpoint;
constant markdown = #"# Quizgram

<style>
input.ltr {font-size: 100%; width: 1.25em; text-transform: uppercase;}
input[readonly].ltr {background: aliceblue;}
img[alt=\"Avatar\"] {max-height: 2em; vertical-align: middle;}
</style>

## `_____` `___` `__` `________`, `____` `_____` `_________`.
## - `___` `____`

---

### DeviCat
1. What is your husband's username? `_____________`
2. What colour are CandiCat's ears? `____` and `______`

### CamaeSoultamer
1. What level of chaos is acceptable? `_-3-__`
2. What is Camae's favourite colour? `_____-1-` `_____`
3. Name the cat who hangs out on stream. `______`

### ABluSkittle
1. What kind of animals get hidden in all Skittle's art? `-29-___`

### RissaBunn
1. How many children does Rissa have? `__-10-`
2. What kind of cat is Tsuki? `___-35-__`
";

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	array parts = markdown / "\n### ";
	foreach (parts; int i; string text) {
		if (!i) continue; //Skip the initial blob
		sscanf(text, "%s\n%s", string channel, text);
		mapping user = await(get_user_info(channel, "login"));
		parts[i] = sprintf("%s\n[![Avatar](%s) Visit %s's channel](https://twitch.tv/%s :target=_blank)\n\n%s", channel, user->profile_image_url, user->display_name, user->login, text);
	}
	return render_template(parts * "\n### ", (["js": "quizgram.js"]));
}
