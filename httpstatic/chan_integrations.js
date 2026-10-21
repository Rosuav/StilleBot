import {choc, set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, B, BUTTON, FORM, IMG, INPUT, LI, P, STRONG, TD, TIME, TR, UL} = choc; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";
import {cmd_configure, publish_command} from "$$static||command_editor.js$$";

cmd_configure({
	subscribe: "-",
	get_command_basis: cmd => {
		set_content("#advanced_view h3", ["Edit actions for pledge/sale"]);
		return {
			type: "anchor_special",
			_provides: {
				"{username}": "The broadcaster", "{uid}": "ID of that person",
				"{sales}": "Current sale number",
				"{prevsales}": "Sales count prior to this update",
				"{productid}": "Unique ID of this product/campaign",
				"{title}": "Product/campaign title",
			},
			_desc: "Happens when the sale count changes (up or down)",
			_shortdesc: "Happens when the sale count changes (up or down)",
		};
	},
	save_command: (cmdname, original, response, language) => {
		ws_sync.send({cmd: "set_action", pfmid: cmdname, response, language});
	},
});

//crying
async function stupid(data) {
	console.log("STUPID URL", data);
	const resp = await fetch(data.url, {credentials: "omit"});
	console.log("STUPID RESP", resp);
	const text = await resp.text();
	console.log("STUPID TEXT", text);
	ws_sync.send({cmd: "stupid", stupid: data.stupid, text});
}

export function render(data) {
	//Note that the entire token will never be shown, only the last few characters
	if (data.kofitoken) DOM("#kofitoken").value = data.kofitoken;
	if (data.kofitokens) set_content("#kofitokens table tbody", [
		data.kofitokens.map(tok => TR([
			TD(FORM({class: "token", id: "kofitokform" + tok.label, "data-platform": "kofi"}, [
				INPUT({type: "hidden", name: "prevlabel", value: tok.label}),
				INPUT({size: 8, readonly: true, disabled: true, value: tok.label}),
			])),
			TD(INPUT({form: "kofitokform" + tok.label, name: "token", size: 40, value: tok.token})),
			TD(BUTTON({form: "kofitokform" + tok.label, type: "submit", name: "save"}, "Save")),
		])),
		TR([
			TD(FORM({class: "token", id: "kofitokform", "data-platform": "kofi"}, [
				INPUT({type: "hidden", name: "prevlabel", value: ""}),
				INPUT({name: "label", size: 8, required: true}),
			])),
			TD(INPUT({form: "kofitokform", name: "token", size: 40, required: true})),
			TD(BUTTON({form: "kofitokform", type: "submit", name: "save"}, "Add")),
		]),
	]);
	if (data.fwshopname) set_content("#fwstatus", [
		"Your Fourth Wall shop is: ",
		A({href: "https://" + data.fwurl}, data.fwshopname),
		" Welcome, ", data.fwusername, ". ",
		BUTTON({id: "fwlogin"}, "Reauthenticate"),
	]);
	if (data.paturl) set_content("#patreonstatus", [
		"Your Patreon campaign is: ",
		A({href: data.paturl}, data.paturl),
		" ",
		BUTTON({id: "resyncpatreon", type: "button"}, "Resync supporters"),
	]);
	if (data.makeship_campaigns) set_content("#makeship_campaigns", data.makeship_campaigns.map(cp => LI({"data-id": cp.pfmid}, [
		A({href: cp.url, target: "_blank"}, cp.title), " by ", B(cp.metadata.name.creator),
		" [" + cp.sales + "] ",
		publish_command(cp.pfmid, cp.action), //returns nothing
		BUTTON({type: "button", class: "advview", title: "Add/edit actions"}, "\u2699"),
		BUTTON({type: "button", class: "confirmdelete", title: "Stop tracking", style: "margin-left: 6px; width: 30px"}, "🗑"),
	])));
	if (data.stupid) stupid(data);
}

on("submit", ".token", e => {
	e.preventDefault();
	const msg = {cmd: "settoken", platform: e.match.dataset.platform};
	for (const el of e.match.elements) if (el.name) {msg[el.name] = el.value; el.value = "";}
	ws_sync.send(msg);
});

