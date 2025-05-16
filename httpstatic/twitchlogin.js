import {choc, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {B, CODE, INPUT, LABEL, LI, SPAN} = choc; //autoimport

function update_login_button() {
	const scopes = [];
	document.querySelectorAll(".scope_cb").forEach(cb => {
		if (cb.checked) scopes.push(cb.value);
	});
	document.querySelectorAll(".addscopes").forEach(el => 
		el.dataset.scopes = scopes.join(" ") + " " + retain_scopes
	);
	const url = new URL("/twitchlogin", window.location);
	url.searchParams.set("scopes", scopes.join(" "));
	document.querySelectorAll(".shareable").forEach(el => el.href = url);
}
on("click", ".scope_cb", update_login_button);
update_login_button();
