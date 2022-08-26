import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, ABBR, AUDIO, B, BR, BUTTON, CODE, DETAILS, DIV, FIGCAPTION, FIGURE, FORM, H3, HR, IMG, INPUT, LABEL, LI, OPTGROUP, OPTION, P, SELECT, SPAN, SUMMARY, TABLE, TD, TR, UL, VIDEO} = choc; //autoimport
import {waitlate, TEXTFORMATTING} from "$$static||utils.js$$";

function THUMB(file) {
	if (!file.url) return DIV({className: "thumbnail"}, "uploading...");
	if (file.mimetype.startsWith("audio/")) return DIV({className: "thumbnail"}, AUDIO({src: file.url, controls: true}));
	if (file.mimetype.startsWith("video/")) {
		const elem = VIDEO({class: "thumbnail", src: file.url, loop: true, ".muted": true});
		elem.play();
		return elem;
	}
	return DIV({className: "thumbnail", style: "background-image: url(" + file.url + ")"});
}

const TRANSPARENT_IMAGE = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNgAAIAAAUAAen63NgAAAAASUVORK5CYII=";
const FREEMEDIA_ROOT = "https://rosuav.github.io/free-media/"
const FREEMEDIA_BASE = FREEMEDIA_ROOT + "media/";

const files = { };
const alerttypes = { }, alert_definitions = { };
const revert_data = { };

//NOTE: Item rendering applies to uploaded files. Other things are handled by render() itself.
//NOTE: Since newly-uploaded files will always go to the end, this should always be sorted by
//order added, as a documented feature. The server will need to ensure this.
export const autorender = {
	item_parent: DOM("#uploads"),
	item(file, obj) {
		//TODO: If obj, reduce flicker by reconfiguring it, without doing any changes to the
		//thumbnail if the URL hasn't changed.
		files[file.id] = file;
		return LABEL({"data-type": file.mimetype}, [
			INPUT({type: "radio", name: "chooseme", value: file.id}),
			FIGURE([
				THUMB(file),
				FIGCAPTION([
					A({href: file.url, target: "_blank"}, file.name),
					" ",
					BUTTON({type: "button", className: "renamefile", title: "Rename"}, "📝"),
				]),
				BUTTON({type: "button", className: "confirmdelete", title: "Delete"}, "🗑"),
			]),
		]);
	},
};

//TODO: Call this once and only once, if the user wants freemedia browsing (currently called on startup which is inefficient)
const freemedia_files = { };
async function populate_freemedia() {
	const data = await (await fetch(FREEMEDIA_ROOT + "filelist.json")).json();
	console.log("Got free media", data);
	data.files.forEach(file => {
		file.url = FREEMEDIA_BASE + file.filename;
		freemedia_files[file.filename] = file;
	});
	set_content("#freemedialibrary", data.files.map(file => LABEL({"data-type": file.mimetype}, [
		INPUT({type: "radio", name: "chooseme", value: file.filename}),
		FIGURE([
			THUMB(file),
			FIGCAPTION([
				A({href: file.url, target: "_blank"}, file.filename),
			]),
		]),
	])));
}
populate_freemedia();

let have_authkey = false;
export function sockmsg_authkey(msg) {
	DOM("#alertboxlink").href = "alertbox?key=" + msg.key;
	msg.key = "<hidden>";
	have_authkey = true;
	if (DOM("#previewdlg").open) DOM("#alertembed").src = DOM("#alertboxlink").href;
}

let ip_history = null, ip_log = [];
function update_ip_log() {
	set_content("#ip_log", ip_log.map(([ip, n, from, to]) => {
		if (!ip_history || ip > ip_history.length) ip = "IP #" + (ip + 1);
		else ip = ip_history[ip];
		let times = n + " times";
		if (n === 1) times = "just once";
		else if (n === 2) times = "twice";
		let dates;
		from = new Date(from * 1000).toLocaleDateString();
		to = new Date(to * 1000).toLocaleDateString();
		//Note that from and to can be equal even if the original timestamps weren't
		//(since we're just reporting the date, not the time).
		if (from === to) dates = " on " + from;
		else dates = " between " + from + " and " + to;
		return LI([
			B(ip),
			" - " + times + dates
		]);
	}));
}
export function sockmsg_auditlog(msg) {ip_history = msg.ip_history; update_ip_log();}

function update_condition_summary(par) {
	const target = par.querySelector(".cond-label");
	if (target) set_content(target, par.querySelector("[name=cond-label]").value || "always");
}

function load_data(type, attrs, par) {
	revert_data[type] = attrs;
	if (!par) par = alerttypes[type];
	if (!par) return;
	if (par.classList.contains("unsaved-changes")) return; //TODO: Notify the user that server changes haven't been applied
	for (let el of par.elements) {
		if (!el.name) continue;
		if (el.type === "checkbox") el.checked = !!attrs[el.name];
		else if (el.type === "color") el.value = attrs[el.name] || "#000000"; //Suppress warning about empty string being inappropriate
		else if (el.name.startsWith("condoper-is_") && attrs[el.name] === "==")
			//Hack: Boolean conditions are stored internally as "== 1" or "== 0",
			//but are shown to the user as "Yes"/"No" with values "true" and "false".
			el.value = attrs[el.name.replace("condoper", "condval")] === 1;
		else el.value = attrs[el.name] || "";
		el.classList.remove("dirty");
		el.labels.forEach(l => l.classList.remove("dirty"));
		if (el.tagName === "SELECT" || el.type === "text" || el.type === "number") {
			el.classList.toggle("inherited", el.value === "");
			el.labels.forEach(l => l.classList.toggle("inherited", el.value === ""));
		}
	}
	const summary = par.querySelector(".condbox summary");
	if (summary) summary.title = "Specificity: " + (attrs.specificity || 0);
	const previewimg = par.querySelector("[data-library=image]");
	if (previewimg && (previewimg.tagName !== "VIDEO") !== !attrs.image_is_video) {
		if (attrs.image_is_video) {
			const el = VIDEO({class: "preview", "data-library": "image", src: attrs.image, loop: true, ".muted": true});
			previewimg.replaceWith(el);
			el.play();
		}
		previewimg.replaceWith(IMG({class: "preview", "data-library": "image", src: attrs.image || TRANSPARENT_IMAGE}));
	}
	par.querySelectorAll("[data-library]").forEach(el => {
		const want = attrs[el.dataset.library] || TRANSPARENT_IMAGE;
		if (el.src !== want) el.src = want; //Avoid flicker and video breakage by only setting if it's different
		const block = el.closest(".inheritblock");
		if (block) block.classList.toggle("inherited", !attrs[el.dataset.library]);
	});
	update_layout_options(par, attrs.layout);
	update_condition_summary(par);
	document.querySelectorAll("input[type=range]").forEach(rangedisplay);
	par.querySelectorAll("[type=submit]").forEach(el => el.disabled = true);
	//For everything in this alert's MRO, disallow that thing inheriting from this one.
	//That makes reference cycles impossible (barring shenanigans, which would be caught
	//on the server by simply inheriting nothing).
	const mro = attrs.mro || [type];
	document.querySelectorAll("select[name=parent] option[value=\"" + type + "\"]").forEach(el =>
		el.disabled = mro.includes(el.closest(".alertconfig").dataset.type)
	);
}

