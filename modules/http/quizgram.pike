inherit http_endpoint;
constant markdown = #"# Quizgram

<style>
input.ltr {font-size: 100%; width: 1.25em; text-transform: uppercase;}
</style>

## `_____` `___` `__` `________`, `____` `_____` `_________`.
## - `___` `____`

---

### DeviCat
1. What is your husband's username? `_____________`
2. What colour are CandiCat's ears? `____` and `______`
";

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	return render_template(markdown, (["js": "quizgram.js"]));
}
