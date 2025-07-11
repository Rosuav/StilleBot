import Matter from "https://esm.run/matter-js";
import decomp from "https://esm.run/poly-decomp";
Matter.Common.setDecomp(decomp);
const hacks = ws_group === "4OCNIkpnmXUkUF0s0SfmOuKzurlCP6mlwxeM#49497888"; //For testing, sometimes will have special code
//const hacks = false;
const engine = Matter.Engine.create();
const width = window.innerWidth - 20, height = window.innerHeight - 20;
const renderer = Matter.Render.create({element: document.getElementById("display"), engine, options: {
	background: "transparent", width, height,
}});
const Rectangle = Matter.Bodies.rectangle, Circle = Matter.Bodies.circle;
Matter.Render.run(renderer);
Matter.Runner.run(Matter.Runner.create(), engine);
renderer.options.wireframes = false;
window.renderer = renderer; //For debugging, eg toggle wireframes mode

//Map a category ID to the array of things
const thingcategories = { };
//Map category ID to the server-provided information about it
let thingtypes = { };
let fadeouttime = 0, fader = 0;
let wall_config = { }, wall_objects = { };
const clawqueue = []; //If empty, the claw isn't active. If >1 entries, after the current one, the next will autostart.

//Create a body from a set of vertices, where the body's origin is at (0,0) regardless of its centre of mass.
//The object will be placed at the origin.
function body_from_path(path, attrs) {
	const verts = Matter.Vertices.fromPath(path);
	let minx = verts[0].x, miny = verts[0].y;
	verts.forEach(v => {
		if (v.x < minx) minx = v.x;
		if (v.y < miny) miny = v.y;
	});
	const body = Matter.Bodies.fromVertices(0, 0, verts, attrs);
	const mins = body.bounds.min;
	//Re-center the body around the original origin. This involves scanning the vertices to find
	//the minimum (x, y) used, then comparing that to the resultant body's boundary, according to
	//the docs' description of correcting the Center of Mass calculation. Is there a better way
	//(read: simpler way) to do this?
	Matter.Body.setCentre(body, {x: mins.x - minx, y: mins.y - miny});
	Matter.Body.setPosition(body, {x: 0, y: 0});
	return body;
}

function unfade() {
	document.body.classList.remove("invisible");
	clearTimeout(fader);
	if (fadeouttime) fader = setTimeout(() => {fader = 0; document.body.classList.add("invisible")}, fadeouttime * 60000 - 5000);
}

const CLAW = {
	mode: "",
	width: 0,
};
function clawdrop() {
	unfade();
	Matter.Composite.translate(CLAW.claw, {x: Math.random() * (width - CLAW.width * 2) + CLAW.width, y: 5000});
	CLAW.mode = "descend";
}

function reset_claw() {
	Matter.Composite.translate(CLAW.claw, {x: -CLAW.head.position.x, y: -CLAW.head.position.y - 5000}); //Hide it way above the screen
	CLAW.claw.bodies.forEach((c, i) => {
		const loc = CLAW.initial_locations[i];
		Matter.Body.setPosition(c, loc);
		Matter.Body.setAngle(c, loc.angle);
	});
}