function make_condition_vars(vars, phold) {
	const opers = {
		"is_": {"": "n/a", "true": "Yes", "false": "No"},
		"'": {"": "n/a", "==": "is exactly", "incl": "includes"},
		"": {"": "n/a", "==": "is exactly", ">=": "is at least"},
	};
	return vars && vars.map(c => {
		const id = c.replace("'", "");
		const operset = Object.keys(opers).find(pfx => c.startsWith(pfx));
		return TR([
			TD(id), //TODO: Replace with a short name
			TD(SELECT({name: "condoper-" + id}, Object.entries(opers[operset]).map(([k, v]) =>
				OPTION({value: k}, v)
			))),
			TD(operset !== "is_" && INPUT({name: "condval-" + id, type: c[0] === "'" ? "text" : "number"})),
			TD(phold[id] || ""),
		]);
	});
}

function alert_name(id) {
	//Figure out a reasonable name for an alert type, based on the ID.
	const base = id.split("-")[0], info = alert_definitions[base];
	//If the alert has been deleted, it must (almost certainly) have been a personal
	if (!info) return "(Personal alert)";
	//Otherwise, we show the description for the base alert, possibly with some
	//adornment indicating which variant was selected.
	let name = info.label;
	const cfg = revert_data[id] || { };
	if (!cfg) return name; //A deleted variant - just use the base name.
	if (cfg["cond-label"]) name += " - " + cfg["cond-label"];
	//If no label, can we synthesize something useful?
	return name;
}

//Based on the alert type, try to give some useful information.
const replay_details = {
	cheer: r => [r.bits, " bits - ", CODE(r.msg)],
	personal: r => CODE(r.text),
}

let wanted_variant = null; //Unlike wanted_tab, this won't be loadable on startup (no need).
function update_alert_variants() {
	const basetype = DOM("#variationdlg form").dataset.type.split("-")[0];
	const variants = (revert_data[basetype].variants || []).map(id => {
		const attrs = revert_data[id] || { };
		return OPTION({value: id.split("-")[1]}, 
			basetype === "defaults" ? attrs.name || "unnamed " + id.split("-")[1]
			: attrs.name || attrs["cond-label"] || "(always)"
		);
	});
	const sel = set_content("#variationdlg [name=variant]", [
		OPTION({value: ""}, "Add new"),
		variants,
	]);
	//Loading data will clear the select, so we have to populate it, then load, then choose the selected variant.
	const frm = DOM("#variationdlg form"), type = basetype + "-" + (wanted_variant||"");
	load_data(wanted_variant, revert_data[type] || {active: true, parent: basetype}, frm);
	sel.value = wanted_variant || "";
	frm.dataset.type = type;
	DOM("#variationdlg .testalert").disabled = !wanted_variant || wanted_tab === "defaults";
	frm.querySelector(".confirmdelete").classList.toggle("invisible", !wanted_variant);
}

export function sockmsg_select_variant(msg) {
	const basetype = DOM("#variationdlg form").dataset.type.split("-")[0];
	if (basetype === msg.type) {wanted_variant = msg.variant; update_alert_variants();}
}

