import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BR, FORM, INPUT, OPTION, SELECT, TD, TR} = choc; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

let allrewards = { };

//Choices offered in the drop-down. You can enter a custom value if you need more flexibility.
const availability_choices = {
	1: "Always",
	0: "Never",
	"{online}": "While you're live",
};

export const autorender = {
	dynreward_parent: DOM("#rewards tbody"),
	dynreward(r) { //extcall
		const av = r.availability || "{online}";
		return TR({"data-id": r.id}, [
			TD(FORM({id: r.id, className: "editreward"}, INPUT({name: "title", value: r.title, "size": 30}))),
			TD(INPUT({name: "prompt", form: r.id, value: r.prompt, size: 30})),
			TD(INPUT({name: "basecost", form: r.id, type: "number", value: r.basecost})),
			TD([
				SELECT({name: "availability-choices", form: r.id, value: availability_choices[av] ? av : ""}, [
					OPTION({value: "1"}, "Always"),
					OPTION({value: "0"}, "Never"),
					OPTION({value: "{online}"}, "While you're live"),
					OPTION({value: ""}, "Custom..."),
				]),
				BR(), INPUT({name: "availability", form: r.id, value: av}),
			]),
			TD(INPUT({name: "formula", form: r.id, value: r.formula})),
			TD(INPUT({name: "curcost", form: r.id, type: "number", value: r.curcost})),
			TD([
				INPUT({name: "rewardid", form: r.id, type: "hidden", value: r.id}),
				INPUT({form: r.id, type: "submit", value: "Save"}),
			]),
		]);
	},
	dynreward_empty() {return DOM("#rewards tbody").appendChild(TR([
		TD({colSpan: 6}, "No redemptions (add one!)"),
	]));},
}
export function render(data) {
	if (data.items) {
		allrewards = data.items;
		const copiables = allrewards.map((r, i) => OPTION({value: i}, r.title + (!r.can_manage || r.is_dynamic ? " (copy)" : "")));
		copiables.unshift(DOM("#copyfrom").firstElementChild);
		set_content("#copyfrom", copiables);
	}
}

//TODO: Put up a spinner - this takes most of a second
//TODO: Simplify the logic in this now that all it's doing is a WS message
function make_dynamic(basis) {ws_sync.send({cmd: "new_dynamic", id: basis.id});}
function create_dynamic(basis) {ws_sync.send({cmd: "new_dynamic", copy_from: basis});}
const confirm_already_dynamic = simpleconfirm("That reward already has dynamic management - want to create a copy of it?", create_dynamic);
const confirm_not_manageable = simpleconfirm("Due to Twitch limitations, we can't manage that reward itself, but can take a copy of it. Good to go?", create_dynamic);

DOM("#add").onclick = e => {
	const basis = allrewards[DOM("#copyfrom").value];
	if (!basis) return create_dynamic({});
	let next = make_dynamic;
	if (basis.is_dynamic) next = confirm_already_dynamic;
	else if (!basis.can_manage) next = confirm_not_manageable;
	next(basis);
};

async function save(el) {
	ws_sync.send({cmd: "update_dynamic",
		dynamic_id: el.rewardid.value, title: el.title.value, prompt: el.prompt.value, basecost: el.basecost.value,
		availability: el.availability.value, formula: el.formula.value, curcost: el.curcost.value});
}
on("submit", "form.editreward", e => {e.preventDefault(); save(e.match.elements);}, true);

on("input", "#rewards input", e => e.match.classList.add("dirty"));
on("change", "#rewards input, #rewards select", e => e.match.classList.add("dirty"));
on("paste", "#rewards input", e => e.match.classList.add("dirty"));

on("change", "[name=availability-choices]", e => {
	if (e.match.value !== "") {
		const inp = e.match.form.elements["availability"];
		inp.value = e.match.value;
		inp.classList.add("dirty"); //Changing the actual availability maes both the drop-down and the input dirty
	}
});
on("change", "[name=availability]", e => availability_choices[e.match.value] && (e.match.form.elements["availability-choices"].value = e.match.value));

on("click", "#save_all", e => {
	//For now, just save each row individually; it may be nice to have a bulk save
	//but it would probably still cost as much in API calls on the back end anyway.
	const saved = {}; //Only save any particular form once
	document.querySelectorAll("#rewards .dirty").forEach(inp => {
		if (saved[inp.form.id]) return;
		saved[inp.form.id] = 1;
		save(inp.form.elements);
	});
});
