import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {INPUT, LABEL, LI} = choc; //autoimport

let current_url = null;

function update_resultant_url() {
	const scopes = [];
	document.querySelectorAll(".scope_cb").forEach(cb => cb.checked && scopes.push(cb.value));
	current_url.searchParams.set("scope", scopes.join(" "));
	DOM("#resultant_url").href = current_url.href;
	//TODO: Save into local storage
}
on("click", ".scope_cb", update_resultant_url);

on("input", "#original_url", e => {
	let url;
	try {url = new URL(e.match.value);}
	catch (e) {
		replace_content("#scopelist", LI("(paste a Twitch login URL in the above field to start trimming)"));
		return;
	}
	current_url = url;
	const scopes = (url.searchParams.get("scope") || "").split(" ").filter(s => s.length);
	if (!scopes.length) {
		replace_content("#scopelist", LI("No scopes requested - this site will only see your user ID"));
		update_resultant_url();
		return;
	}
	//TODO: Fetch from local storage to see whether the checkboxes should be initially checked or unchecked
	//(If anything wasn't previously in the mapping - undefined, as opposed to true/false - highlight it.)
	//TODO: Mark some of them with a yellow warning triangle
	replace_content("#scopelist", scopes.map(s => LI(LABEL([
		INPUT({type: "checkbox", class: "scope_cb", checked: true, value: s}),
		" ",
		all_twitch_scopes[s] || s,
	]))));
	update_resultant_url();
});