let selecttab = location.hash.slice(1);
export function render(data) {
	if (data.authkey === "<REVOKED>") {
		have_authkey = false;
		if (DOM("#previewdlg").open) ws_sync.send({cmd: "getkey"});
	}
	if (data.alerttypes) data.alerttypes.forEach(info => {
		const type = info.id;
		alert_definitions[type] = info;
		if (!info.placeholders) {
			//Personal alerts don't have all their data stored, since it would be the same for all
			//personals, and might change over time. (TODO: Send it from the back end instead?)
			info.placeholders = {text: "the text used to trigger the alert"};
			info.condition_vars = ["'text"];
		}
		const placeholder_description = Object.entries(info.placeholders).map(([k,d]) => [BR(), CODE("{" + k + "}"), " - " + d]);
		if (alerttypes[type]) {
			for (let kwd in info) {
				let txt = info[kwd];
				if (kwd === "placeholders") txt = placeholder_description;
				const elem = alerttypes[type].querySelector("." + kwd);
				if (elem) set_content(elem, txt);
			}
			if (type !== "variant") set_content("label[for=select-" + type + "]", info.label);
			return;
		}
		if (type !== "variant") {
			DOM("#newpersonal").before(LI([
				INPUT({type: "radio", name: "alertselect", id: "select-" + type, value: type}),
				LABEL({htmlFor: "select-" + type}, info.label),
			]));
			document.querySelectorAll("select[name=parent]").forEach(el => el.appendChild(OPTION({value: type}, info.label)));
		}
		const nondef = type !== "defaults"; //A lot of things are different for the defaults
		//For variants, some things get redescribed when it's in alertset mode. Variant/Set
		//descriptors are in a superposition, or some technobabble like that.
		const VS = type === "variant" ? (v,s) => [SPAN({class: "not-alertset"}, v), SPAN({class: "not-variant"}, s)] : (v,s) => v;
		DOM("#alertconfigs").appendChild(alerttypes[type] = FORM({class: type === "defaults" ? "alertconfig no-inherit": "alertconfig", "data-type": type}, [
			H3({className: "heading"}, [
				VS(info.heading, "Alert Set"), SPAN({className: "if-unsaved"}, " "),
				ABBR({className: "dirty if-unsaved", title: "Unsaved changes - click Save to apply them"}, "*"),
			]),
			P([
				!info.builtin && BUTTON({type: "button", className: "editpersonaldesc", title: "Edit"}, "📝"),
				SPAN({class: "description not-alertset"}, info.description),
				type === "variant" && SPAN({class: "not-variant"}, "Create alert sets to easily enable/disable all associated alert variants. You can also set layout defaults for alert sets."),
			]),
			type === "hostalert" && P({class: "no-dirty no-inherit"}, [
				host_alert_scopes && DIV({class: "need-auth"}, [
					"Host alerts require authentication as the broadcaster. ",
					BUTTON({class: "twitchlogin", "data-scopes": host_alert_scopes}, "Grant permissions"),
				]),
				"Select host detection back end: ",
				SELECT({name: "hostbackend"}, [
					OPTION({value: "none"}, "None"),
					OPTION({value: "js"}, "JavaScript"),
					OPTION({value: "pike"}, "Pike"),
				]),
				" (Pike backend supports variants, JS backend supports !hostlist command)",
			]),
			type === "variant" && P({class: "no-inherit no-dirty"}, [
				//No inherit and no dirty, this is a selector not a saveable
				LABEL([VS("Select variant:", "Select alert set:"), SELECT({name: "variant"}, OPTION({value: ""}, "Add new"))]),
				BUTTON({type: "button", class: "confirmdelete invisible", title: "Delete"}, "🗑"),
			]),
			//Yeah, this is only for variants, but only NOT for variants. It's for alertset mode only.
			//That's not actually a requirement - both name and description will be saved by the backend
			//for base alerts and variants as well - but they're less useful, so they're currently hidden.
			type === "variant" && P({class: "no-inherit not-variant"}, [
				LABEL(["Name: ", INPUT({name: "name", size: 30})]),
				//LABEL([" Description: ", INPUT({name: "description", size: 60})]), //Might be nice to add this
			]),
			nondef && P([
				LABEL([INPUT({name: "active", type: "checkbox"}), VS(" Alert active", " Alert set active")]), BR(),
				type === "variant"
					? VS("Inactive variants are ignored when selecting which variant to use.",
						"Inactive alert sets effectively deactivate the corresponding alerts.")
					: "Inactive alerts will never be used (nor their variants), but can be inherited from.",
			]),
			HR(),
			nondef && DETAILS({class: "condbox expandbox no-inherit not-alertset"}, [
				SUMMARY(["Alert will be used: ", B({class: "cond-label"}, "always"), ". Expand to configure."]),
				P([
					"If any alert variation is used, the base alert will be replaced with it.",
					type !== "variant" && " Filters here will prevent ANY variation from being used.",
				]),
				//Condition vars depend on the alert type. For instance, a sub alert
				//can check the tier, a cheer alert the number of bits. It's entirely
				//possible to have empty condition_vars, which will just have the
				//standard condition types.
				TABLE({class: "conditions"}, make_condition_vars(info.condition_vars, info.placeholders)),
				P(LABEL(["Only if alert set active: ", SELECT({name: "cond-alertset"}, [
					OPTION({value: ""}, "n/a"),
					(data.alertconfigs.defaults?.variants || [])
						.map(s => OPTION(s)), //Note that this just uses the IDs; they'll be replaced with names shortly.
				])])),
				P([
					LABEL(["Label: ", INPUT({name: "cond-label", size: 30})]),
					LABEL([INPUT({type: "checkbox", name: "cond-disableautogen"}), " Retain (don't autogenerate)"]),
				]),
				//Fully custom conditions. Currently disabled. Do we need them? Would it be
				//better to recommend that people use the full special+builtin system instead?
				/*P(LABEL([
					"Custom numeric condition: ",
					INPUT({name: "cond-numeric", size: 30}),
					" (blank to ignore)",
				])),
				P([
					"Custom text condition: ",
					INPUT({name: "cond-expr1", size: 20}),
					SELECT({name: "cond-type"}, [
						OPTION({value: ""}, "n/a"),
						OPTION({value: "string"}, "is exactly"),
						OPTION({value: "contains"}, "includes"),
						OPTION({value: "regexp"}, "matches regex"),
					]),
					INPUT({name: "cond-expr2", size: 20}),
				]),*/
			]),
			nondef && P({class: "not-alertset"}, [
				LABEL(["Inherit settings from: ", SELECT({name: "parent"},
					Object.entries(alert_definitions).map(([t, x]) =>
						t === "defaults" ? OPTION({value: ""}, "None")
						: t !== "variant" && OPTION({value: t}, x.label)),
				)]),
			]),
			P([
				SELECT({name: "format"}, [
					OPTION({value: "text_image_stacked"}, "Text and image, stacked"),
					OPTION({value: "text_image_overlaid"}, "Text overlaid on image"),
				]),
				LABEL([" Size:", INPUT({name: "alertwidth", type: "number"})]),
				LABEL([" x ", INPUT({name: "alertheight", type: "number"}), " pixels"]),
			]),
			P(LABEL([
				"Layout: ",
				SELECT({name: "layout"}, [OPTION({value: "image_above"}, "Image above"), OPTION({value: "image_below"}, "Image below")]),
			])),
			P([
				LABEL(["Alert length: ", INPUT({name: "alertlength", type: "number", step: "0.5"}), " seconds; "]),
				LABEL(["gap before next alert: ", INPUT({name: "alertgap", type: "number", step: "0.25"}), " seconds"]),
			]),
			nondef && P({class: "not-alertset inheritblock"}, [
				"Image: ",
				IMG({className: "preview", "data-library": "image"}), //Will be replaced with a VIDEO element as needed
				" ",
				BUTTON({type: "button", className: "showlibrary", "data-target": "image", "data-type": "image,video"}, "Choose"),
			]),
			nondef && P({class: "not-alertset inheritblock"}, [
				"Sound: ",
				AUDIO({className: "preview", "data-library": "sound", controls: true}),
				" ",
				BUTTON({type: "button", className: "showlibrary", "data-target": "sound", "data-type": "audio"}, "Choose"),
				LABEL([
					" Volume: ",
					INPUT({name: "volume", type: "range", step: 0.05, min: 0, max: 1}),
					SPAN({className: "rangedisplay"}, ""),
				]),
			]),
			type !== "hostalert" && DETAILS({class: "expandbox"}, [ //Currently, host alerts can't do TTS, since they don't come from the backend.
				SUMMARY("Text-To-Speech settings"),
				TABLE([
					TR({class: "cheer-only"}, [
						//Note that this is hidden when not on the cheer page (or a variant for
						//cheer alerts), but is technically fully functional. Setting this on an
						//alert set would be potentially useful, but only if it's unset on the
						//base cheer alert, and set on the defaults instead. This is UI-confusing
						//but perfectly sane on the back end, so this is UI-hidden rather than
						//being actually server-side blocked. If you understand the implications
						//and want to use the full power of this, go ahead and unhide the fields.
						TD(LABEL({for: type + "-tts_min_bits"}, "Minimum bits for TTS:")),
						TD([
							INPUT({id: type + "-tts_min_bits", name: "tts_min_bits", size: 4}),
							" Cheers smaller than this will ignore text-to-speech",
						]),
					]),
					nondef && TR([
						TD(LABEL({for: type + "-tts_text"}, "Spoken text:")),
						TD([
							INPUT({id: type + "-tts_text", name: "tts_text", size: 40}), BR(),
							"Use ", CODE("{msg}"), " for a cheer or resub message",
						])
					]),
					TR([
						TD("Voice:"),
						TD(SELECT({name: "tts_voice"}, [
							OPTION(),
							avail_voices.map(([label, voices]) =>
								OPTGROUP({label}, voices.map(v => OPTION({value: v.selector}, v.desc)))
							),
						])),
					]),
					TR([TD(LABEL({for: type + "-tts_dwell"}, "Extra time permitted:")), TD(INPUT({id: type + "-tts_dwell", name: "tts_dwell", type: "number"}))]),
					TR(TD({colspan: 2}, [
						"If zero, the alert will stop abruptly and cut off TTS; if longer,", BR(),
						"the alert will be permitted to lengthen to finish the message."
					])),
					TR([
						TD(LABEL({for: type + "-tts_volume"}, "Volume:")),
						TD(LABEL([INPUT({id: type + "-tts_volume", name: "tts_volume", type: "range", step: 0.05, min: 0, max: 1}),
							SPAN({class: "rangedisplay"}, "")])),
					]),
					TR([TD("Filter out"), TD([
						SELECT({name: "tts_filter_emotes"}, [
							OPTION(),
							OPTION({value: "cheers"}, "Cheer emotes"),
							OPTION({value: "emotes"}, "All emotes"),
						]),
						SELECT({name: "tts_filter_badwords"}, [
							OPTION(),
							OPTION({value: "none"}, "No swear filter"),
							OPTION({value: "skip"}, "Exclude bad words"),
							OPTION({value: "replace"}, "Replace bad words"),
							OPTION({value: "message"}, "Bad words prevent TTS"),
						]),
						" (TODO: Custom blocklist)",
					])]),
				]),
			]),
			TEXTFORMATTING({
				textname: nondef ? "textformat" : "-", //FIXME: Hide this when in alertset mode
				textclass: "not-alertset",
				textdesc: SPAN({className: "placeholders"}, placeholder_description),
				blank_opts: nondef, //Add a blank option to selects, but not on the Defaults tab
			}),
			P([
				BUTTON({type: "submit", disabled: true}, "Save"),
				nondef ? BUTTON({type: "button", className: "testalert", "data-type": type}, "Send test alert")
					: BUTTON({type: "button", class: "editvariants"}, "Manage alert sets"),
				type !== "variant" && BUTTON({type: "button", className: "editvariants", "data-type": type}, "Manage alert variants"),
			]),
		]));
		if (type === "variant") DOM("#replaceme").replaceWith(alerttypes.variant);
		load_data(type, { });
	});
	if (selecttab !== null && data.alerttypes && !DOM("input[name=alertselect]:checked")) {
		if (!DOM("#select-" + selecttab))
			//Invalid or not specified? Use the first tab.
			selecttab = document.querySelectorAll("input[name=alertselect]")[0].id.replace("select-", "")
		DOM("#select-" + selecttab).checked = true;
		update_visible_form();
		selecttab = null;
	}
	if (data.alertconfigs) {
		Object.entries(data.alertconfigs).forEach(([type, attrs]) => load_data(type, attrs));
		update_alert_variants();
		const sets = data.alertconfigs.defaults?.variants || [];
		document.querySelectorAll("[name=cond-alertset]").forEach(el => {
			const val = el.value;
			set_content(el, [
				OPTION({value: ""}, "n/a"),
				sets.map(s => OPTION({value: s}, data.alertconfigs[s]["name"] || s))
			]);
			el.value = sets.includes(val) ? val : "";
		});
	}
	if (data.delpersonal) {
		//This isn't part of a normal stateful update, and is a signal that a personal
		//alert has gone bye-bye. Clean up our local state, matching what we'd have if
		//we refreshed the page.
		const type = data.delpersonal;
		alerttypes[type].replaceWith();
		delete alerttypes[type];
		delete revert_data[type];
		DOM("#select-" + type).closest("li").replaceWith();
		document.querySelectorAll("select[name=parent] option[value=" + type + "]").forEach(el => el.replaceWith());
		if (wanted_tab === type) {
			//The currently-selected one got deleted. Switch to the first available.
			document.querySelectorAll("input[name=alertselect]")[0].checked = true;
			update_visible_form();
		}
	}
	//TODO: Migrate this to autorender, but first, have the alertidx come from the server
	if (data.replay) {
		const ofs = data.replay_offset || 0;
		if (!data.replay.length) set_content("#replays", "No events to replay");
		else set_content("#replays", data.replay.map((r,i) => DETAILS([SUMMARY([
			alert_name(r.send_alert),
			" from ",
			r.username || "Anonymous", //Absence of username may indicate a bug.
			" at ",
			new Date(r.alert_timestamp*1000).toLocaleString(),
			" ",
			BUTTON({class: "replayalert", "data-alertidx": i + ofs}, "⟲"),
		]), (replay_details[r.send_alert.split("-")[0]] || replay_details.personal)(r)])));
	}
	if (data.ip_log) {
		if (!ip_history) {ws_sync.send({cmd: "auditlog"}); ip_history = [];} //Only fetch once. Refresh the page if you notice that there's a new IP.
		ip_log = data.ip_log;
		update_ip_log();
	}
	if (data.hostbackend) DOM("select[name=hostbackend]").value = data.hostbackend;
}

