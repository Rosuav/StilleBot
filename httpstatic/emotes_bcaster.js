import {choc, set_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {H2, H3, IMG, INPUT, LABEL} = choc; //autoimport

set_content("#sections", emoteset_order.map(setid => LABEL([
	INPUT({type: "checkbox", name: setid, checked: true}),
	" " + emoteset_labels[setid].trim(),
])));

function update_preview() {
	const sections = [];
	const include_headings = DOM("#headings").checked;
	const size = +DOM("#imgsize").value;
	const hdg = DOM("#heading").value.trim();
	if (hdg !== "") sections.push(H2(hdg));
	document.querySelectorAll("#sections input:checked").forEach(el => {
		const setid = el.name;
		if (include_headings) sections.push(H3(emoteset_labels[setid]));
		sections.push(emotes_by_set[setid].map(id => IMG({
			crossOrigin: "anonymous", //Allow the use of these images in canvas without tainting it
			"src": "https://static-cdn.jtvnw.net/emoticons/v2/" + id + "/static/light/" + size + ".0",
		})));
	});
	set_content("#captureme", sections);
}

on("click", "#opencapturedlg", e => {
	update_preview();
	DOM("#capturedlg").showModal();
});
on("click", "#capturedlg input[type=checkbox]", update_preview);
on("change", "#capturedlg input,#capturedlg select", update_preview);

on("click", "#capture", e => {
	const target = DOM("#captureme");
	console.log("CAPTURE", target);
	const box = target.getBoundingClientRect();
	const canvas = choc.CANVAS({width: box.width|0, height: box.height|0});
	const ctx = canvas.getContext("2d");
	//ctx.fillStyle = "#f7f7f7"; //TODO: Offer dark mode as well, and maybe offer transparency (skip the fillRect)
	//ctx.fillRect(0, 0, canvas.width, canvas.height);
	target.querySelectorAll("img").forEach(img => {
		ctx.drawImage(img, img.offsetLeft, img.offsetTop);
	});
	//To quickly see the image:
	//target.insertAdjacentElement("afterend", choc.IMG({src: canvas.toDataURL(), style: "width: " + box.width + "px; height: " + box.height + "px"}));
	canvas.toBlob(blob => {
		choc.A({href: URL.createObjectURL(blob), download: "emotes.png"}).click();
	});
});
