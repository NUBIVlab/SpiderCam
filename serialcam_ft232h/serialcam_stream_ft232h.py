#!/usr/bin/env python3

import ftd2xx as ft
import time
import sys
import numpy as np

from collections import deque

import os
import threading
import queue

import argparse

# New: Import PyQt for our GUI display
from PyQt5 import QtWidgets, QtGui, QtCore

# Import from our utils file in the same dir
from serialcam_stream_utils_ft232h import *
from serialcam_ft232h_dialogs import *

import colormaps

def execute(args):
    # Manually instantiate magic bytes
    magic_bytes = b'BIVFRAME'

    # Initialize objects shared between threads
    # rx side
    rx_binary_queue = queue.Queue()
    rx_stream_queue = queue.Queue()
    rx_channel_queues = []
    for _ in range(args.maxchannels):
        rx_channel_queues.append(queue.Queue())

    # tx side
    tx_binary_queue = queue.Queue()
    
    # Recording Utility 
    recorder_request_queue = queue.Queue()
    recorder_queues = []
    for _ in range(args.maxchannels):
        recorder_queues.append(queue.Queue())
    
    # Each channel gets a display window
    # The central channel controls the tx_binary_queue
    app = QtWidgets.QApplication([])
    app.setQuitOnLastWindowClosed(True)
    window = ImageDisplayWindow(args.maxchannels, rx_channel_queues, recorder_request_queue, tx_binary_queue, args.fast)

    # FT232 Threads
    ft232h_thread = threading.Thread(target=ft232h,
                                     args=(rx_binary_queue, tx_binary_queue, args.ftdi_sn_prefix.encode('utf-8'), args.fast),
                                     daemon=True) 
    # binary decoder
    binary_decoder = BinaryDecoder(rx_binary_queue, rx_stream_queue, magic_bytes)
    binary_decoder_thread = threading.Thread(target=binary_decoder.run,
                                             daemon=True)

    # stream decoder
    stream_decoder = StreamDecoder(rx_stream_queue, rx_channel_queues, window, recorder_queues, recorder_request_queue, args.fast)
    stream_decoder_thread = threading.Thread(target=stream_decoder.run,
                                             daemon=True)

    # Starting All Threads
    ft232h_thread.start()
    binary_decoder_thread.start()
    stream_decoder_thread.start()

    # Run the Qt displays in the main thread.
    window.show()
    app.exec_()

if __name__ == '__main__':
    descstr = "Capture and stream video coming from our FPGA dev board over the high-speed FT232H connection."
    parser = argparse.ArgumentParser(description=descstr)
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=480)
    parser.add_argument("--scale", type=int, default=2)
    parser.add_argument("--maxchannels", type=int, default=2)
    parser.add_argument("--centralchannel", type=int, default=0)
    parser.add_argument("--ftdi_sn_prefix", type=str, default="fsplit")
    parser.add_argument("--fast", type=int, default=False)
    args = parser.parse_args()
    execute(args)

    