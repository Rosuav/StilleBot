import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, BR, BUTTON, CODE, DETAILS, SUMMARY, DIV, FORM, INPUT, OPTION, OPTGROUP, SELECT, TABLE, TR, TH, TD} = choc;
import {open_advanced_view} from "$$static||chan_commands.js$$";

function update_milepicker() {
	const thresholds = DOM("[name=thresholds]").value.split(" ");
	const pos = +DOM("[name=currentval]").value;
	const opts = [];
	thresholds.push(Infinity); //Place a known elephant in Cairo
	let val = -1, total = 0;
	for (let which = 0; which < thresholds.length; ++which) {
		//Record the *previous* total as the mark for this mile. If you pick
		//mile 3, the total should be set to the *start* of mile 3.
		const desc = which === thresholds.length - 1 ? "And beyond!" : "Mile " + (which + 1);
		const prevtotal = total;
		total += 100 * +thresholds[which]; //What if thresholds[which] isn't numeric??
		opts.push(OPTION({value: prevtotal}, desc));
		if (val === -1 && pos < total) val = prevtotal;
	}
	set_content(DOM("[name=milepicker]"), opts).value = val;
}
window.update_milepicker = update_milepicker; //Not clean but whatever. Allow chan_monitors to trigger this.
DOM("[name=thresholds]").onchange = DOM("[name=currentval]").onchange = update_milepicker;
DOM("[name=milepicker]").onchange = e => DOM("[name=currentval]").value = e.currentTarget.value;
DOM("#setval").onclick = async e => {
	const val = +DOM("[name=currentval]").value;
	if (val !== val) return; //TODO: Be nicer
	const rc = await fetch("run", {
		method: "PUT",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify({"var": DOM("[name=varname]").value, val}),
	});
	if (!rc.ok) {console.error("Couldn't update (TODO)"); return;}
}

on("submit", "form", async e => {
	e.preventDefault();
	if (!nonce) return; //TODO: Be nicer
	const body = {nonce};
	css_attributes.split(" ").forEach(attr => {
		if (!e.match.elements[attr]) return;
		body[attr] = e.match.elements[attr].value;
	});
	body.text = `$${e.match.elements.varname.value}$:${e.match.elements.text.value}`;
	fetch("monitors", { //Uses same API backend as the main monitors page does
		method: "PUT",
		headers: {"Content-Type": "application/json"},
		body: JSON.stringify(body),
	})
});

on("dragstart", ".monitorlink", e => {
	const url = `${e.match.href}&layer-name=StilleBot%20monitor&layer-width=120&layer-height=20`;
	e.dataTransfer.setData("text/uri-list", url);
});

function textify(cmd) {
	if (typeof cmd === "string") return cmd;
	if (Array.isArray(cmd)) return cmd.map(textify).filter(x => x).join(" // ");
	if (cmd.dest) return null; //Suppress special-destination sections
	return cmd.message;
}
const commands = { };
ws_sync.connect("#" + channame, {
	ws_type: "chan_commands",
	select: DOM("#cmdpicker"),
	make_option: cmd => OPTION({"data-id": cmd.id, value: cmd.id.split("#")[0]}, "!" + cmd.id.split("#")[0] + " -- " + textify(cmd.message)),
	is_recommended: cmd => cmd.access === "none" && cmd.visibility === "hidden",
	render: function(data) {
		if (data.id) {
			const opt = select.querySelector(`[data-id="${data.id}"]`);
			//Note that a partial update (currently) won't move a command between groups.
			if (opt) set_content(opt, "!" + cmd.id.split("#")[0] + " -- " + textify(cmd.message)); //TODO: dedup
			else this.groups[this.is_recommended(cmd) ? 1 : 2].appendChild(this.make_option(cmd));
			commands[data.id] = data;
			return;
		}
		if (!this.groups) set_content(this.select, this.groups = [
			OPTGROUP({label: "None"}, OPTION({value: ""}, "No response - levels will pass silently")),
			OPTGROUP({label: "Recommended"}),
			OPTGROUP({label: "Other"}),
		]);
		const blocks = [[], []];
		data.items.forEach(cmd => blocks[this.is_recommended(cmd) ? 0 : 1].push(this.make_option(commands[cmd.id] = cmd)));
		set_content(this.groups[1], blocks[0]);
		set_content(this.groups[2], blocks[1]);
		const want = this.select.dataset.wantvalue;
		if (want) this.select.value = want;
	},
});

DOM("#editlvlup").onclick = e => {
	const id = DOM("#cmdpicker").selectedOptions[0].dataset.id;
	if (commands[id]) open_advanced_view(commands[id]);
}
