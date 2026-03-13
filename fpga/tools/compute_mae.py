#!/usr/bin/env python3
import os
import sys
import math
import numpy as np
from PIL import Image
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
import pandas as pd

# ---------------- CONFIG ----------------
DEFAULT_DIR = "."
CSV_NAME = "compute_mae_results.csv"
PLOT_MAE_NAME = "mae_vs_target.png"
PLOT_ME_NAME  = "me_vs_target.png"
PLOT_GRID_NAME = "depthmap_grid.png"

VMIN = 0.3
VMAX = 1.4
HIGH_DPI = 600
N_COLS = 7
# ----------------------------------------


def load_uint8_div128_cropped(path: str) -> np.ndarray:
    """Load 8-bit PNG -> float, crop, zero→NaN."""
    with Image.open(path) as im:
        arr = np.asarray(im)

    if arr.ndim == 3:  # RGB or RGBA
        arr = arr[..., :3]
        arr = arr.mean(axis=2)

    arr = arr[15:415, 5:485]  # crop
    arr = arr.astype(np.float32) / (2**7)
    arr[arr == 0.0] = np.nan
    return arr


def main(directory: str):
    directory = os.path.abspath(directory)

    results = []
    samples = []

    # Load in index order: cam_1_500_480_x.png
    for x in range(56):
        fname = f"cam_1_500_480_{x}.png"
        fpath = os.path.join(directory, fname)
        if not os.path.isfile(fpath):
            continue

        arr = load_uint8_div128_cropped(fpath)
        target = 0.24 + 0.02 * x

        err = arr - target
        mae = float(np.nanmean(np.abs(err)))
        me  = float(np.nanmean(err))  # signed mean error

        results.append((x, target, mae, me, fname))
        samples.append((x, arr, target, mae, me))

        print(
            f"x={x:02d}: target={target:.2f}, "
            f"MAE={mae:.4f}, ME={me:.4f}"
        )

    if not results:
        print("No cam_1_500_480_x.png files found.")
        return

    # Save CSV
    df = pd.DataFrame(
        results,
        columns=["x", "target_m", "MAE_m", "ME_m", "filename"],
    )
    df.to_csv(os.path.join(directory, CSV_NAME), index=False)

    # ------------------------ MAE vs Target Plot ------------------------
    plt.figure(figsize=(7, 4.2))
    plt.scatter(df["target_m"], df["MAE_m"])
    plt.xlabel("Target Depth (m)")
    plt.ylabel("MAE (m)")
    plt.title("MAE vs Target Depth")
    plt.grid(alpha=0.3)
    plt.tight_layout()
    plt.savefig(
        os.path.join(directory, PLOT_MAE_NAME),
        dpi=HIGH_DPI,
        bbox_inches="tight",
        pad_inches=0,
    )
    plt.close()

    # ------------------------ ME vs Target Plot ------------------------
    plt.figure(figsize=(7, 4.2))
    plt.scatter(df["target_m"], df["ME_m"])
    plt.axhline(0.0, linestyle="--", linewidth=1, color="gray")
    plt.xlabel("Target Depth (m)")
    plt.ylabel("Mean Error (m)")
    plt.title("Mean Error vs Target Depth")
    plt.grid(alpha=0.3)
    plt.tight_layout()
    plt.savefig(
        os.path.join(directory, PLOT_ME_NAME),
        dpi=HIGH_DPI,
        bbox_inches="tight",
        pad_inches=0,
    )
    plt.close()

    # ------------------------ Tight Grid with Perfect Row Colorbars ------------------------
    samples.sort(key=lambda t: t[0])
    n = len(samples)
    n_rows = math.ceil(n / N_COLS)

    fig_width = 2.8 * (N_COLS + 0.5)
    fig_height = 2.8 * n_rows
    fig = plt.figure(figsize=(fig_width, fig_height))

    outer_gs = gridspec.GridSpec(
        n_rows,
        1,
        hspace=0.1,
        wspace=0.1,
    )

    idx = 0
    for r in range(n_rows):
        row_gs = gridspec.GridSpecFromSubplotSpec(
            1,
            N_COLS + 1,
            subplot_spec=outer_gs[r],
            width_ratios=[1] * N_COLS + [0.07],
            wspace=0.1,
            hspace=0.1,
        )

        chosen_im = None

        for c in range(N_COLS):
            ax = fig.add_subplot(row_gs[0, c])

            if idx < n:
                x, arr, target, mae, me = samples[idx]
                im = ax.imshow(arr, cmap="jet", vmin=VMIN, vmax=VMAX)

                ax.set_title(
                    f"t={target:.2f}m, MAE={mae:.3f}m, ME={me:+.3f}m",
                    fontsize=7,
                )
                ax.axis("off")

                if chosen_im is None:
                    chosen_im = im

                idx += 1
            else:
                ax.axis("off")

        # Colorbar for this row
        cax = fig.add_subplot(row_gs[0, -1])
        if chosen_im is not None:
            cbar = fig.colorbar(chosen_im, cax=cax)
            cbar.set_label("Depth (m)", fontsize=8)

    plt.savefig(
        os.path.join(directory, PLOT_GRID_NAME),
        dpi=HIGH_DPI,
        bbox_inches="tight",
        pad_inches=0,
    )
    plt.close()
    print(f"Saved grid → {os.path.join(directory, PLOT_GRID_NAME)}")


if __name__ == "__main__":
    directory = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_DIR
    main(directory)
