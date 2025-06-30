import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {FIGCAPTION, FIGURE, H2, H3, IMG, INPUT, LABEL} = choc; //autoimport

set_content("#sections", emoteset_order.map(setid => LABEL([
	INPUT({type: "checkbox", name: setid, checked: true}),
	" " + emoteset_labels[setid].trim(),
])));

const render_emote = {
	none(id, size) {
		return IMG({
			crossOrigin: "anonymous", //Allow the use of these images in canvas without tainting it
			"src": "https://static-cdn.jtvnw.net/emoticons/v2/" + id + "/static/light/" + size + ".0",
		});
	},
	long(id, size, name) {
		return FIGURE([
			render_emote.none(id, size),
			FIGCAPTION({class: "size" + size}, name || emote_names[id]),
		]);
	},
	short(id, size) {
		let name = emote_names[id];
		if (name.startsWith(emote_prefix)) name = name.slice(emote_prefix.length);
		return render_emote.long(id, size, name);
	},
}

//HACK! Make the text white when on a dark background. Can we do this automatically somehow?
const text_for_bg = {
	"#0e0c13": "#f7f7f7",
};

function update_preview() {
	const sections = [];
	const include_headings = DOM("#headings").checked;
	const size = +DOM("#imgsize").value;
	const hdg = DOM("#heading").value.trim();
	if (hdg !== "") sections.push(H2(hdg));
	const make_emote = render_emote[DOM("#emotenames").value];
	document.querySelectorAll("#sections input:checked").forEach(el => {
		const setid = el.name;
		if (include_headings) sections.push(H3(emoteset_labels[setid]));
		sections.push(emotes_by_set[setid].map(id => make_emote(id, size)));
	});
	DOM("#captureme").classList.remove("no_ellipsis");
	const bg = DOM("#background").value;
	set_content("#captureme", sections).style.backgroundColor = bg;
	DOM("#captureme").style.color = text_for_bg[bg] || null;
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
}

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
	if (bg !== "transparent") {
		ctx.fillStyle = bg;
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