on("click", ".replayalert", e => ws_sync.send({cmd: "replay_alert", idx: e.match.dataset.alertidx|0}));

on("change", ".condbox", e => {
	if (e.match.querySelector("[name=cond-disableautogen]").checked) {
		if (e.target.name === "cond-label") update_condition_summary(e.match); //If you edit the label itself, update everything
		return;
	}
	const conds = [];
	const set = e.match.querySelector("[name=cond-alertset]").value;
	if (set) conds.push(revert_data[set]["name"] + " alerts");
	e.match.querySelectorAll("[name^=condoper-]").forEach(el => {
		const val = e.match.querySelector("[name=" + el.name.replace("oper-", "val-") + "]");
		let desc = (val && val.value) || 0;
		if (el.value === ">=") desc += "+"; //eg ">= 100" is shown as "100+"
		else if (el.value === "incl") desc = "incl " + desc; //"text incl Hello"
		else if (el.value === "true") desc = "is"; //"is is_raid"
		else if (el.value === "false") desc = "not"; //"not is_raid"
		else if (el.value !== "==") return; //Condition not applicable
		//Special case: "tier 2" instead of "2 tier"
		if (el.name === "condoper-tier") desc = "tier " + desc;
		//Another special case: "text" gets described differently. FIXME: Don't say "text is incl X"
		else if (el.name === "condoper-text") desc = "text is " + desc;
		else desc += " " + el.name.split("-")[1].replace("is_", ""); //Transform "is/not is_raid" to just "is/not raid"
		conds.push(desc);
	});
	e.match.querySelector("[name=cond-label]").value = conds.join(", ");
	update_condition_summary(e.match);
});

