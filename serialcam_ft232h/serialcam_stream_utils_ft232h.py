
import ftd2xx as ft
import time
import sys
import numpy as np
import cv2
from collections import deque
import queue
from serialcam_ft232h_dialogs import *
import colormaps
import math
from live_image_viewer import LiveImageViewer
import matplotlib.pyplot as plt
plt.ion()
plt.show(block=False)

def printhex(arr):
    hex_vals = [f"{val:02x}" for val in arr]
    for i in range(0, len(hex_vals), 8):
        print(" ".join(hex_vals[i:i+8]))

# BIG-ENDIAN, combine bytes
def combine_bytes(np_arr, data_width):
    cols = np_arr.shape[1]
    shifts = data_width * np.arange(cols - 1, -1, -1)  # e.g., [24, 16, 8, 0] for 4 bytes
    return np_arr.astype(int) @ (1 << shifts)

def tile_arrays(arrays, fill_value=0):
    """
    Take a list of 2D NumPy arrays (same shape) and tile them
    into a square grid. Empty slots are filled with fill_value.
    """
    if not arrays:
        return None

    h, w = arrays[0].shape
    n = len(arrays)
    grid_size = math.ceil(math.sqrt(n))

    # Create big array initialized with fill_value
    big = np.full((grid_size * h, grid_size * w), fill_value, dtype=arrays[0].dtype)

    for idx, arr in enumerate(arrays):
        row = idx // grid_size
        col = idx % grid_size
        big[row*h:(row+1)*h, col*w:(col+1)*w] = arr

    return big



# Sends and Recieves binary data from FT232h chip
def ft232h(rx_binary_queue, tx_binary_queue, sn_prefix=b'fsplit', fast=0):
    # Find the ftdi device to open
    try:
        devlist = ft.listDevices()
        print(f"Read Thread: Found FT232H devices with the following serial numbers:")
        print(devlist)
        matching_sns = [sn for sn in devlist if (sn.startswith(sn_prefix))]
        if (len(matching_sns) == 0):
            print(f"Read Thread: Couldn't find an FT232H board with a serial number starting with {sn_prefix}")
            sys.exit(-1)
        else:
            ftdev_id = devlist.index(matching_sns[0])
            print(f"Read Thread: Choosing device number {ftdev_id} with serial number {matching_sns[0]}")
    except ValueError:
        raise Exception("Read Thread: No board found!")

    # open and configure the device
    print("Read Thread: Opening device")
    ftdev = ft.open(ftdev_id)
    print("Read Thread: resetting device")
    ftdev.resetDevice()
    print("Read Thread: setting modes")
    ftdev.setBitMode(0xff, 0x00)
    if(fast):
        ftdev.setTimeouts(5,5)
    else:
        ftdev.setTimeouts(100,100)  # in ms
    
    ftdev.setUSBParameters(24 * 1024, 24 * 1024)  # set rx, tx buffer size in bytes
    ftdev.setFlowControl(ft.defines.FLOW_RTS_CTS, 0, 0)

    # Read data
    stats = DataRateStats()
    last_printed_time = time.time()
    STATS_PRINT_RATE = 5
    while True:
        # Try to read from the ft232; send the resulting data to stream decoder thread
        chunk = ftdev.read(1024 * 1024)
        rx_binary_queue.put(chunk)
        # update data reading stats
        stats.register_bytes_read(len(chunk))
        # Check tx_binary queue to see if we need to send data
        try:
            txdata = tx_binary_queue.get_nowait()
            print(f"sending {txdata} to FPGA")
            ftdev.write(txdata)
        except queue.Empty as e:
            pass
            

        # print data rate if we havent printed in a little bit
        if ((time.time() - last_printed_time) > STATS_PRINT_RATE):
            data_rate, total_datas = stats.get_results()
            print(f"Read Thread: reading data at {data_rate/1e6:6.2f}MB/s. {total_datas/1e6:8.2}MB so far")
            last_printed_time = time.time()