const shoulderangle = 0.3; //Fairly flat angle for the fixed part of the arm
const armangle = 0.08; //Initial angles. They will change once we touch something.
const shoulderangle_closed = 0.54, armangle_closed = 0.57; //Angles once the claw has fully closed (should still leave a small gap between the talons)
function create_claw(cfg) {
	if (window.frameElement) return; //Don't enable the claw in preview mode
	//FIXME: Calling this more than once will probably break things. Is currently blocked from re-calling.
	const attrs = {
		isStatic: true,
		render: {fillStyle: cfg.clawcolor || "#71797E", lineWidth: 0},
	};
	CLAW.width = +cfg.clawsize; //TODO: Should this be increased a bit?
	const shoulderlength = +cfg.clawsize, armlength = +cfg.clawsize, talonlength = Math.floor(+cfg.clawsize / 4);
	const thickness = +cfg.clawthickness || 1;
	//The primary body of the claw is its head. Everything else is connected to that.
	//Note that the labels starting "head-" are the ones which, when contacted, will trigger the closing of the claw.
	CLAW.head = Matter.Bodies.fromVertices(0, 0, Matter.Vertices.fromPath("1 -12 8 5 4 10 -4 10 -8 5 -1 -12"), {...attrs, isStatic: true, label: "head-0"});
	CLAW.leftshoulder = Rectangle(-8 - shoulderlength / 2, 5, shoulderlength, thickness * 2, {...attrs, label: "head-1"});
	Matter.Body.setCentre(CLAW.leftshoulder, {x: -8, y: 5});
	Matter.Body.rotate(CLAW.leftshoulder, -shoulderangle);
	CLAW.rightshoulder = Rectangle(+8 + shoulderlength / 2, 5, shoulderlength, thickness * 2, {...attrs, label: "head-2"});
	Matter.Body.setCentre(CLAW.rightshoulder, {x: 8, y: 5});
	Matter.Body.rotate(CLAW.rightshoulder, +shoulderangle);
	const shoulderendx = shoulderlength * Math.cos(shoulderangle), shoulderendy = shoulderlength * Math.sin(shoulderangle);
	//Create an arm+talon combo which has its origin point at the top of the arm
	CLAW.leftarmtalon = body_from_path(`-${thickness} -${thickness} -${thickness} ${armlength+thickness} ${talonlength+thickness} ${armlength+thickness} ${talonlength+thickness} ${armlength-thickness} ${thickness} ${armlength-thickness} ${thickness} -${thickness}`, attrs);
	Matter.Body.rotate(CLAW.leftarmtalon, -armangle);
	Matter.Body.setPosition(CLAW.leftarmtalon, {x: -8 - shoulderendx, y: 5 + shoulderendy});
	CLAW.rightarmtalon = body_from_path(`${thickness} -${thickness} ${thickness} ${armlength+thickness} ${-talonlength-thickness} ${armlength+thickness} ${-talonlength-thickness} ${armlength-thickness} -${thickness} ${armlength-thickness} -${thickness} -${thickness}`, attrs);
	Matter.Body.rotate(CLAW.rightarmtalon, armangle);
	Matter.Body.setPosition(CLAW.rightarmtalon, {x: 8 + shoulderendx, y: 5 + shoulderendy});
	CLAW.claw = Matter.Composite.create({
		bodies: [
			//The head
			CLAW.head,
			//The tail
			Rectangle(0, -1000, thickness * 2, 2000, {...attrs, isStatic: true}),
			//Arms
			CLAW.leftshoulder, CLAW.rightshoulder, CLAW.leftarmtalon, CLAW.rightarmtalon,
			//Origin marker (keep last so it's on top)
			Rectangle(0, 0, 3, 3, {isStatic: true, render: {fillStyle: "#ffff22", lineWidth: 0}}),
		],
	});
	Matter.Composite.translate(CLAW.claw, {x: 0, y: -5000}); //Hide it way above the screen
	CLAW.initial_locations = CLAW.claw.bodies.map(c => ({x: c.position.x, y: c.position.y, angle: c.angle}));
	reset_claw();
	Matter.Composite.add(engine.world, CLAW.claw);
	if (!CLAW.events_created) create_claw_events();
}

