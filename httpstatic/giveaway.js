import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {DIV, LI} = choc;
fix_dialogs({close_selector: ".dialog_cancel,.dialog_close", click_outside: true});

set_content("#existing", rewards.map(r => LI(r.title)));

/*
1) Create rewards
   - Choose points per ticket
   - Optionally pick some multibuy amounts
   - PUT request to set all settings. The back end will do the necessary changes.
2) Activate rewards
   - PUT request with a single flag. Back end will clear counts and activate.
3) Notice redemptions - possibly with caps and autorejection?
4) Deactivate rewards and pick a winner
5) Multiple winners?? Will need a way to say "pick another without clearing".

When no current giveaway, show most recent winner. (Maybe allow that to be cleared??)
*/

on("submit", "#configform", async e => {
	e.preventDefault();
	const el = e.match.elements;
	const body = {cost: el.cost.value, desc: el.desc.value, multi: el.multi.value, max: el.max.value};
	const info = await (await fetch("giveaway", {
		method: "PUT",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify(body),
	})).json();
	console.log("Got response:", info);
});
