import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {FIGCAPTION, FIGURE, H2, H3, IMG, INPUT, LABEL} = choc; //autoimport

set_content("#sections", emoteset_order.map(setid => LABEL([
	INPUT({type: "checkbox", name: setid, checked: true}),
	" " + emoteset_labels[setid].trim(),
])));

function slugify(setid) {
	//Return a short reference for a set ID. Currently uses the initials of the label,
	//since "F", "T1", "B", etc are all good labels.
	return emoteset_labels[setid].split(" ").map(w => w[0]).join("");
}

const panelparams = new URLSearchParams(location.hash.slice(1));

const bg_color = {none: "transparent", light: "#f7f7f7", dark: "#0e0c13"};

let dragging = null; //If non-null, is the ID of the emote currently being dragged
let moved = false; //True once the dragged emote has been moved (even just a pixel, even if moved back)
let dragset = null, dragorigin = -1; //Where the dragged emote came from

const render_emote = {
	none(id, size, setid, caption) {
		let cls = "";
		if (id === dragging && moved) {
			//We're dragging this one around. Note that the array has been mutated to show the
			//target position, and the original position is saved for the Esc key to restore it to.
			cls = "dragging";
		}
		return FIGURE({"data-id": id, "data-set": setid, class: cls}, [
			IMG({
				crossOrigin: "anonymous", //Allow the use of these images in canvas without tainting it
				"src": "https://static-cdn.jtvnw.net/emoticons/v2/" + id + "/static/light/" + size + ".0",
			}),
			caption,
		]);
	},
	long(id, size, setid, name) {
		return render_emote.none(id, size, setid,
			FIGCAPTION({class: "size" + size}, name || emote_names[id]),
		);
	},
	short(id, size, setid) {
		let name = emote_names[id];
		if (name.startsWith(emote_prefix)) name = name.slice(emote_prefix.length);
		return render_emote.long(id, size, setid, name);
	},
}

//HACK! Make the text white when on a dark background. Can we do this automatically somehow?
const text_for_bg = {
	dark: "#f7f7f7",
};

function update_preview() {
	const sections = [];
	const include_headings = DOM("#headings").checked;
	panelparams.set("sec", +include_headings);
	const size = +DOM("#imgsize").value;
	panelparams.set("sz", size);
	const hdg = DOM("#heading").value.trim();
	if (hdg !== "") sections.push(H2(hdg));
	panelparams.set("hdg", hdg);
	const make_emote = render_emote[DOM("#emotenames").value];
	panelparams.set("names", DOM("#emotenames").value);
	let sets = [];
	document.querySelectorAll("#sections input:checked").forEach(el => {
		const setid = el.name;
		sets.push(slugify(setid));
		if (include_headings) sections.push(H3(emoteset_labels[setid]));
		sections.push(emotes_by_set[setid].map(id => make_emote(id, size, setid)));
	});
	panelparams.set("sets", sets.join(" "));
	DOM("#captureme").classList.remove("no_ellipsis");
	const bg = DOM("#background").value;
	panelparams.set("bg", bg);
	set_content("#captureme", sections).style.backgroundColor = bg_color[bg];
	DOM("#captureme").style.color = text_for_bg[bg] || null;
	panelparams.set("long", DOM("#longnames").value);
	switch (DOM("#longnames").value) {
		case "shrink":
			//See if any of the captions are getting ellipsized, and if so, shrink them.
			//This is unideal but I don't know of a better way to do this.
			//We attempt the size reduction in steps, and at some point, just give up and
			//let it ellipsize.
			["80%", "60%", "40%"].forEach(size => {
				document.querySelectorAll("#captureme figcaption").forEach(el => {
					if (el.offsetWidth < el.scrollWidth)
						el.style.fontSize = size;
				});
			});
			break;
		case "retain":
			DOM("#captureme").classList.add("no_ellipsis");
			break;
		case "ellipsize": default: break;
	}
	history.replaceState(null, "", "#" + panelparams.toString());
}

//Apply all current panel params (only if we have a fragment with content in it)
if (location.hash.length >= 2) {
	function param_to_dom(el, kwd) {
		const val = panelparams.get(kwd);
		if (val !== null) el[el.type === "checkbox" ? "checked" : "value"] = val;
	}
	param_to_dom(DOM("#headings"), "sec");
	param_to_dom(DOM("#imgsize"), "sz");
	param_to_dom(DOM("#heading"), "hdg");
	param_to_dom(DOM("#emotenames"), "names");
	const sets = panelparams.get("sets");
	if (sets !== null) {
		const want = {};
		sets.split(" ").forEach(s => want[s] = true);
		document.querySelectorAll("#sections input").forEach(el => {
			el.checked = want[slugify(el.name)] || false;
		});
	}
	param_to_dom(DOM("#background"), "bg");
	param_to_dom(DOM("#longnames"), "long");
	update_preview();
	DOM("#capturedlg").showModal();
}
DOM("#capturedlg").onclose = e => history.replaceState(null, "", " ");

