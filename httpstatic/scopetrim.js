import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {B, CODE, INPUT, LABEL, LI, SPAN} = choc; //autoimport

let all_sites = {}, current_url = null, current_origin = "";

function update_resultant_url() {
	const scopes = [];
	const prefs = all_sites[current_origin].scopes;
	//Note that this does not overwrite the scopes. If a site *reduces* the scopes it requests,
	//your preferences will still be remembered for the removed scopes.
	document.querySelectorAll(".scope_cb").forEach(cb => {
		prefs[cb.value] = cb.checked; //Remember both selected and deselected for preferences
		if (cb.checked) scopes.push(cb.value); //For the URL, keep only the selected ones
	});
	current_url.searchParams.set("scope", scopes.join(" "));
	DOM("#resultant_url").href = current_url.href;
	localStorage.setItem("scopetrim_sites", JSON.stringify(all_sites));
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
	current_origin = url.searchParams.get("redirect_uri") || url.searchParams.get("client_id") || "(unknown)";
	replace_content("#origin", [
		"Scopes requested by ",
		CODE(current_origin),
		":",
	]);
	const scopes = (url.searchParams.get("scope") || "").split(" ").filter(s => s.length);
	if (!scopes.length) {
		replace_content("#scopelist", LI("No scopes requested - this site will only see your user ID"));
		update_resultant_url();
		return;
	}
	//Reload the configs every time you edit the URL (in case you have two pages open)
	all_sites = {};
	try {all_sites = JSON.parse(localStorage.getItem("scopetrim_sites")) || {};} catch (e) {}
	//If this is a completely new site, don't show "(new)" on everything. However, if
	//we've previously seen anything at all - even if it didn't request any scopes - then
	//adorn every new scope so it can be seen.
	const new_site = !all_sites[current_origin];
	if (new_site) all_sites[current_origin] = {scopes: {}};
	if (!all_sites[current_origin].scopes) all_sites[current_origin].scopes = {};
	const prev = all_sites[current_origin].scopes;
	replace_content("#scopelist", scopes.map(s => LI(LABEL([
		!new_site && typeof prev[s] === "undefined" && B("(new)"),
		INPUT({type: "checkbox", class: "scope_cb", checked: prev[s] !== false, value: s}),
		(all_twitch_scopes[s] || s)[0] === '*' && SPAN({class: "warningicon"}, "⚠️"),
		" ",
		(all_twitch_scopes[s] || s).replace('*', ''),
		" - ", CODE(s),
	]))));
	update_resultant_url();
});