on("input", ".condbox [name=cond-label]", e => e.match.closest(".condbox").querySelector("[name=cond-disableautogen]").checked = true);

on("change", "[name=hostbackend]", e => ws_sync.send({cmd: "config", hostbackend: e.match.value}));

on("click", ".editvariants", e => {
	const type = e.match.closest("form").dataset.type;
	const info = alert_definitions[type];
	set_content("#variationdlg .conditions", make_condition_vars(info.condition_vars, info.placeholders));
	const frm = DOM("#variationdlg form");
	DOM("#variationdlg [name=variant]").value = "";
	frm.classList.remove("unsaved-changes");
	//In alertset mode, some things get redescribed. Choose the wording appropriately.
	frm.classList.toggle("mode-alertset", type === "defaults"); //Hide things that aren't needed for alertsets.
	frm.classList.toggle("mode-variant", type !== "defaults"); //Ditto variants.
	load_data(type + "-", {active: true, parent: type}, frm);
	frm.dataset.type = type + "-";
	wanted_variant = null;
	update_alert_variants();
	DOM("#variationdlg").showModal();
});

let unsaved_form = null, unsaved_clickme = null;
on("change", "[name=variant]", e => select_variant(e.match));
function select_variant(elem) {
	const frm = elem.form;
	if (frm && frm.classList.contains("unsaved-changes")) {
		const orig = elem.value;
		unsaved_form = frm; unsaved_clickme = () => {elem.value = orig; select_variant(elem);};
		set_content("#discarddesc", "Unsaved changes will be lost if you switch to another alert variant.");
		elem.value = frm.dataset.type.split("-")[1];
		DOM("#unsaveddlg").showModal();
		return;
	}
	const type = wanted_tab + "-" + (elem.value || "");
	frm.dataset.type = type;
	wanted_variant = elem.value;
	load_data(type, revert_data[type] || { }, frm);
	elem.value = wanted_variant; //Ensure that the selected variant is still selected, if it exists in the user's settings.
	frm.classList.remove("unsaved-changes"); //Fresh load doesn't count as unsaved changes
	DOM("#variationdlg .testalert").disabled = !wanted_variant || wanted_tab === "defaults";
	frm.querySelector(".confirmdelete").classList.toggle("invisible", !wanted_variant);
}

let wanted_tab = null; //TODO: Allow this to be set from the page fragment (wait till loading is done)
function update_visible_form() {
	wanted_tab = DOM("input[name=alertselect]:checked").value;
	set_content("#selectalert", "#alertconfigs .alertconfig[data-type=" + wanted_tab + "] {display: block;}");
	history.replaceState(null, "", "#" + wanted_tab);
}

