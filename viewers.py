import json
import sys
import time
import itertools
import matplotlib.pyplot as plt

if len(sys.argv) < 2:
	print("USAGE: python3 viewers.py channelname", file=sys.stderr)
	sys.exit(1)

with open("twitchbot_status.json") as f: status = json.load(f)
stats = status["stream_stats"][sys.argv[1]]

boundary = time.time() - 86400 * 62 # Take the past year. Or use 31 for a month, or 62 for two months, etc.
boundary = 0 # Or show all available data
max_graph_points = 100

stats = [s for s in stats if s["start"] >= boundary]
if len(stats) > max_graph_points:
	# Combine some stats together so there are no more than N points
	factor = len(stats) // max_graph_points
	print("Each data point represents %d streams." % (factor + 1))
	it = iter(stats)
	stats = []
	for combined in it:
		for cur in itertools.islice(it, factor):
			combined["end"] = cur["end"]
			combined["viewers_low"] = min(combined["viewers_low"], cur["viewers_low"])
			combined["viewers_high"] = max(combined["viewers_high"], cur["viewers_high"])
		stats.append(combined)
print(len(stats), "data points graphed.")
# for s in stats:
#	print("%s %d-%d" % (time.ctime(s["start"]), s["viewers_low"], s["viewers_high"]))
plt.plot([s["viewers_high"] for s in stats])
plt.plot([s["viewers_low"] for s in stats])
plt.show()
