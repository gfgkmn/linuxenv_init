#!/usr/bin/env ipython

import sys
import subprocess
import xml.etree.ElementTree

cmd = ["nvidia-smi", "-q", "-x"]
cmd_out = subprocess.check_output(cmd)
gpus = xml.etree.ElementTree.fromstring(cmd_out).findall("gpu")
infos = {}
for idx, gpu in enumerate(gpus):
    if idx < 4:
        # only used gpu is calculated
        pname = "cuda:%d" % idx
        total = float(gpu.find("fb_memory_usage/total").text.split(" ")[0])
        used = float(gpu.find("fb_memory_usage/used").text.split(" ")[0])
        if used < 20:
            sys.exit(0)
print("True")