function update_layout_options(par, layout) {
	const fmt = par.querySelector("[name=format]").value;
	const opts = {
		text_image_stacked: ["Image above", "Image below"],
		text_image_overlaid: ["Top left", "Top middle", "Top right", "Center left", "Center middle", "Center right", "Bottom left", "Bottom middle", "Bottom right"],
	}[fmt];
	if (!opts) return;
	const el = par.querySelector("[name=layout]");
	if (layout === "") layout = el.layout;
	const kwds = opts.map(o => o.toLowerCase().replace(" ", "_")); //TODO: Deduplicate
	if (!kwds.includes(layout)) layout = kwds[0];
	set_content(el, opts.map(o => OPTION({value: o.toLowerCase().replace(" ", "_")}, o)));
	setTimeout(() => el.value = layout, 1);
}

on("change", "select[name=format]", e => update_layout_options(e.match.closest("form"), ""));

function rangedisplay(el) {
	set_content(el.parentElement.querySelector(".rangedisplay"), Math.floor(el.value * 100) + "%");
	if (el.name === "volume") el.closest("form").querySelector("[data-library=sound]").volume = el.value ** 2;
}
on("input", "input[type=range]", e => rangedisplay(e.match));

function formchanged(e) {
	const frm = e.match.form; if (!frm || !frm.classList.contains("alertconfig")) return;
	if (e.match.closest(".no-dirty")) return;
	frm.classList.add("unsaved-changes"); //Add "dirty" here to colour the entire form
	e.match.classList.add("dirty"); //Can skip this if dirty is applied to the whole form
	e.match.labels.forEach(l => l.classList.add("dirty"));
	const inh = e.match.value === "";
	e.match.classList.toggle("inherited", inh);
	e.match.labels.forEach(l => l.classList.toggle("inherited", inh));
	frm.querySelectorAll("[type=submit]").forEach(el => el.disabled = false);
}
on("input", "input", formchanged); on("change", "input,select", formchanged);

let librarytarget = null;
on("click", ".showlibrary", e => {
	const mode = e.match.dataset.target;
	librarytarget = mode ? e.match.form.querySelector("[data-library=" + mode + "]") : null; //In case there are multiple forms, retain the exact object we're targeting
	let needvalue = !!librarytarget;
	const wanttypes = (e.match.dataset.type || "").split(",");
	for (let el of DOM("#uploads").children) {
		if (!el.dataset.id) continue;
		const want = wanttypes[0] === "" || wanttypes.includes(el.dataset.type.split("/")[0]);
		el.classList.toggle("inactive", !want);
		const rb = el.querySelector("input[type=radio]");
		rb.disabled = !want || wanttypes[0] === "";
		if (needvalue && el.querySelector("a").href === librarytarget.src) {rb.checked = true; needvalue = false;}
	}
	if (needvalue) {
		//Didn't match against any of the library entries.
		if (librarytarget.src === TRANSPARENT_IMAGE) DOM("input[type=radio][data-special=None]").checked = true;
		else if (librarytarget.src.startsWith(FREEMEDIA_BASE)) {
			DOM("input[type=radio][data-special=FreeMedia]").checked = true;
			DOM("#freemediafn").value = librarytarget.src.replace(FREEMEDIA_BASE, "");
		}
		else {
			DOM("input[type=radio][data-special=URL]").checked = true;
			DOM("#customurl").value = librarytarget.src;
		}
	}
	DOM("#library").classList.toggle("noselect", DOM("#libraryselect").disabled = wanttypes[0] === "");
	set_content("#uploaderror", "").classList.add("hidden"); //Clear any lingering error message
	DOM("#library").showModal();
});

//Select radio buttons as appropriate when you manipulate the URL box
DOM("#customurl").onfocus = e => e.target.value !== "" && (DOM("input[type=radio][data-special=URL]").checked = true);
on("input", "#customurl", e => DOM("input[type=radio][data-special=" + (e.target.value !== "" ? "URL" : "None") + "]").checked = true);
DOM("#freemediafn").onfocus = e => e.target.value !== "" && (DOM("input[type=radio][data-special=FreeMedia]").checked = true);
on("input", "#freemediafn", e => DOM("input[type=radio][data-special=" + (e.target.value !== "" ? "FreeMedia" : "None") + "]").checked = true);

//Can the dialog be made into a form and this turned into a submit event? <form method=dialog>
//isn't very well supported yet, so I might have to do some of the work myself. Would improve
//keyboard accessibility though.
on("click", "#libraryselect", async e => {
	if (librarytarget) {
		const rb = DOM("#library input[type=radio]:checked");
		let img = "", type = "";
		if (rb) switch (rb.dataset.special) {
			case "None": break;
			case "URL": {
				img = DOM("#customurl").value;
				try {
					const blob = await (await fetch(img)).blob();
					type = blob.type;
				} catch (e) { } //TODO: Report the error (don't just assume it's a still image)
				break;
			}
			case "FreeMedia": {
				const file = freemedia_files[DOM("#freemediafn").value];
				if (file) {img = file.url; type = file.mimetype;}
				break;
			}
			default:
				img = rb.parentElement.querySelector("a").href;
				type = rb.closest("[data-type]").dataset.type;
		}
		ws_sync.send({cmd: "alertcfg", type: librarytarget.closest(".alertconfig").dataset.type,
			[librarytarget.dataset.library]: img, image_is_video: type.startsWith("video/")});
		const isvid = librarytarget.tagName === "VIDEO", wantvid = type.startsWith("video/");
		if (isvid !== wantvid) librarytarget.replaceWith(wantvid
			? VIDEO({class: "preview", "data-library": "image", src: img, loop: true, ".muted": true, autoplay: true})
			: IMG({class: "preview", "data-library": "image", src: img || TRANSPARENT_IMAGE})
		);
		else librarytarget.src = img || TRANSPARENT_IMAGE;
		const block = librarytarget.closest(".inheritblock");
		if (block) block.classList.toggle("inherited", !img);
		librarytarget = null;
	}
	DOM("#library").close();
});

