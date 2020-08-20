import json
import sys
import time
import itertools
import statistics
import matplotlib.pyplot as plt

if len(sys.argv) < 2:
	print("USAGE: python3 viewers.py channelname", file=sys.stderr)
	sys.exit(1)

with open("twitchbot_status.json") as f: status = json.load(f)
stats = status["stream_stats"][sys.argv[1]]

boundary = time.time() - 86400 * 62 # Take the past year. Or use 31 for a month, or 62 for two months, etc.
boundary = 0 # Or show all available data
max_graph_points = 100
cull_outliers = False # Drop any data points that seem to be outliers (eg front page streams)

stats = [s for s in stats if s["start"] >= boundary]
if cull_outliers:
	# For outlier detection, we just look at the high water mark.
	data = [s["viewers_high"] for s in stats]
	# TODO: Get a more statistically-reliable form of outlier detection
	# This is basically "drop anything more than four standard deviations
	# above the mean", except that we use the median, and if the stdev is
	# greater than the median, we actually drop anything that's more than
	# four medians above the median. It seems to give useful results.
	avg = statistics.median(data)
	basis = min(statistics.stdev(data), avg)
	threshold = avg + 4 * basis
	n = len(stats)
	stats = [s for s in stats if s["viewers_high"] <= threshold]
	dropped = n - len(stats)
	if dropped: print("Discarded", dropped, "probable outliers.")

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
print("From", time.ctime(stats[0]["start"]))
print("To  ", time.ctime(stats[-1]["end"]))
# for s in stats:
#	print("%s %d-%d" % (time.ctime(s["start"]), s["viewers_low"], s["viewers_high"]))
plt.plot([s["viewers_high"] for s in stats])
plt.plot([s["viewers_low"] for s in stats])
plt.show()