# Form complete frames (streams) from the rx_binary_queue
class BinaryDecoder:
    def __init__(self, rx_binary_queue, rx_stream_queue, magic_bytes):
        self.magic_bytes        = magic_bytes
        self.magic_bytes_np     = np.frombuffer(magic_bytes, dtype=np.uint8)
        
        self.rx_binary_queue    = rx_binary_queue
        self.rx_stream_queue    = rx_stream_queue
        
        # Header Info stored in BIG-ENDIAN (wrt to array index, meaning,
        # low index is MSB and high index is LSB) then passed as metadata:
        # [width, height, channels, data_width]
        self.width           = 0 ## 2 bytes
        self.height          = 0 ## 2 bytes
        self.channels        = 0 ## 1 byte
        self.data_width      = 0 ## 1 byte -- data width in number of BITS
        self.magic_bytes_len_np = len(self.magic_bytes_np)
        # includes width, height and data_width bytes (2 + 2 + 1 + 1 = 6)
        self.magic_bytes_len_total_np = self.magic_bytes_len_np + 6
   
    def run(self):
        rx_binary_acc_np = np.empty((0,), dtype=np.uint8)
        mb_len       = self.magic_bytes_len_np
        mb_len_total = self.magic_bytes_len_total_np
        while True:
            rx_binary_np = np.frombuffer(self.rx_binary_queue.get(), dtype=np.uint8)
            rx_binary_acc_np = np.concatenate((rx_binary_acc_np, rx_binary_np))
            matching_indices = self.find_magic_bytes(rx_binary_acc_np)
            # we have a full frame, send as a tuple (header_info, data)
            # then remove it from the accumulator
            if(len(matching_indices) > 1):
                stream = np.array(rx_binary_acc_np[matching_indices[0]+mb_len_total:matching_indices[1]],copy=True)
                self.rx_stream_queue.put(
                    ([self.width, self.height, self.channels, self.data_width],
                     stream))
                rx_binary_acc_np = rx_binary_acc_np[matching_indices[1]:]
    
    def find_magic_bytes(self, rx_binary_np_acc):
        mb_len       = self.magic_bytes_len_np
        mb_len_total = self.magic_bytes_len_total_np
        candidates = np.flatnonzero(rx_binary_np_acc == self.magic_bytes_np[0])
        matching_indices = []
        for i in candidates:
            if (i + mb_len_total) > len(rx_binary_np_acc):
                break
            if np.array_equal(rx_binary_np_acc[i : i + mb_len], self.magic_bytes_np):
                width_msb  = rx_binary_np_acc[i + mb_len + 0]
                width_lsb  = rx_binary_np_acc[i + mb_len + 1]
                height_msb = rx_binary_np_acc[i + mb_len + 2]
                height_lsb = rx_binary_np_acc[i + mb_len + 3]   
                self.width      = (int(width_msb) << 8) + int(width_lsb)
                self.height     = (int(height_msb) << 8) + int(height_lsb)
                self.channels   = rx_binary_np_acc[i + mb_len + 4]
                self.data_width = rx_binary_np_acc[i + mb_len + 5]
                matching_indices.append(i)
        return matching_indices
    