on("click", "#freemedia", e => {
	const fm = DOM("#library input[type=radio][data-special=FreeMedia]");
	const val = fm.checked ? DOM("#freemediafn").value : "";
	const el = DOM("#freemediadlg input[name=chooseme][value=\"" + val + "\"]") || DOM("#freemedianone");
	el.checked = true;
});

on("click", "#freemediaselect", e => {
	DOM("#freemediadlg").close();
	const rb = DOM("#freemediadlg input[name=chooseme]:checked") || DOM("#freemedianone");
	const fm = DOM("#library input[type=radio][data-special=FreeMedia]");
	if (rb.id === "freemedianone") {
		//If you selected "None" and previously had a Free Media selection, switch to None.
		//Otherwise, leave your previous selection unchanged.
		if (fm.checked) DOM("#library input[data-special=None]").checked = true;
		return;
	}
	fm.checked = true;
	DOM("#freemediafn").value = rb.value;
});

export function sockmsg_uploaderror(msg) {
	set_content("#uploaderror", msg.error || "Unknown upload error, see server log").classList.remove("hidden");
}

on("submit", ".alertconfig", e => {
	e.preventDefault();
	const msg = {cmd: "alertcfg", type: e.match.dataset.type};
	for (let el of e.match.elements) {
		if (el.closest(".mode-alertset .not-alertset")) continue; //TODO: Find a more efficient way to do this
		if (el.closest(".mode-variant .not-variant")) continue;
		if (el.name) msg[el.name] = el.type === "checkbox" ? el.checked : el.value;
	}
	ws_sync.send(msg);
	e.match.classList.remove("unsaved-changes");
});

on("dragstart", "#alertboxlink", e => {
	//TODO: Set the width and height to the (individual) maximums of all alerts, incl defaults
	e.dataTransfer.setData("text/uri-list", `${e.match.href}&layer-name=Host%20Alerts&layer-width=600&layer-height=400`);
});

on("click", "#authpreview", e => {
	if (!have_authkey) ws_sync.send({cmd: "getkey"});
	else DOM("#alertembed").src = DOM("#alertboxlink").href;
	DOM("#previewdlg").showModal();
});
on("click", "#alertboxlabel", e => {
	const inp = DOM("#alertboxdisplay");
	inp.value = DOM("#alertboxlink").href;
	inp.disabled = false;
	inp.select();
});

//Unload the preview when the dialog closes
DOM("#previewdlg").onclose = e => DOM("#alertembed").src = "";

let deletetype = null, deleteid = null;
on("click", "#uploads .confirmdelete", e => {
	deleteid = e.match.closest("[data-id]").dataset.id;
	const file = files[deleteid]; if (!file) return;
	deletetype = "file";
	DOM("#confirmdeletedlg .thumbnail").replaceWith(THUMB(file));
	set_content("#confirmdeletedlg a", file.name).href = file.url;
	document.querySelectorAll(".deltype").forEach(e => e.innerHTML = deletetype);
	set_content("#deletewarning", [
		"Once deleted, this file will no longer be available for alerts, and if", BR(),
		"reuploaded, will have a brand new URL.",
	]);
	DOM("#confirmdeletedlg").showModal();
});

on("click", ".alertconfig .confirmdelete", e => {
	const subid = e.match.form.elements.variant.value; if (subid === "") return; //Button should be hidden when on the "Add New" anyway
	deleteid = e.match.form.dataset.type.split("-")[0] + "-" + subid;
	const alert = revert_data[deleteid]; if (!alert) return;
	deletetype = "variant";
	//TODO: Have an actual thumbnail of the alert, somehow
	DOM("#confirmdeletedlg .thumbnail").replaceWith(P({class: "thumbnail"}, alert["name"] || subid));
	set_content("#confirmdeletedlg a", "");
	document.querySelectorAll(".deltype").forEach(e => e.innerHTML = deletetype);
	set_content("#deletewarning", [
		"Deleting this variant will allow other variants, or the base alert,", BR(),
		"to be used when this one would have.",
	]);
	DOM("#confirmdeletedlg").showModal();
});

on("click", "#delete", e => {
	if (deletetype && deleteid) ws_sync.send({cmd: "delete", type: deletetype, id: deleteid});
	DOM("#confirmdeletedlg").close();
});

on("click", "#unsaved-save,#unsaved-discard", e => {
	DOM("#unsaveddlg").close();
	//Asynchronicity note: There are three timestreams involved in a "save
	//and test" scenario, all independent, but all internally sequenced.
	//1) Here in the editor, we collect form data, then push that out on
	//   the websocket to the server. Then we send the "test alert" message.
	//2) On the server, the "alertcfg" message is received, and configuration
	//   is saved, and pushed out to all clients (including both the editor
	//   and the display). Then the "testalert" message is received, and the
	//   signal goes to the display to send a test alert.
	//3) In the display client, the update from the server is received, and
	//   all changes are immediately applied. Then the alert signal comes in,
	//   and the freshly-updated alert gets fired.
	//So even though we have two separations of asynchronicity, the sequencing
	//of "save, then test" actually still works, so long as requestSubmit() is
	//properly synchronous. (If that's not true on all browsers, just refactor
	//submission into a callable function and do the save directly.)
	if (e.match.id === "unsaved-save") unsaved_form.requestSubmit();
	else {
		const type = unsaved_form.dataset.type;
		unsaved_form.classList.remove("unsaved-changes");
		load_data(type, revert_data[type] || { });
	}
	if (unsaved_clickme.click) unsaved_clickme.click(); else unsaved_clickme();
	unsaved_form = unsaved_clickme = null;
});

