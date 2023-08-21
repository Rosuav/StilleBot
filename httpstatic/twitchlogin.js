import {choc, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {B, CODE, INPUT, LABEL, LI, SPAN} = choc; //autoimport

function update_login_button() {
	const scopes = [];
	document.querySelectorAll(".scope_cb").forEach(cb => {
		if (cb.checked) scopes.push(cb.value);
	});
	DOM("#addscopes").dataset.scopes = scopes.join(" ");
}
on("click", ".scope_cb", update_login_button);