function create_claw_events() {
	CLAW.events_created = true;
	const steps = 30;
	Matter.Events.on(engine, "collisionStart", e => CLAW.mode === "descend" && e.pairs.forEach(pair => {
		const isheadA = pair.bodyA.label.startsWith("head-");
		const isheadB = pair.bodyB.label.startsWith("head-");
		if (isheadA !== isheadB) {
			//The head (or shoulder) has touched a thing! Not the armtalon though; if that
			//makes contact, it'll keep pushing, which gives better chances of grabbing.
			//NOTE: If multiple pairs touch in a single frame, this function may be
			//called multiple times. Ensure that it is idempotent. (Spawning multiple
			//timeouts that have the same delay and are themselves idempotent is, in
			//effect, idempotent.)
			CLAW.mode = ""; setTimeout(() => {CLAW.closing = steps; CLAW.mode = "close"}, 500);
		}
	}));
	//Each step, we rotate the shoulder a little, and then the arm a little beyond that.
	//Since the arm gets rotated around the shoulder too, the arm's own step is reduced
	//to compensate. Otherwise it would get double the rotation.
	Matter.Events.on(engine, "afterUpdate", e => {switch (CLAW.mode) {
		case "descend":
			Matter.Composite.translate(CLAW.claw, {x: 0, y: 2});
			//If we hit the floor, the collision check won't detect it, so just close below the surface and pull up.
			if (CLAW.head.position.y >= height) {CLAW.mode = ""; setTimeout(() => {CLAW.closing = steps; CLAW.mode = "close"}, 500);}
			break;
		case "close": {
			//To close the claws, we droop the shoulders slightly and then
			//bring the arm-talon pairs in. This involves rotating both the
			//shoulders and the arm-talons by the shoulder rotation, and
			//then rotating the arm-talons alone by the arm rotation.

			//As the step counter descends from steps to zero, the angles
			//should gently curve from their initial to final values. This
			//is done with a cosine curve starting at -pi and going to zero,
			//yielding positions from -1 to 1; rescaling this to be from 0
			//to 1 makes them into a fraction of the delta.
			--CLAW.closing;
			const pos = Math.cos((-CLAW.closing / steps) * Math.PI) / 2 + 0.5; //From zero to one
			const shouldergoal = shoulderangle + (shoulderangle_closed - shoulderangle) * pos;
			const armgoal = armangle + (armangle_closed - armangle) * pos;
			const shoulderstep = shouldergoal - CLAW.rightshoulder.angle;
			Matter.Body.rotate(CLAW.leftshoulder, -shoulderstep);
			Matter.Body.rotate(CLAW.rightshoulder, shoulderstep);
			Matter.Body.rotate(CLAW.leftarmtalon, -shoulderstep, {x: CLAW.leftshoulder.position.x, y: CLAW.leftshoulder.position.y});
			Matter.Body.rotate(CLAW.rightarmtalon, shoulderstep, {x: CLAW.rightshoulder.position.x, y: CLAW.rightshoulder.position.y});
			const armstep = armgoal - CLAW.rightarmtalon.angle;
			Matter.Body.rotate(CLAW.leftarmtalon, -armstep);
			Matter.Body.rotate(CLAW.rightarmtalon, armstep);
			if (!CLAW.closing) {
				CLAW.mode = ""; setTimeout(() => CLAW.mode = "ascend", 500);
			}
			break;
		}
		case "ascend":
			Matter.Composite.translate(CLAW.claw, {x: 0, y: -1});
			if (CLAW.head.position.y < -100) {
				CLAW.mode = "";
				//See what's above the screen. Note that there might be more than one thing,
				//but we'll only claim one prize (chosen arbitrarily).
				let prize = null, prizetype = "";
				engine.world.bodies.forEach(body => body.position.y < 0 && (prize = body));
				if (prize) {
					for (let thingtype in thingcategories) {
						const things = thingcategories[thingtype];
						things.forEach((thing, idx) => {
							if (thing.id === prize.id) {things.splice(idx, 1); prizetype = thingtype;}
						});
					}
					Matter.Composite.remove(engine.world, prize);
				}
				const clawid = clawqueue.shift(); //TODO: Have an autoretry option, which will skip shifting the queue if there was no prize.
				if (clawid) ws_sync.send({cmd: "clawdone", prizetype, label: prize?.label, clawid});
				reset_claw();
				if (clawqueue.length) setTimeout(clawdrop, 2000);
			}
			break;
	}});
}

const addxtra = { };

//For a given color eg #663399 and alpha eg 100, return an eight digit hex color. Note that alpha is in the range 0-100.
function hexcolor(color, alpha) {
	return (color || "#000000") + ("0" + Math.floor((alpha || 0) * 2.55 + 0.5).toString(16)).slice(-2);
}