const multitest = {tvbase: [], tvall: [], tvactive: []};
on("click", ".testalert", e => {
	const frm = e.match.form;
	if (!frm) {ws_sync.send({cmd: "testalert", type: e.match.dataset.type}); return;}
	if (frm.classList.contains("unsaved-changes")) {
		unsaved_form = frm; unsaved_clickme = e.match;
		set_content("#discarddesc", "Cannot send a test alert with unsaved changes.");
		DOM("#unsaveddlg").showModal();
		return;
	}
	if (!frm.dataset.type.includes("-")) {
		const data = revert_data[frm.dataset.type] || { };
		if (data.variants && data.variants.length) {
			let general = 0, thisset = 0;
			multitest.tvall.length = multitest.tvactive.length = 0;
			multitest.tvbase[0] = frm.dataset.type;
			data.variants.forEach(v => {
				const a = revert_data[v] || { };
				multitest.tvall.push(v); //Should there be any checks to ensure that this is a real alert?
				if (!a.active) return;
				if (!a["cond-alertset"]) {++general; multitest.tvactive.push(v);}
				//else if (a["cond-alertset"] === current-alert-set) {++thisset; multitest_active.push(v);}
			});
			multitest.tvall.push(frm.dataset.type); //Always play the base alert last
			if (!data["cond-alertset"]) {++general; multitest.tvactive.push(frm.dataset.type);}
			//else as above ++thisset
			//if (current-alert-set) set_content("#tvactivedesc", general + " general + " + thisset + " " + current-alert-set + " =");
			/*else*/ set_content("#tvactivedesc", ""+general);
			set_content("#tvalldesc", ""+multitest.tvall.length);
			DOM("#testalertdlg").showModal();
			return;
		}
	}
	ws_sync.send({cmd: "testalert", type: frm.dataset.type});
});

on("click", ".testvariant", e => {
	DOM("#testalertdlg").close();
	const alerts = multitest[e.match.id]; if (!alerts) return;
	alerts.forEach(type => ws_sync.send({cmd: "testalert", type}));
});

on("click", "input[name=alertselect]", e => {
	const frm = DOM(".alertconfig[data-type=" + wanted_tab + "]");
	if (frm && frm.classList.contains("unsaved-changes")) {
		unsaved_form = frm; unsaved_clickme = e.match;
		set_content("#discarddesc", "Unsaved changes will be lost if you switch to another alert type.");
		DOM("#select-" + wanted_tab).checked = true; //Snap back to the other one
		DOM("#unsaveddlg").showModal();
		return;
	}
	update_visible_form();
});

const uploadme = { };
export async function sockmsg_upload(msg) {
	const file = uploadme[msg.name];
	if (!file) return;
	delete uploadme[msg.name];
	const resp = await (await fetch("alertbox?id=" + msg.id, { //The server guarantees that the ID is URL-safe
		method: "POST",
		body: file,
		credentials: "same-origin",
	})).json();
}

on("change", "input[type=file]", e => {
	for (let f of e.match.files) {
		ws_sync.send({cmd: "upload", name: f.name, size: f.size, mimetype: f.type});
		uploadme[f.name] = f;
	}
	e.match.value = "";
});

on("click", ".dlg", e => DOM("#" + e.match.id + "dlg").showModal());
on("click", "#confirmrevokekey", e => {ws_sync.send({cmd: "revokekey"}); DOM("#revokekeydlg").close();});


on("click", "#addpersonal", e => {
	const frm = DOM(".alertconfig[data-type=" + wanted_tab + "]");
	if (frm && frm.classList.contains("unsaved-changes")) {
		unsaved_form = frm; unsaved_clickme = e.match;
		set_content("#discarddesc", "Unsaved changes will be lost if you create another alert type.");
		DOM("#unsaveddlg").showModal();
		return;
	}
	for (let el of DOM("#editpersonal").elements) el.value = "";
	set_content("#savepersonal", "Add");
	DOM("#delpersonal").disabled = true;
	DOM("#personaldlg").showModal();
});

on("click", ".editpersonaldesc", e => {
	const type = e.match.closest("form").dataset.type;
	const elem = DOM("#editpersonal").elements;
	const info = alert_definitions[type];
	for (let kwd in info) {
		if (elem[kwd]) elem[kwd].value = info[kwd];
	}
	elem.id.value = type;
	set_content("#savepersonal", "Save");
	DOM("#delpersonal").disabled = false;
	DOM("#personaldlg").showModal();
});

//TODO: Make a general handler in utils for all form[method=dialog]?
//Would need a data-cmd to bootstrap the message, or alternatively,
//some other type of hook that receives the form and an object of data.
//Maybe even have a "form dialog opening button", the entire thing??
//When it's clicked, it triggers a delayed event upon form submission.
on("submit", "#editpersonal", e => {
	e.preventDefault(); //Can't depend on method=dialog :(
	const msg = {cmd: "makepersonal"}; //Atwix's Legacy?
	for (let el of e.match.elements)
		if (el.name) msg[el.name] = el.type === "checkbox" ? el.checked : el.value;
	ws_sync.send(msg);
	DOM("#personaldlg").close();
});

on("click", "#delpersonal", waitlate(1000, 7500, "Really delete?", e => {
	ws_sync.send({cmd: "delpersonal", id: DOM("#editpersonal").elements.id.value});
	DOM("#personaldlg").close();
}));

on("click", ".renamefile", e => {
	const elem = DOM("#renameform").elements;
	const file = files[e.match.closest("[data-id]").dataset.id];
	if (!file) return;
	DOM("#renamefiledlg .thumbnail").replaceWith(THUMB(file));
	elem.id.value = file.id;
	elem.name.value = file.name;
	DOM("#renamefiledlg").showModal();
});

on("submit", "#renameform", e => {
	e.preventDefault();
	const msg = {cmd: "renamefile"};
	for (let el of e.match.elements)
		if (el.name) msg[el.name] = el.type === "checkbox" ? el.checked : el.value;
	ws_sync.send(msg);
	DOM("#renamefiledlg").close();
});