# Form complete channels by seperating out of the streams (frames)
# do this using the header info, the data does not include the header
# as it is passed separately as such:
# ([width, height, channels, data_width], data_np)
# data is stored as BIG-ENDIAN
#
# Since this is only synchronized place to record frames, the
# StreamDecoder also has the job of recording frames.
#
# It also has the additional job of recording the fps stats.
class StreamDecoder:
    def __init__(self, rx_stream_queue, rx_channel_queues, window, recorder_queues, recorder_request_queue, fast=False):
        self.rx_stream_queue        = rx_stream_queue
        self.rx_channel_queues      = rx_channel_queues
        self.window                 = window
        self.fast = fast
        # Recording related
        self.recorder_queues = recorder_queues
        self.recorder_request_queue = recorder_request_queue
        self.remaining = 0
        self.several_frames_requested = False
        self.output_dir = ''
        self.base_filename = ''
        self.unique_id = 0

        # Recording FPS stats
        self.last_time = time.time()
        
    def run(self):
        while True:
            rx_stream_pkg = self.rx_stream_queue.get()
            rx_stream_header_info = rx_stream_pkg[0]
            rx_stream_np          = rx_stream_pkg[1]
            width      = rx_stream_header_info[0]
            height     = rx_stream_header_info[1]
            channels   = rx_stream_header_info[2]
            data_width = rx_stream_header_info[3]
            # try seeing if there is a record request and perform
            # some setup
            try:
                req = None
                req = self.recorder_request_queue.get_nowait()
                self.setup_record_request(req)
            except:
                pass
            try:
                # first group uint8s into their own items
                rx_stream_np = rx_stream_np.reshape(-1, data_width // 8)
                # then combine each bytes parcel into one int using BIG-ENDIAN
                rx_stream_np = combine_bytes(rx_stream_np, data_width)
  
                for c in range(channels):
                    # splice each channel according to how many channels there 
                    channel = np.array(rx_stream_np[c::channels], copy=True)
                    # then reshape into the appropriate width and height
                    channel = channel.reshape(height, width)
                    # make continguous array
                    channel = np.ascontiguousarray(channel)
                    # are and add it to the rx_channel_queues, with header info too
                    # threw in a small crop too
                    # if fast, cropping a 490x450 image:
                    if self.fast:
                        self.rx_channel_queues[c].put(
                            ([width, height, channels, data_width],
                            channel[0:400, 0:480]))
                    else:
                        self.rx_channel_queues[c].put(
                            ([width, height, channels, data_width],
                            channel[15:415, 5:485]))
                    
                    # If recording is active, we should push it to the 
                    # recording queues too
                    if(self.remaining > 0):
                        self.recorder_queues[c].put(
                            ([width, height, channels, data_width],
                             channel))
                        
                # Process one group of capture        
                if(self.remaining > 0):
                    self.step_record_request([width, height, channels, data_width])

                # calculate FPS stat
                now = time.time()
                dt = now - self.last_time
                self.last_time = now
                fps = 1.0 / dt if dt > 0 else 0.0
                fps_str = f"FPS: {fps:.2f}"

                # Finally for the window, we have to emit the signal to update the display
                # and pass the fps stat
                self.window.new_image_received.emit()
                self.window.statusBar().showMessage(fps_str)
                
            except Exception as e:
                print(e)
                print("Malformed Stream Detected!")

    def setup_record_request(self, req):
        if(req == None): # means a req was previously passed and processing
            return
        self.remaining = req["frames"]

        if(self.remaining < 2):
            self.several_frames_requested = False
        else:
            self.several_frames_requested = True
        
        file_path = req["filename"].split("/")
        
        if(req["filename"] == ""):
            self.output_dir =  ""
            self.base_filename = "default"
        elif(len(file_path) == 1):
            self.output_dir = file_path[0]
            self.base_filename = "default"
        else:
            self.output_dir = ('/').join(file_path[:-1])
            self.base_filename = file_path[-1]

        os.makedirs(self.output_dir, exist_ok=True)

    def step_record_request(self, header_info):
        filename = self.output_dir + '/' + self.base_filename 
        self.remaining -= 1

        width      = header_info[0]
        height     = header_info[1]
        channels   = header_info[2]
        data_width = header_info[3]

        # For now, we save the npy and uint8 converted version
        for c in range(channels):
            channel_pkg = self.recorder_queues[c].get()
            channel_int_np = channel_pkg[1]

            if(self.several_frames_requested):
                #np.save(filename + "_" + str(c) + "_" + str(width) + "_" + str(height) + "_"  + str(self.remaining) + "_" + str(self.unique_id) + "_int.npy",channel_int_np)

                # uint8 png
                channel_uint8_np = (channel_int_np >> (data_width - 8)).astype(np.uint8)
                cv2.imwrite(filename + "_" + str(c) + "_" + str(width) + "_" + str(height) + "_" + str(self.remaining) + "_" + str(self.unique_id) + ".png",channel_uint8_np)
            else:
                #np.save(filename + "_" + str(c)  + "_" + str(width) + "_" + str(height) + "_" + str(self.unique_id) + "_int.npy",channel_int_np)

                # uint8 png
                channel_uint8_np = (channel_int_np >> (data_width - 8)).astype(np.uint8)
                cv2.imwrite(filename + "_" + str(c) + "_" + str(width) + "_" + str(height) + "_"  + str(self.unique_id) + ".png",channel_uint8_np)

            
        self.unique_id += 1
        return

class DataRateStats:
    def __init__(self, window_ms=1000):
        """
        :param window_ms: The time window (in milliseconds) over which to calculate the moving average.
        """
        self.window_ms = window_ms
        self.history = deque()
        self.total_bytes = 0

    def register_bytes_read(self, num_bytes):
        """
        Update internal stats with the number of bytes just read.
        """
        now = time.time() * 1000
        self.history.append((now, num_bytes))
        self.total_bytes += num_bytes

        # Remove samples older than the time window
        while self.history and self.history[0][0] < now - self.window_ms:
            self.history.popleft()

    def get_results(self):
        """
        Returns a tuple containing the average number of datas read in the last second
        and the total number of datas read overall.
        """
        # Sum bytes within the current window.
        bytes_in_window = sum(item[1] for item in self.history)

        # Determine the effective window time.
        if self.history:
            effective_window_ms = (time.time() * 1000) - self.history[0][0]
        else:
            effective_window_ms = self.window_ms

        # Avoid division by zero.
        if effective_window_ms > 0:
            data_rate = (bytes_in_window / (effective_window_ms / 1000.0))
        else:
            data_rate = 0.0

        return (data_rate, self.total_bytes)
    
# This class displays recieved data in a qt window.
# Images are passed in through the 'image_queue'; whenever something pushes to the image queue, a
# redraw should be manually requested through the
#     window.new_image_received.emit()
# Signal
class ImageDisplayWindow(QtWidgets.QMainWindow):
    new_image_received = QtCore.pyqtSignal()
    capture_settings: dict = None
    image_scale: float = 1.0
    color_map: str = "gray"      # "gray" or "color"

    def __init__(self, maxchannels, image_queue, command_queue, write_command_queue, fast=False, parent=None):
        """
        this window reads numpy arrays from image_queue containing images to display.
        Commands are sent from 'command_queue' to the different interface threads (the ft232
        reader thread and image decoder thread) in response to user actions.
        """
        super().__init__(parent)

        self.image_queue = image_queue
        self.command_queue = command_queue
        self.write_command_queue = write_command_queue
        self.fast = fast

        # Make space for image display
        self.image_display = QtWidgets.QLabel(self)
        self.setCentralWidget(self.image_display)

        # Trigger an update image whenever the 'new_image_received' signal is fired.
        self.new_image_received.connect(self.update_image)

        # Add menus for image capture
        self._add_menu()

        # Add a status bar for showing frame rate and image stats
        self.status = QtWidgets.QStatusBar()
        monospace_font = QtGui.QFontDatabase.systemFont(QtGui.QFontDatabase.FixedFont)
        self.status.setFont(monospace_font)
        self.setStatusBar(self.status)

        # Matplotlib windows
        self.mp_windows = []
        for c in range(maxchannels):
            self.mp_windows.append(LiveImageViewer(cmap="gray", vmin=0, vmax=255, title=("Channel "+str(c)), fast=self.fast))
        plt.show(block=False)

    def update_image(self):
        # image queue
        # element : [ [header_info, image_data], [header_info, image_data], [header_info, image_data], ...]
        while True:
            try:
                rx_channel_pkgs = []
                # there must be at least one channel
                rx_channel_pkgs.append(self.image_queue[0].get_nowait())

                rx_channel_header_info = rx_channel_pkgs[0][0]

                width      = rx_channel_header_info[0]
                height     = rx_channel_header_info[1]
                channels   = rx_channel_header_info[2]
                data_width = rx_channel_header_info[3]

                for c in range(1, channels):
                    rx_channel_pkgs.append(self.image_queue[c].get_nowait())

            except queue.Empty:
                return
            
            for c in range(channels):
                frame = rx_channel_pkgs[c][1]
                self.mp_windows[c].update_image(frame)

            #plt.pause(0.001)

        
    def _add_menu(self):
        # File menu
        menubar = self.menuBar()
        file_menu = menubar.addMenu("&File")
        capture_action = QtWidgets.QAction("Capture", self)
        capture_action.triggered.connect(self.open_capture_dialog)
        file_menu.addAction(capture_action)

        # View menu
        view_menu = menubar.addMenu("&View")
        view_options_action = QtWidgets.QAction("View Options", self)
        view_options_action.triggered.connect(self.open_view_options_dialog)
        view_menu.addAction(view_options_action)

        # Send command menu
        command_menu = menubar.addMenu("&Command")

        # Send raw command
        command_action = QtWidgets.QAction("Send Command", self)
        command_action.triggered.connect(self.open_command_dialog)
        command_menu.addAction(command_action)

        # Set homography
        set_camera_0_homography_action = QtWidgets.QAction("Set Camera 0 Homography", self)
        set_camera_0_homography_action.triggered.connect(lambda: self.open_camera_homography_dialog(0x20))
        command_menu.addAction(set_camera_0_homography_action)
        set_camera_1_homography_action = QtWidgets.QAction("Set Camera 1 Homography", self)
        set_camera_1_homography_action.triggered.connect(lambda: self.open_camera_homography_dialog(0x10))
        command_menu.addAction(set_camera_1_homography_action)

        # Set ROI
        roi_action = QtWidgets.QAction("Send Roi", self)
        roi_action.triggered.connect(self.open_roi_dialog)
        command_menu.addAction(roi_action)

        # Set DfDD parameters
        set_params_action = QtWidgets.QAction("Set DfDD Parameters", self)
        set_params_action.triggered.connect(self.open_dfdd_parameters_dialog)
        command_menu.addAction(set_params_action)

    def open_capture_dialog(self):
        dialog = CaptureDialog(settings=self.capture_settings)
        if dialog.exec_() == QtWidgets.QDialog.Accepted:
            values = dialog.get_values()
            self.capture_settings = values
            print("\nCapture request:", values)
            if(self.command_queue is None):
                print("Request ignored, not central channel")
            else:
                self.command_queue.put(values)


    def open_view_options_dialog(self):
        dialog = ViewOptionsDialog(current_scale=self.image_scale, current_color=self.color_map, parent=self)
        if dialog.exec_() == QtWidgets.QDialog.Accepted:
            values = dialog.get_values()
            if (values["scale"] is not None):
                self.image_scale = values["scale"]
            if (values["colormap"] is not None):
                self.color_map = values["colormap"]

    def open_command_dialog(self):
        self.command_widget = CommandWriteWidget()
        self.command_widget.write_command.connect(self.handle_write_command)
        self.command_widget.show()

    def open_camera_homography_dialog(self, start_addr=0x10):
        self.set_camera_homography_widget = HomographyWidget(start_addr=start_addr)
        self.set_camera_homography_widget.write_command.connect(self.handle_write_command)
        self.set_camera_homography_widget.show()

    def open_roi_dialog(self):
        self.roi_widget = RoiSendWidget()
        self.roi_widget.write_command.connect(self.handle_write_command)
        self.roi_widget.show()

    def open_dfdd_parameters_dialog(self):
        self.dfdd_parameters_widget = DfddParametersSendWidget()
        self.dfdd_parameters_widget.write_command.connect(self.handle_write_command)
        self.dfdd_parameters_widget.show()

    def handle_write_command(self, values):
        if (values is not None): 
            if(self.write_command_queue is None):
                print("Handle write command ignored, not central channel")
            else:
                self.write_command_queue.put(values["bytes"])

    def update_status(self, text):
        self.status.showMessage(text)



