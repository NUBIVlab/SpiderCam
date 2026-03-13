#!/usr/bin/env python3
import os
import sys
import re
import numpy as np
import cv2
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.patches as patches

# ---------------- CONFIG ----------------
DEFAULT_DIR = "."
CSV_NAME = "true_mode_results.csv"
PLOT_MAE_NAME = "true_mode_mae_vs_gt_mean.png"
PLOT_GRID_NAME = "true_mode_depthmap_grid.png"

VMIN = 0.4
VMAX = 1.0
HIGH_DPI = 600

DEBUG_PRINT_ONE_TRUE = True
# ----------------------------------------


def _crop_2d(arr: np.ndarray) -> np.ndarray:
    return arr[15:415, 5:485]


def _crop_3d(arr: np.ndarray) -> np.ndarray:
    return arr[15:415, 5:485, :]


def _load_depth_generic_cv2(path: str,
                            use_green_channel: bool,
                            debug_label: str = "") -> np.ndarray:
    """
    Generic depth loader using OpenCV.

    - Reads with IMREAD_UNCHANGED.
    - If multi-channel:
        * if use_green_channel: take green channel (BGR[...,1])
        * else: convert to grayscale (cvtColor).
    - Handles uint8 or uint16:
        * if uint16: convert to 8-bit via >> 8.
    - Crops [15:415, 5:485].
    - Converts to float32 and divides by 128.
    - Zero -> NaN.
    """
    img = cv2.imread(path, cv2.IMREAD_UNCHANGED)
    if img is None:
        raise RuntimeError(f"Failed to load image: {path}")

    if img.ndim == 3:
        if use_green_channel:
            gray = img[..., 1]  # green channel only
        else:
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    else:
        gray = img

    orig_dtype = gray.dtype

    if gray.dtype == np.uint16:
        gray = (gray >> 8).astype(np.uint8)
    elif gray.dtype != np.uint8:
        gray = gray.astype(np.uint8)
    global DEBUG_PRINT_ONE_TRUE
    if debug_label and use_green_channel and DEBUG_PRINT_ONE_TRUE:
        print(f"[DEBUG true] {debug_label}: dtype={orig_dtype}, "
              f"min={gray.min()}, max={gray.max()}")

    gray = _crop_2d(gray)

    depth = gray.astype(np.float32) / 128.0
    depth[depth == 0.0] = np.nan

    
    if debug_label and use_green_channel and DEBUG_PRINT_ONE_TRUE:
        print(f"[DEBUG true] {debug_label}: after /128, "
              f"min={np.nanmin(depth):.4f}, max={np.nanmax(depth):.4f}")
        DEBUG_PRINT_ONE_TRUE = False

    return depth


def load_depth_pred(path: str) -> np.ndarray:
    return _load_depth_generic_cv2(path, use_green_channel=False)


def load_depth_true(path: str, debug_label: str = "") -> np.ndarray:
    return _load_depth_generic_cv2(path, use_green_channel=True, debug_label=debug_label)


def load_rgb_cropped(path: str) -> np.ndarray:
    """
    Load original image with OpenCV, convert BGR->RGB, crop.
    """
    img = cv2.imread(path, cv2.IMREAD_COLOR)
    if img is None:
        raise RuntimeError(f"Failed to load image: {path}")
    img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    img = _crop_3d(img)
    return img


def add_black_border(ax):
    rect = patches.Rectangle(
        (0, 0),
        1, 1,
        linewidth=2,
        edgecolor="black",
        facecolor="none",
        transform=ax.transAxes,
        clip_on=False,
    )
    ax.add_patch(rect)


