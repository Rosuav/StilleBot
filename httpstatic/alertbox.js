import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {AUDIO, DIV, FIGCAPTION, FIGURE, IMG, P, SECTION, VIDEO} = choc; //autoimport
import "https://cdn.jsdelivr.net/npm/comfy.js/dist/comfy.min.js"; const ComfyJS = window.ComfyJS;
import {ensure_font} from "$$static||utils.js$$";

const TRANSPARENT_IMAGE = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNgAAIAAAUAAen63NgAAAAASUVORK5CYII=";
const EMPTY_AUDIO = "data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEARKwAAIhYAQACABAAZGF0YQAAAAA=";

function img_or_video(data) {
	if (!data.image_is_video) return IMG({class: "mainimg", src: data.image || TRANSPARENT_IMAGE});
	const el = VIDEO({class: "mainimg", src: data.image, preload: "auto", loop: true});
	el.muted = true;
	return el;
}

const alert_formats = {
	text_image_stacked: data => FIGURE({
		className: "text_image_stacked " + (data.layout||""),
		style: `width: ${data.alertwidth}px; max-height: ${data.alertheight}px;`,
	}, [
		img_or_video(data),
		FIGCAPTION({"data-textformat": data.textformat, style: data.text_css || ""}, data.textformat),
		AUDIO({preload: "auto", src: data.sound || EMPTY_AUDIO, volume: data.volume ** 2}),
	]),
	text_image_overlaid: data => DIV(
		{
			//The layout might be "top_middle", but in CSS, we can handle each dimension
			//separately, so apply classes of "top middle" instead :)
			className: "text_image_overlaid " + (data.layout||"").replace("_", " "),
			style: `width: ${data.alertwidth}px; height: ${data.alertheight}px;`,
		}, [
			DIV({class: "boundingbox", style: `width: ${data.alertwidth}px; height: ${data.alertheight}px;`}, img_or_video(data)),
			DIV({"data-textformat": data.textformat, style: data.text_css || ""}, data.textformat),
			AUDIO({preload: "auto", src: data.sound || EMPTY_AUDIO, volume: data.volume ** 2}),
		]
	),
};

//Timings:
//1) Alert length is the time that the alert is visible, measured from the
//   start of its fade-in to the start of its fade-out.
//2) Fade-in and fade-out are visual effects only; opacity grows/shrinks
//   over time to smooth things out. Keep these short.
//3) Alert gap is the time after the start of fade-out before another alert
//   will be shown. It should be greater than the fade-out, to avoid ugly
//   "snap back to full" visuals.
//4) An animated alert with a period exactly equal to alert_length + fade-out
//   will run once, then disappear. A period half of that will cycle twice etc.
//5) An audio clip shorter than alert_length + alert_gap will leave silence.
//   Longer than that will skip the audio on stacked alerts. Recommend aiming
//   to keep it roughly as long as the alert, no more, no less.
//6) A long alert_gap will result in weird waiting periods between alerts. A
//   short alert_gap will have alerts coming hard on each other's heels.

let inited = false, token = null;
let hostlist_command = null, hostlist_format = null;
const alert_active = { };
const retainme = ["alertlength", "alertgap", "tts_dwell", "tts_volume"];
export function render(data) {
	if (data.version > alertbox_version) {location.reload(); return;}
	if (data.alertconfigs) {
		for (let kwd in data.alertconfigs) {
			const cfg = data.alertconfigs[kwd];
			if (cfg.version > alertbox_version) {location.reload(); return;}
			let elem = DOM("#" + kwd);
			if (!elem) elem = DOM("main").appendChild(SECTION({className: "alert", id: kwd})); //New alert type
			if (alert_formats[cfg.format]) set_content(elem, alert_formats[cfg.format](cfg));
			else set_content(elem, P("Unrecognized alert format '" + cfg.format + "', check editor or refresh page"));
			alert_active["#" + kwd] = cfg.active;
			for (let attr of retainme)
				elem.dataset[attr] = cfg[attr];
			ensure_font(cfg.font);
		}
		const removeme = [];
		document.querySelectorAll("main > section").forEach(el => !data.alertconfigs[el.id] && removeme.push(el));
		removeme.forEach(el => el.replaceWith()); //Do all the removal after the checks, to avoid trampling on things
	}
	if (data.send_alert) do_alert("#" + data.send_alert, data);
	if (data.token && data.token !== token) {
		if (inited) ComfyJS.Disconnect();
		inited = true;
		token = data.token;
		if (token !== "!demo") ComfyJS.Init(ws_group.split("#")[1], data.token);
	}
	if (data.breaknow) {
		//Token has been revoked. This will be the last message we receive
		//on the websocket. Clean up some resources rather than waiting around.
		ComfyJS.Disconnect();
	}
	if (data.hostlist_command) hostlist_command = data.hostlist_command;
	if (data.hostlist_format) hostlist_format = data.hostlist_format;
}