export function render(data) {
	if (data.data) { //Odd name but this is the primary reconfiguration
		if (data.data.fadeouttime) fadeouttime = +data.data.fadeouttime;
		if (data.data.things) thingtypes = Object.fromEntries(data.data.things.map(t => [t.id, t]));
		renderer.options.background = hexcolor(data.data.bgcolor, data.data.bgalpha);
		//If the floor dimension changes, recreate the walls as well. Otherwise, only recreate what's changed.
		//(Usually that'll be nothing. Changing the walls and floor is unusual.)
		const wallcolor = hexcolor(data.data.wallcolor, data.data.wallalpha);
		const floor_changed = data.data.wall_floor !== wall_config.floor
			|| wallcolor !== wall_config.color;
		for (let side of ["floor", "left", "right"]) {
			if (data.data["wall_" + side] !== wall_config[side] || floor_changed) {
				wall_config[side] = data.data["wall_" + side];
				if (wall_objects[side]) {
					Matter.Composite.remove(engine.world, wall_objects[side]);
					delete wall_objects[side];
				}
			}
		}
		//The walls should have some thickness to them, to prevent weird bouncing. At 2px, there's a lot of bouncing;
		//even at 10px there's occasional issues. However, thicker walls look weird if the floor isn't 100% size.
		const wall_thickness = 95 < +wall_config.floor ? 60 : 10;
		//The need fields are 0 if no recreation is needed, or a percentage eg 50% to create a half-size wall.
		const need_floor = !wall_objects.floor && +wall_config.floor;
		const need_left = !wall_objects.left && +wall_config.left;
		const need_right = !wall_objects.right && +wall_config.right;
		const floor_size = width * +wall_config.floor / 200 + wall_thickness / 2 - 2;
		if (need_floor) Matter.Composite.add(engine.world,
			wall_objects.floor = Rectangle(width / 2, height + 28, width * need_floor / 100 + 10, 60,
				{isStatic: true, render: {fillStyle: wallcolor, lineWidth: 0}}));
		if (need_left) Matter.Composite.add(engine.world,
			wall_objects.left = Rectangle(width / 2 - floor_size, height - height * need_left / 200, wall_thickness, height * need_left / 100 + 10,
				{isStatic: true, render: {fillStyle: wallcolor, lineWidth: 0}}));
		if (need_right) Matter.Composite.add(engine.world,
			wall_objects.right = Rectangle(width / 2 + floor_size, height - height * need_right / 200, wall_thickness, height * need_right / 100 + 10,
				{isStatic: true, render: {fillStyle: wallcolor, lineWidth: 0}}));
		if (+data.data.clawsize) create_claw(data.data);
	}
	if (data.addxtra) addxtra[data.addxtra] = data.xtra;
	if (data.newcount) Object.entries(data.newcount).forEach(([thingtype, newcount]) => {
		const cat = thingtypes[thingtype];
		if (!cat) return;
		if (!thingcategories[thingtype]) thingcategories[thingtype] = [];
		const things = thingcategories[thingtype];
		while (things.length > newcount) Matter.Composite.remove(engine.world, things.pop());
		while (things.length < newcount) {
			const xtra = addxtra[thingtype] || { }; delete addxtra[thingtype];
			const img = xtra.image || cat.images[Math.floor(Math.random() * cat.images.length)] || default_thing_image;
			const scale = cat.xsize / img.xsize;
			const attrs = {
				render: {sprite: {
					texture: img.url,
					xOffset: img.xoffset || 0, yOffset: img.yoffset || 0,
					xScale: scale, yScale: scale, 
				}},
				restitution: 0.25, //Make 'em a little bit bouncier
			};
			if (xtra.label) attrs.label = "label-" + xtra.label; //Force a prefix so we can do hit-detection based on label category
			let obj;
			switch (cat.shape) {
				case "circle": obj = Circle(
					Math.floor(Math.random() * (width - cat.xsize - 30) + cat.xsize / 2 + 15),
					Math.floor(Math.random() * 100 + 10),
					cat.xsize / 2, //Our idea of xsize is width, so the radius is half that
					attrs);
				break;
				default: obj = Rectangle(
					Math.floor(Math.random() * (width - cat.xsize - 30) + cat.xsize / 2 + 15),
					Math.floor(Math.random() * 100 + 10),
					cat.xsize, Math.ceil(img.ysize * scale),
					attrs);
			}
			if (img.hull && img.hull.length >= 4) {
				const verts = Matter.Vertices.create(img.hull.map(([x, y]) => ({x, y})), obj);
				obj = Matter.Bodies.fromVertices(obj.position.x, obj.position.y, Matter.Vertices.hull(verts), attrs);
				Matter.Body.scale(obj, scale, scale);
			}
			//Angles are measured in radians. Angular velocity seems to be rad/frame and we're at
			//60Hz physics rate, meaning that 0.01 will rotate you by 0.60 rad/sec (before friction is
			//taken into account). Provide each newly-added element with a bit of rotation, either direction.
			Matter.Body.setAngularVelocity(obj, Math.random() * .2 - .1);
			Matter.Composite.add(engine.world, obj);
			things.push(obj);
			//A new thing has been added! Make the pile visible.
			unfade();
		}
	});
	if (data.claw && CLAW.claw) {
		clawqueue.push(data.claw);
		if (clawqueue.length === 1) clawdrop();
	}
	if (data.remove) {
		//Remove one of a thingtype, choosing based on label
		const things = thingcategories[data.remove];
		if (!things) return;
		for (let i = 0; i < things.length; ++i) {
			const thing = things[i];
			if (thing.label !== "label-" + data.label) continue;
			ws_sync.send({cmd: "removed", thingtype: data.remove, label: thing.label});
			Matter.Composite.remove(engine.world, thing);
			things.splice(i, 1);
			return;
		}
	}
}
ws_sync.send({cmd: "querycounts"});

//Demo mode? Emote dropping mode?
if (0) setInterval(() => {
	const cat = thingtypes.emotes; //TODO: User selection from the available categories
	if (!cat) return;
	const img = cat[Math.floor(Math.random() * cat.length)];
	const obj = Rectangle(Math.floor(Math.random() * width), Math.floor(Math.random() * 100 + 10), img.xsize, img.ysize, {
		render: {sprite: {texture: img.url, xOffset: img.xoffset, yOffset: img.yoffset}},
	});
	//Angles are measured in radians. Angular velocity seems to be rad/frame and we're at
	//60Hz physics rate, meaning that 0.01 will rotate you by 0.60 rad/sec (before friction is
	//taken into account). Provide each newly-added element with a bit of rotation, either direction.
	Matter.Body.setAngularVelocity(obj, Math.random() * .2 - .1);
	Matter.Composite.add(engine.world, obj);
}, 2000);
//TODO: Handle things dropping past the floor? Would need to remove them and signal the server to decrement the count.
//Might need to be governed by a broadcaster control.