on("click", "#opencapturedlg", e => {
	update_preview();
	DOM("#capturedlg").showModal();
});
on("click", "#capturedlg input[type=checkbox]", update_preview);
on("change", "#capturedlg input,#capturedlg select", update_preview);

on("click", "#capture", e => {
	const target = DOM("#captureme");
	const box = target.getBoundingClientRect();
	const canvas = choc.CANVAS({width: box.width|0, height: box.height|0});
	const ctx = canvas.getContext("2d");
	const bg = DOM("#background").value
	if (bg !== "none") {
		ctx.fillStyle = bg_color[bg];
		ctx.fillRect(0, 0, canvas.width, canvas.height);
	}
	target.querySelectorAll("img").forEach(img => {
		ctx.drawImage(img, img.offsetLeft, img.offsetTop);
	});
	ctx.fillStyle = text_for_bg[bg] || "black";
	ctx.textBaseline = "top"; //Measure text from the top left, not the baseline - lets us use DOM measurement for pixel positions
	target.querySelectorAll("h2,h3,figcaption").forEach(hdg => {
		let text = hdg.innerText;
		const styles = getComputedStyle(hdg);
		ctx.font = styles.font;
		while (ctx.measureText(text).width > hdg.offsetWidth + 1) {
			//Text is too wide. (Note that we grant one extra pixel of leeway as otherwise we get odd unnecessary ellipsization.)
			text = text.slice(0, -2) + "…";
		}
		ctx.fillText(text, hdg.offsetLeft + (hdg.offsetWidth - ctx.measureText(text).width) / 2, hdg.offsetTop);
	});
	//To quickly see the image:
	//target.closest(".twocol").append(choc.IMG({src: canvas.toDataURL(), style: "width: " + box.width + "px; height: " + box.height + "px"}));
	canvas.toBlob(blob => {
		choc.A({href: URL.createObjectURL(blob), download: "emotes.png"}).click();
	});
});

//All pointer events will get targeted here. Using pointer capture with Choc on() doesn't work properly,
//as the event is attached to document; maybe it would work to capture pointer to document, but then we
//still need to do all the real work ourselves.
const dragtop = DOM("#captureme");
let pointerid = null;
dragtop.addEventListener("pointerdown", e => {
	if (e.button) return; //Only left clicks
	dragging = e.target.closest_data("id");
	dragset = e.target.closest_data("set");
	//Can only drag when there's at least two to reorder. Sorry affiliates and your tiered emotes.
	if (!emotes_by_set[dragset] || emotes_by_set[dragset].length < 2) {dragging = null; return;}
	dragorigin = emotes_by_set[dragset].indexOf(dragging);
	dragtop.setPointerCapture(pointerid = e.pointerId);
	moved = false;
	//Note that we don't update_preview here; there's no visual change until the first movement.
	e.preventDefault();
});
dragtop.addEventListener("pointermove", e => {
	if (!dragging) return;
	let curpos = emotes_by_set[dragset].indexOf(dragging);
	const target = document.elementFromPoint(e.clientX, e.clientY);
	if (!target) return;
	const dropdest = target.closest_data("id"), dropset = target.closest_data("set");
	if (!dropset) return; //Probably dropping onto the background somewhere; leave the emote where it is for now.
	let destidx = 0;
	if (dropset !== dragset) {
		//If you drag something past its own set, it will "lock" at the extreme of the set
		//If you dragged forwards, lock at the end. I don't really care if weird things
		//happen with failed indexOf searches, it'll still be at one end or the other.
		if (emoteset_order.indexOf(dropset) > emoteset_order.indexOf(dragset))
			destidx = emotes_by_set[dragset].length;
	} else {
		//Within the set, dropping "on" an item means either dropping to its left or its right.
		destidx = emotes_by_set[dragset].indexOf(dropdest);
		const bounds = target.getBoundingClientRect();
		if (e.clientX > (bounds.left + bounds.right) / 2) {
			//If we're on the right hand half of the target, drop to the right of this one.
			++destidx;
		}
	}
	//Remove the previous slot that this held, and put it instead at the new index.
	const set = emotes_by_set[dragset].map(el => el === dragging ? null : el); //Suppress the previous one (without altering indices)
	set.splice(destidx, 0, dragging); //Insert at the new position
	emotes_by_set[dragset] = set.filter(el => el); //And remove the null from the first step.
	if (!moved || destidx != curpos) {moved = true; update_preview();}
});
dragtop.addEventListener("pointerup", e => {
	dragging = null;
	dragtop.releasePointerCapture(e.pointerId);
	update_preview();
});
document.addEventListener("keydown", e => {
	if (dragging && e.code === "Escape") {
		e.preventDefault();
		//Reset the dragged emote to its original position.
		emotes_by_set[dragset] = emotes_by_set[dragset].filter(el => el !== dragging); //Remove it from whereever it now is
		emotes_by_set[dragset].splice(dragorigin, 0, dragging);
		dragging = null;
		dragtop.releasePointerCapture(pointerid);
		update_preview();
	}
});