setTimeout(() => {
	if (inited) return; //All good!
	set_content("#hostalert", P("No login token provided - check configuration or refresh page"));
}, 5000);

const alert_queue = [];
let alert_playing = false;

function next_alert() {
	alert_playing = false;
	let next = alert_queue.shift();
	//If you disable an alert while there are a bunch of them queued, they
	//remain in the queue until they would have been displayed, at which
	//point they get dropped. This is unlikely to matter as there's currently
	//no way to see the queue, but if one is ever added, it may be worth
	//hiding any that are inactive.
	while (next && !alert_active[next[0]]) next = alert_queue.shift();
	if (next) do_alert(...next);
}

function remove_alert(alert, gap) {
	DOM(alert).classList.remove("active");
	DOM(alert).querySelectorAll("video,audio").forEach(el => el.pause());
	DOM("#tts").pause();
	setTimeout(next_alert, gap * 1000);
}

function render_emoted_text(txt) {
	if (typeof txt === "string") return txt;
	if (Array.isArray(txt)) return txt.map(render_emoted_text);
	if (txt.img) return IMG({src: txt.img, alt: txt.title, title: txt.title});
	return "<ERROR> Unknown text format: " + Object.keys(txt);
}

function do_alert(alert, replacements) {
	if (!replacements.test_alert && !alert_active[alert]) return;
	if (alert_playing) {alert_queue.push([alert, replacements]); return;}
	alert_playing = true;
	const elem = DOM(alert);
	elem.querySelectorAll("[data-textformat]").forEach(el =>
		set_content(el, el.dataset.textformat.split(/{([^}]+)}/).map((kwd,i) => {
			if (i&1) { //1st, 3rd, 5th are all braced keywords
				if (kwd === "msg") kwd = replacements._emoted || replacements.msg;
				else kwd = replacements[kwd];
				return render_emoted_text(kwd || "");
			}
			return kwd; //0th, 2nd, 4th etc are all literal text
		}))
	);
	//Force animations and videos to restart
	elem.querySelectorAll("img").forEach(el => el.src = el.src);
	elem.querySelectorAll("video").forEach(el => {el.currentTime = 0; el.play();});
	const alertlength = +elem.dataset.alertlength;
	let alerttimeout = null;
	if (replacements.tts) {
		const maxlength = alertlength + +elem.dataset.tts_dwell;
		const len = elem.querySelector("audio").duration;
		if (len < maxlength) {
			//Start TTS playing after the main audio finishes
			const tts = DOM("#tts");
			tts.src = replacements.tts;
			tts.volume = (+elem.dataset.tts_volume) ** 2;
			setTimeout(() => tts.play(), len * 1000);
			//Potentially increase the alert length up to the maxlength
			//Since the TTS content comes from a string, we assume that it will
			//load quickly - not instantly (it's still asynchronous), but fast
			//enough that we don't have to compensate for the delay. The alert
			//length will be counted from this event.
			tts.ondurationchange = e => {
				const reallen = Math.min(alertlength + tts.duration, maxlength);
				clearTimeout(alerttimeout);
				setTimeout(remove_alert, reallen * 1000, alert, elem.dataset.alertgap);
				tts.ondurationchange = null;
			};
		}
	}
	elem.classList.add("active");
	let playing = false;
	//If the page is in the background, don't play audio.
	if (!document.hidden) document.querySelectorAll("audio").forEach(a => {if (!a.paused) playing = true;});
	if (!playing) elem.querySelector("audio").play();
	alerttimeout = setTimeout(remove_alert, alertlength * 1000, alert, elem.dataset.alertgap);
}
window.ping = type => do_alert("#" + (type || "hostalert"), {NAME: "Test", username: "Test", VIEWERS: 42, viewers: 42, test_alert: 1});

const current_hosts = { };
ComfyJS.onHosted = (username, viewers, autohost, extra) => {
	//Note that ComfyJS itself never seems to announce autohosts. It also
	//doesn't provide the displayname, so we fall back on the username.
	if (current_hosts[username]) return;
	current_hosts[username] = 1;
	console.log("HOST:", username, viewers, autohost, extra);
	do_alert("#hostalert", {NAME: username, VIEWERS: viewers, username, viewers});
};

ComfyJS.onCommand = (user, command, message, flags, extra) => {
	if (!hostlist_command || !hostlist_format || command !== hostlist_command) return;
	if (!flags.broadcaster && !flags.mod) return;
	const hosts = Object.keys(current_hosts);
	ComfyJS.Say(hostlist_format.replace("{count}", hosts.length).replace("{hosts}", hosts.join(", ")));
};
