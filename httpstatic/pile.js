const hacks = ws_group === "4OCNIkpnmXUkUF0s0SfmOuKzurlCP6mlwxeM#49497888";
const engine = Matter.Engine.create();
const width = window.innerWidth - 20, height = window.innerHeight - 20;
//NOTE: For debugging and testing, background and fillStyle are both colours. For
//production, they should be transparent, with actual elements for interaction purposes.
const visible_walls = hacks;
const renderer = Matter.Render.create({element: document.getElementById("display"), engine, options: {
	background: visible_walls ? "aliceblue" : "transparent", width, height,
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
let wall_sizes = { }, wall_objects = { };

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

if (hacks) {
	console.log("Hacks mode enabled");
	const attrs = {
		isStatic: true,
		render: {fillStyle: "#71797E", lineWidth: 0},
	};
	const shoulderlength = 60, armlength = 60, talonlength = 15; //TODO: Make configurable (maybe as a single size, rather than separate lengths)
	const shoulderangle = 0.3; //Fairly flat angle for the fixed part of the arm
	const armangle = 0.08; //Initial angles. They will change once we touch something.
	const shoulderangle_closed = 0.54, armangle_closed = 0.57; //Angles once the claw has fully closed (should still leave a small gap between the talons)
	//The primary body of the claw is its head. Everything else is connected to that.
	//Note that the labels starting "head-" are the ones which, when contacted, will trigger the closing of the claw.
	const head = Matter.Bodies.fromVertices(0, 0, Matter.Vertices.fromPath("1 -12 8 5 4 10 -4 10 -8 5 -1 -12"), {...attrs, isStatic: true, label: "head-0"});
	const leftshoulder = Rectangle(-8 - shoulderlength / 2, 5, shoulderlength, 2, {...attrs, label: "head-1"});
	Matter.Body.setCentre(leftshoulder, {x: -8, y: 5});
	Matter.Body.rotate(leftshoulder, -shoulderangle);
	const rightshoulder = Rectangle(+8 + shoulderlength / 2, 5, shoulderlength, 2, {...attrs, label: "head-2"});
	Matter.Body.setCentre(rightshoulder, {x: 8, y: 5});
	Matter.Body.rotate(rightshoulder, +shoulderangle);
	const shoulderendx = shoulderlength * Math.cos(shoulderangle), shoulderendy = shoulderlength * Math.sin(shoulderangle);
	//Create an arm+talon combo which has its origin point at the top of the arm
	const leftarmtalon = body_from_path(`-1 -1 -1 ${armlength+1} ${talonlength+1} ${armlength+1} ${talonlength+1} ${armlength-1} 1 ${armlength-1} 1 -1`, attrs);
	Matter.Body.rotate(leftarmtalon, -armangle);
	Matter.Body.setPosition(leftarmtalon, {x: -8 - shoulderendx, y: 5 + shoulderendy});
	const rightarmtalon = body_from_path(`1 -1 1 ${armlength+1} ${-talonlength-1} ${armlength+1} ${-talonlength-1} ${armlength-1} -1 ${armlength-1} -1 -1`, attrs);
	Matter.Body.rotate(rightarmtalon, armangle);
	Matter.Body.setPosition(rightarmtalon, {x: 8 + shoulderendx, y: 5 + shoulderendy});
	const claw = Matter.Composite.create({
		bodies: [
			//The head
			head,
			//The tail
			Rectangle(0, -1000, 2, 2000, {...attrs, isStatic: true}),
			//Arms
			leftshoulder, rightshoulder, leftarmtalon, rightarmtalon,
			//Origin marker (keep last so it's on top)
			Rectangle(0, 0, 3, 3, {isStatic: true, render: {fillStyle: "#ffff22", lineWidth: 0}}),
		],
	});
	Matter.Composite.translate(claw, {x: 0, y: -5000}); //Hide it way above the screen
	const initial_locations = claw.bodies.map(c => ({x: c.position.x, y: c.position.y, angle: c.angle}));
	function reset_claw() {
		Matter.Composite.translate(claw, {x: -head.position.x, y: -head.position.y - 5000}); //Hide it way above the screen
		claw.bodies.forEach((c, i) => {
			const loc = initial_locations[i];
			Matter.Body.setPosition(c, loc);
			Matter.Body.setAngle(c, loc.angle);
		});
	}
	reset_claw();
	Matter.Composite.add(engine.world, claw);
	let mode = "";
	setTimeout(() => {
		Matter.Composite.translate(claw, {x: Math.random() * (width - shoulderlength * 2) + shoulderlength, y: 5000});
		mode = "descend";
	}, 1000);
	const steps = 30;
	let closing = 0;
	Matter.Events.on(engine, "collisionStart", e => mode === "descend" && e.pairs.forEach(pair => {
		const headA = pair.bodyA.label.startsWith("head-");
		const headB = pair.bodyB.label.startsWith("head-");
		if (headA !== headB) {
			//The head has touched a thing! Note that this could be the armtalon part,
			//if it strikes something and bounces up. Not sure what to do about that.
			//NOTE: If multiple pairs touch in a single frame, this function may be
			//called multiple times. Ensure that it is idempotent. (Spawning multiple
			//timeouts that have the same delay and are themselves idempotent is, in
			//effect, idempotent.)
			mode = ""; setTimeout(() => {closing = steps; mode = "close"}, 500);
		}
	}));
	//Each step, we rotate the shoulder a little, and then the arm a little beyond that.
	//Since the arm gets rotated around the shoulder too, the arm's own step is reduced
	//to compensate. Otherwise it would get double the rotation.
	Matter.Events.on(engine, "afterUpdate", e => {switch (mode) {
		case "descend": Matter.Composite.translate(claw, {x: 0, y: 2}); break;
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
			--closing;
			const pos = Math.cos((-closing / steps) * Math.PI) / 2 + 0.5; //From zero to one
			const shouldergoal = shoulderangle + (shoulderangle_closed - shoulderangle) * pos;
			const armgoal = armangle + (armangle_closed - armangle) * pos;
			const shoulderstep = shouldergoal - rightshoulder.angle;
			Matter.Body.rotate(leftshoulder, -shoulderstep);
			Matter.Body.rotate(rightshoulder, shoulderstep);
			Matter.Body.rotate(leftarmtalon, -shoulderstep, {x: leftshoulder.position.x, y: leftshoulder.position.y});
			Matter.Body.rotate(rightarmtalon, shoulderstep, {x: rightshoulder.position.x, y: rightshoulder.position.y});
			const armstep = armgoal - rightarmtalon.angle;
			Matter.Body.rotate(leftarmtalon, -armstep);
			Matter.Body.rotate(rightarmtalon, armstep);
			if (!closing) {
				mode = ""; setTimeout(() => mode = "ascend", 500);
			}
			break;
		}
		case "ascend":
			Matter.Composite.translate(claw, {x: 0, y: -1});
			if (head.position.y < -100) {
				mode = "";
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
				ws_sync.send({cmd: "clawdone", prizetype, label: prize?.label});
				reset_claw();
				//Autoretry. TODO: Have a mode for "retry until prize won"?
				setTimeout(() => {
					Matter.Composite.translate(claw, {x: Math.random() * (width - shoulderlength * 2) + shoulderlength, y: 5000});
					mode = "descend";
				}, 2000);
			}
			break;
	}});
}

export function render(data) {
	if (data.data) {
		if (data.data.fadeouttime) fadeouttime = +data.data.fadeouttime;
		if (data.data.things) thingtypes = Object.fromEntries(data.data.things.map(t => [t.id, t]));
		//If the floor dimension changes, recreate the walls as well. Otherwise, only recreate what's changed.
		//(Usually that'll be nothing. Changing the walls and floor is unusual.)
		let floor_changed = data.data.wall_floor !== wall_sizes.floor;
		for (let side of ["floor", "left", "right"]) {
			if (data.data["wall_" + side] !== wall_sizes[side] || floor_changed) {
				wall_sizes[side] = data.data["wall_" + side];
				if (wall_objects[side]) {
					Matter.Composite.remove(engine.world, wall_objects[side]);
					delete wall_objects[side];
				}
			}
		}
		//The walls should have some thickness to them, to prevent weird bouncing. At 2px, there's a lot of bouncing;
		//even at 10px there's occasional issues. However, thicker walls look weird if the floor isn't 100% size.
		const wall_thickness = 95 < +wall_sizes.floor ? 60 : 10;
		//The need fields are 0 if no recreation is needed, or a percentage eg 50% to create a half-size wall.
		const need_floor = !wall_objects.floor && +wall_sizes.floor;
		const need_left = !wall_objects.left && +wall_sizes.left;
		const need_right = !wall_objects.right && +wall_sizes.right;
		const floor_size = width * +wall_sizes.floor / 200 + wall_thickness / 2 - 2;
		if (need_floor) Matter.Composite.add(engine.world,
			wall_objects.floor = Rectangle(width / 2, height + 28, width * need_floor / 100 + 10, 60,
				{isStatic: true, render: {fillStyle: visible_walls ? "rebeccapurple" : "transparent", lineWidth: 0}}));
		if (need_left) Matter.Composite.add(engine.world,
			wall_objects.left = Rectangle(width / 2 - floor_size, height - height * need_left / 200, wall_thickness, height * need_left / 100 + 10,
				{isStatic: true, render: {fillStyle: visible_walls ? "rebeccapurple" : "transparent", lineWidth: 0}}));
		if (need_right) Matter.Composite.add(engine.world,
			wall_objects.right = Rectangle(width / 2 + floor_size, height - height * need_right / 200, wall_thickness, height * need_right / 100 + 10,
				{isStatic: true, render: {fillStyle: visible_walls ? "rebeccapurple" : "transparent", lineWidth: 0}}));
	}
	if (data.newcount) Object.entries(data.newcount).forEach(([thingtype, newcount]) => {
		const cat = thingtypes[thingtype];
		if (!cat) return;
		if (!thingcategories[thingtype]) thingcategories[thingtype] = [];
		const things = thingcategories[thingtype];
		while (things.length > newcount) Matter.Composite.remove(engine.world, things.pop());
		while (things.length < newcount) {
			const img = cat.images[Math.floor(Math.random() * cat.images.length)] || default_thing_image;
			const scale = cat.xsize / img.xsize;
			const attrs = {
				render: {sprite: {
					texture: img.url,
					//xOffset: cat.xoffset || 0, yOffset: cat.yoffset || 0, //Not currently configured on the back end
					xScale: scale, yScale: scale, 
				}},
				restitution: 0.25, //Make 'em a little bit bouncier
			};
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
			//Angles are measured in radians. Angular velocity seems to be rad/frame and we're at
			//60Hz physics rate, meaning that 0.01 will rotate you by 0.60 rad/sec (before friction is
			//taken into account). Provide each newly-added element with a bit of rotation, either direction.
			Matter.Body.setAngularVelocity(obj, Math.random() * .2 - .1);
			Matter.Composite.add(engine.world, obj);
			things.push(obj);
			//A new thing has been added! Make the pile visible.
			document.body.classList.remove("invisible");
			clearTimeout(fader);
			if (fadeouttime) fader = setTimeout(() => {fader = 0; document.body.classList.add("invisible")}, fadeouttime * 60000 - 5000);
		}
	});
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
//TODO: If stable mode is selected, then after adding something, set a quarter-second interval timer to
//check the newly created thing's speed, and if it's low enough, setStatic() on it.
//Alternatively, set everything to Sleeping? Wake them up when something new is added?
/* Next steps:

* Create an object type ("category", need a good name for it)
* Upload an image for an object type - may be done more than once. If not done, will use Mustard Mine squavatar.
* Builtin to manipulate objects
  - Needs a type. Will only manipulate objects of that type.
  - Add N (default to 1), remove N (default to 1), or set to N on screen
    - "+1", "-1", "1"?
* Handle objects falling off the bottom?
* On the edit dlg, button to add/remove objects given a type

*/