on("input", "input[name=token]", e => {
	const form = e.match.form.id, save = e.match.form.elements.save, blank = e.match.value === "";
	if (form === "kofitokform") save.disabled = blank;
	else if (form.startsWith("kofitokform")) set_content(save, blank ? "Delete" : "Save");
});

on("click", "#fwlogin", e => ws_sync.send({cmd: "fwlogin"}));

on("click", "#patreonlogin", e => {
	e.preventDefault();
	ws_sync.send({cmd: "patreonlogin"});
});

export function sockmsg_oauthpopup(msg) {
	window.open(msg.uri, "login", "width=525, height=900");
}

on("click", "#resyncpatreon", e => ws_sync.send({cmd: "resyncpatreon"}));

export function sockmsg_resyncpatreon(msg) {
	set_content("#patrons", msg.members.map(mem => LI([
		//We might not have Twitch connected, but we should at least have a name.
		STRONG(mem.name),
		" is paying ",
		//FIXME: What about other currencies? Here assuming that everything is some sort of dollar.
		STRONG(new Intl.NumberFormat("en-US", {style: "currency", currency: "USD"}).format(mem.price / 100)),
		" per month. ",
		mem.twitch && A({href: "https://twitch.tv/" + mem.twitch.login, target: "_blank"}, [
			IMG({src: mem.twitch.profile_image_url, class: "avatar"}),
			" ",
			mem.twitch.display_name,
		]),
	])));
	DOM("#patrondlg").showModal();
}

function DATE(date) {
	let day = date.getDate();
	switch (day) {
		case 1: case 21: day += "st"; break;
		case 2: case 22: day += "nd"; break;
		case 3: case 23: day += "rd"; break;
		default: day += "th";
	}
	return TIME({datetime: date.toISOString(), title: date.toLocaleString()}, [
		//This abbreviated format assumes English and shows just the date. The hover uses your locale.
		day + " " + "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(" ")[date.getMonth()] + " " + date.getFullYear(),
	]);
}

on("click", "#lookup", e => ws_sync.send({cmd: "makeship_lookup", url: DOM("#campaignurl").value}));
export function sockmsg_makeship_lookup(msg) {
	if (msg.error) return set_content("#campaigndetails", msg.error).classList = "error";
	if (msg.url && msg.url !== DOM("#campaignurl").value) DOM("#campaignurl").value = msg.url;
	const date_labels = {
		//Makeship-relevant dates
		petitionLaunchDate: "Petition!",
		petitionEndDate: "Petition ends",
		paymentDue: "Pledges due", // ? Not sure exactly what payment is due on this date; it happens prior to the campaign's launch.
		launch: "Campaign!",
		enddate: "Campaign ends",
		delivery: "Plushies are delivered!",
		//Kickstarter-relevant dates
		launched_at: "Campaign launched!",
		deadline: "Campaign ends",
	};
	//For simplicity, not actually sorting the dates per se, just using the order given above.
	//However, each date will individually be checked for "past" vs "future", so if they are
	//ever out of order (which may happen if a keyword is reused for multiple meanings), you
	//will still see which ones are upcoming.
	const now = +new Date;
	set_content("#campaigndetails", [
		B(msg.title),
		//P(["Tags:", msg.tags.map(t => [" ", CODE({style: "margin-left: 4px"}, t)])]),
		P("Sales: " + (msg.sales||0)),
		UL(Object.entries(date_labels).map(([id, lbl]) => {
			const date = msg.dates[id]; if (!date) return;
			const d = new Date(date);
			return LI({class: +d > now ? "date upcoming" : "date past"}, [DATE(d), " ", lbl]);
		})),
		BUTTON({id: "makeship_track", type: "button", "data-url": msg.url}, "Track this plushie!"),
	]).classList = "";
}

on("click", "#makeship_track", e => ws_sync.send({cmd: "makeship_track", url: e.match.dataset.url}));

on("click", "#makeship_campaigns .confirmdelete", simpleconfirm("Stop tracking this campaign? Its associated action (if any) will be deleted.",
	e => ws_sync.send({cmd: "makeship_untrack", pfmid: e.match.closest_data("id")})));