def main(directory: str):
    directory = os.path.abspath(directory)

    # Filename patterns (ignore everything after 500_480)
    img_re  = re.compile(r"^(?P<stem>.+)_0_500_480(?:_.*)?\.png$", re.IGNORECASE)
    pred_re = re.compile(r"^(?P<stem>.+)_1_500_480(?:_.*)?\.png$", re.IGNORECASE)
    true_re = re.compile(r"^(?P<stem>.+)_true_1_500_480(?:_.*)?\.png$", re.IGNORECASE)

    image_files = {}
    pred_files = {}
    true_files = {}

    all_files = [f for f in os.listdir(directory) if f.lower().endswith(".png")]

    if not all_files:
        print("No PNG files found in directory.")
        return

    # Classify by stem
    for fname in all_files:
        m_img  = img_re.match(fname)
        m_true = true_re.match(fname)
        m_pred = pred_re.match(fname)

        if m_true:
            true_files[m_true.group("stem")] = fname
        elif m_pred:
            pred_files[m_pred.group("stem")] = fname
        elif m_img:
            image_files[m_img.group("stem")] = fname

    stems = sorted(set(image_files.keys()) &
                   set(pred_files.keys()) &
                   set(true_files.keys()))

    if not stems:
        print("No complete (image, pred, true) triplets found.")
        print("Image stems:", sorted(image_files.keys()))
        print("Pred stems: ", sorted(pred_files.keys()))
        print("True stems: ", sorted(true_files.keys()))
        return

    results = []
    samples = []  # (stem, orig_img, ref_img, pred_img, gt_mean, mae)

    for stem in stems:
        img_path  = os.path.join(directory, image_files[stem])
        pred_path = os.path.join(directory, pred_files[stem])
        true_path = os.path.join(directory, true_files[stem])

        orig_img = load_rgb_cropped(img_path)
        pred_img = load_depth_pred(pred_path)
        ref_img  = load_depth_true(true_path, debug_label=true_files[stem])

        mae = float(np.nanmean(np.abs(pred_img - ref_img)))
        gt_mean = float(np.nanmean(ref_img))

        print(f"{stem}: GT_mean={gt_mean:.4f} m, MAE={mae:.4f} m")

        results.append(
            (stem, gt_mean, mae, image_files[stem], pred_files[stem], true_files[stem])
        )
        samples.append((stem, orig_img, ref_img, pred_img, gt_mean, mae))

    df = pd.DataFrame(
        results,
        columns=[
            "stem", "gt_mean_m", "MAE_m",
            "image_filename", "pred_filename", "true_filename",
        ],
    ).sort_values("stem")

    df.to_csv(os.path.join(directory, CSV_NAME), index=False)
    print(f"✅ Saved CSV to {os.path.join(directory, CSV_NAME)}")

    # ------------------------------
    # MAE vs Reference Mean Depth
    # ------------------------------
    plt.figure(figsize=(7, 4.2))
    plt.scatter(df["gt_mean_m"], df["MAE_m"])
    plt.xlabel("Reference Mean Depth (m)")
    plt.ylabel("MAE (m)")
    plt.title("MAE vs Reference Mean Depth", fontweight="bold")
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(
        os.path.join(directory, PLOT_MAE_NAME),
        dpi=HIGH_DPI,
        bbox_inches="tight",
        pad_inches=0,
    )
    plt.close()
    print(f"📈 Saved MAE plot to {os.path.join(directory, PLOT_MAE_NAME)}")

    # ------------------------------
    # GRID: Image | Reference | Predicted
    # ------------------------------
    samples.sort(key=lambda t: t[0])
    rows = len(samples)
    cols = 3

    fig_height = 2.5 * rows
    fig_width = 3.3 * cols + 0.6  # extra width for per-row colorbars

    fig, axes = plt.subplots(rows, cols, figsize=(fig_width, fig_height))
    axes = np.atleast_2d(axes)

    for i, (stem, orig_img, ref_img, pred_img, gt_mean, mae) in enumerate(samples):
        ax_img  = axes[i, 0]
        ax_ref  = axes[i, 1]
        ax_pred = axes[i, 2]

        # ---- Image ----
        ax_img.imshow(orig_img)
        if i == 0:
            ax_img.set_title("Image", fontsize=10, fontweight="bold")
        ax_img.axis("off")
        add_black_border(ax_img)

        # ---- Reference ----
        ax_ref.imshow(ref_img, cmap="jet", vmin=VMIN, vmax=VMAX)
        if i == 0:
            ax_ref.set_title("Reference", fontsize=10, fontweight="bold")
        ax_ref.axis("off")
        add_black_border(ax_ref)

        # ---- Predicted ----
        im_pred = ax_pred.imshow(pred_img, cmap="jet", vmin=VMIN, vmax=VMAX)
        if i == 0:
            ax_pred.set_title("Predicted", fontsize=10, fontweight="bold")
        ax_pred.text(
            0.02, 0.05,
            f"MAE={mae:.3f} m",
            color="white",
            fontsize=8,
            transform=ax_pred.transAxes,
            ha="left",
            va="bottom",
            bbox=dict(facecolor="black", alpha=0.4, pad=2),
        )
        ax_pred.axis("off")
        add_black_border(ax_pred)

    # ------------------------------
    # COLORBAR on RIGHT FOR EVERY ROW
    # ------------------------------
    fig.canvas.draw()

    for i in range(rows):
        row_axes = axes[i, :]
        row_top = max(ax.get_position().y1 for ax in row_axes)
        row_bottom = min(ax.get_position().y0 for ax in row_axes)

        # Place colorbar axis next to this row
        colorbar_ax = fig.add_axes([0.93, row_bottom, 0.015, row_top - row_bottom])

        # Use the predicted image from that row (axes[i, 2])
        cbar = plt.colorbar(axes[i, 2].images[0], cax=colorbar_ax)
        cbar.set_label("Depth (m)", fontweight="bold")

    out_path = os.path.join(directory, PLOT_GRID_NAME)
    plt.savefig(
        out_path,
        dpi=HIGH_DPI,
        bbox_inches="tight",
        pad_inches=0,
    )
    plt.close()
    print(f"🖼 Saved grid to {out_path}")


if __name__ == "__main__":
    directory = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_DIR
    main(directory)
