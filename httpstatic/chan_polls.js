import {lindt, replace_content, on} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, CAPTION, LI, OPTION, SELECT, TABLE, TBODY, TD, TH, THEAD, TIME, TR, UL} = lindt; //autoimport
import {simpleconfirm} from "$$static||utils.js$$";

function format_date(d) {
	const date = new Date(d * 1000);
	return date.toLocaleString(); //Is this useful enough?
}

function DATE(d) {
	if (!d) return "(unknown)";
	const date = new Date(d * 1000);
	let day = date.getDate();
	switch (day) {
		case 1: case 21: day += "st"; break;
		case 2: case 22: day += "nd"; break;
		case 3: case 23: day += "rd"; break;
		default: day += "th";
	}
	return TIME({datetime: date.toISOString(), title: date.toLocaleString()}, [
		//This abbreviated format assumes English and shows just the date. The hover uses your locale.
		"Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(" ")[date.getMonth()] + " " + day,
	]);
}

//Assumes that the duration will be valid for a Twitch poll, 15 <= d <= 1800
//If it isn't, the display may be weird.
function describe_duration(d) {
	if (d < 60) return d + " secs";
	if (d === 60) return "1 min"; //The only singular that's relevant here
	if (d % 60) return Math.floor(d / 60) + ":" + ("0" + (d%60)).slice(-2);
	return d / 60 + " mins";
}

function results_summary(options) {
	const votes = options.toSorted((a, b) => b.votes - a.votes);
	let totvotes = 0; votes.forEach(o => totvotes += o.votes);
	if (!totvotes) return "no votes";
	let ret = [];
	//With five options, this might get quite long - only show the winner and runner-up
	votes.forEach(o => o.votes && ret.length < 2 && ret.push(Math.floor(o.votes * 100 / totvotes) + "% " + o.title));
	return ret.join(", ");
}

let pollresults = { };
function show_poll_results(rslt) {
	if (!rslt) replace_content("#resultdetails", "");
	const opts = rslt.options.toSorted((a, b) => b.votes - a.votes);
	let totvotes = 0; rslt.options.forEach(o => totvotes += o.votes);
	if (!totvotes) totvotes = 1; //If no votes were cast, everything shows as 0%.
	replace_content("#resultdetails", [
		BUTTON({type: "button", class: "pickresult", "data-id": rslt.previd, disabled: !rslt.previd}, "<"),
		TABLE([
			CAPTION(["Poll conducted ", DATE(rslt.completed)]),
			THEAD(TR([TH("Option"), TH("Votes"), TH("Percentage")])),
			TBODY(opts.map(o => TR([
				TD(o.title),
				TD([""+o.votes, o.channel_points_votes && " (" + (o.votes - o.channel_points_votes) + "+" + o.channel_points_votes + ")"]),
				TD(Math.floor(o.votes * 100 / totvotes) + "%"),
			]))),
		]),
		BUTTON({type: "button", class: "pickresult", "data-id": rslt.nextid, disabled: !rslt.nextid}, ">"),
	]);
}

function update_results_view(poll) {
	replace_content("#resultsummary", [
		//Summary of all times this has been asked
		SELECT({id: "pickresults", value: poll.results[poll.results.length - 1]?.id}, [
			poll.results.map(r => OPTION({value: r.id}, [
				poll.results.length > 1 && [ //Differentiate results by date if there are multiple. If multiple on same day, sorry, use the sequence.
					DATE(r.completed), //NOTE: Browsers ignore the element and just include the text. Would be nice to get the hover but so be it.
					" - ",
				],
				results_summary(r.options),
			])),
		]),
	]);
	pollresults = { };
	let lastid = null;
	for (let r of poll.results) {
		pollresults[r.id] = {...r, previd: lastid};
		if (lastid) pollresults[lastid].nextid = r.id;
		lastid = r.id;
	}
	show_poll_results(pollresults[DOM("#pickresults").value]);
}

let selectedpoll = null;
export function render(data) {
	if (!data.polls.length) replace_content("#polls tbody", [TR(TD({colSpan: 8}, "Ask a poll for it to show up here!"))]);
	else replace_content("#polls tbody", data.polls.map((p, idx) => TR({".polldata": p, "data-idx": idx}, [
		TD(DATE(p.created)), TD(DATE(p.lastused)),
		TD(p.title),
		TD(UL(p.options.split("\n").map(o => LI(o)))),
		TD(describe_duration(p.duration)),
		TD(p.points || ""),
		TD(p.results.length && results_summary(p.results[p.results.length - 1].options)),
		TD(BUTTON({class: "delete"}, "X")),
	])));
	//If you have a poll selected, update any results. Should we update everything about it? Might mess with you
	//if you're editing the poll for subsequent usage.
	if (selectedpoll) data.polls.forEach(p => p.title + "\n" + p.options === selectedpoll && update_results_view(p));
}

on("click", "#polls tr[data-idx]", e => {
	const poll = e.match.polldata;
	if (!poll) return;
	const form = DOM("#config").elements;
	selectedpoll = poll.title + "\n" + poll.options;
	form.created.value = format_date(poll.created);
	form.lastused.value = format_date(poll.lastused);
	form.title.value = poll.title;
	form.options.value = poll.options;
	if (!DOM("#duration option[value=\"" + poll.duration + "\"]")) {
		//Note that we never *remove* these, so if you have weird durations, they'll stick around.
		DOM("#duration").append(choc.OPTION({value: poll.duration}, describe_duration(poll.duration)));
	}
	form.duration.value = poll.duration;
	form.points.value = poll.points;
	update_results_view(poll);
});

on("change", "#pickresults", e => show_poll_results(pollresults[e.match.value]));
on("click", ".pickresult", e => show_poll_results(pollresults[DOM("#pickresults").value = e.match.dataset.id]));

on("submit", "#config", e => {
	e.preventDefault();
	const el = DOM("#config").elements;
	const msg = {cmd: "askpoll"};
	"title options duration points".split(" ").forEach(id => msg[id] = el[id].value);
	ws_sync.send(msg);
});

on("click", ".delete", simpleconfirm("Delete this poll?", e => {
	ws_sync.send({cmd: "delpoll", idx: +e.match.closest_data("idx")});
}));
