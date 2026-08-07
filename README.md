## [CVPR 2026] SpiderCam: Low-Power Snapshot Depth from Differential Defocus

<b>[Marcos A. Ferreira](https://marc103.github.io/)</b><sup>&ast;,1</sup>, <b>[Tianao Li](https://lukeli0425.github.io/)</b><sup>&ast;,1</sup>, <b>[John Mamish](https://scholar.google.com/citations?user=ux9iJ74AAAAJ&hl=en)</b><sup>&ast;,2</sup>, <b>[Josiah Hester](https://josiahhester.com/)</b><sup>2</sup>, <b>[Yaman Sangar](https://scholar.google.com/citations?user=gbBJzRkAAAAJ&hl=en&oi=ao)</b><sup>2</sup>, <b>[Qi Guo](https://www.qiguo.org/)</b><sup>3</sup>, <b>[Emma Alexander](https://www.alexander.vision/emma)</b><sup>1</sup>
<br>
<sup>1</sup>Northwestern University, <sup>2</sup>Georgia Institute of Technology, <sup>3</sup>Purdue University, <sup>&ast;</sup>Equal contribution.

_IEEE/CVF Conference on Computer Vision and Pattern Recognition (CVPR), 2026_

[![Project Page](https://img.shields.io/badge/Project-Page-purple)](https://nubivlab.github.io/SpiderCam/)&nbsp;
[![arXiv](https://img.shields.io/badge/arXiv-2603.17910-b31b1b.svg)](http://arxiv.org/abs/2603.17910)&nbsp;
[![Demo Video](https://img.shields.io/badge/Youtube-Video-red)](https://youtu.be/eOzm_onlyY0?si=R25dEPk8qHDu6dYn)&nbsp;
[![LICENSE](https://img.shields.io/badge/License-MIT-blue)](./LICENSE)&nbsp;

Official code for [_SpiderCam: Low-Power Snapshot Depth from Differential Defocus_](https://nubivlab.github.io/SpiderCam/).

![Pipeline](figures/SpiderCam_pipeline.png)

### Repository layout

| Path | Contents |
| --- | --- |
| [`configs/`](configs/), [`datasets/`](datasets/), [`models/`](models/), [`utils/`](utils/) | Hydra configs and DfDD training / inference code |
| [`serialcam_ft232h/`](serialcam_ft232h/) | Live FT232H stream viewer and on-device DfDD parameter UI |
| [`fpga/`](fpga/) | FPGA RTL (see [`fpga/README.md`](fpga/README.md)) |
| [`pcb/`](pcb/) | PCB layouts |
| [`3d_printed_parts/`](3d_printed_parts/) | Printable enclosure parts |

### Running DfDD

#### Setup

To install required packages:
```bash
pip install -r requirements.txt
```

#### Data

Point `data_path` in a config under [`configs/data/`](configs/data/) to your capture directory. Each group folder should contain paired frames:

- `cam_1_500_480_{idx}.png` — near-focus (`+`) image  
- `cam_0_500_480_{idx}.png` — far-focus (`-`) image  

Crop, frame range, depth step/offset, and image center are set in the same YAML (see e.g. [`configs/data/11-06.yaml`](configs/data/11-06.yaml)).

#### Model parameters

Defaults live in [`configs/model/focal_split.yaml`](configs/model/focal_split.yaml). Override any of them on the CLI with Hydra (`model.<key>=...`).

| Parameter | Options / typical values | Meaning |
| --- | --- | --- |
| `model.n_scales` | `1` or `2` | Number of Laplacian-pyramid levels. Depth is estimated at each scale and fused; `2` is the paper default and improves robustness across texture frequencies. |
| `model.dxdy` | `true` / `false` | If `true`, append spatial derivatives (`∂/∂x`, `∂/∂y`) of `V` and `W` as extra channels before fusion (3 channels per scale). Helps on oriented textures. |
| `model.const` | `rings`, `universal`, `radial`, `polynomial`, `pixel-grid` | How optical constants **A** and **B** vary over the field of view (see below). |
| `model.n_rings` | e.g. `16` | Used when `const=rings`: number of concentric annuli with a shared (A, B) per ring. |
| `model.n_orders` | e.g. `2` | Used when `const=radial` or `polynomial`: polynomial degree of the radial / 2D field. |
| `model.conf` | `VW`, `W2`, `V`, `W` | Confidence map used for sparsity filtering and (in `separate` mode) scale fusion. |
| `model.mode` | `joint` / `separate` | How multi-channel estimates are fused (see below). |

**Optical constants (`model.const`).** DfDD recovers depth from a linear combination of the image Laplacian and the differential image, with learnable maps **A** and **B** (one pair per scale):

- `universal` — single scalar (A, B) per scale (spatially constant; ablation / simplest FPGA mapping).
- `rings` — piecewise-constant (A, B) on concentric rings about `data.center` (paper default; matches on-device zone tables).
- `radial` — A(r), B(r) as low-order polynomials in image radius.
- `polynomial` — full 2D polynomial in (x, y).
- `pixel-grid` — independent (A, B) at every pixel (most flexible, heaviest).

**Confidence (`model.conf`).** With numerator/denominator terms built from `V` and `W`:

- `VW` — confidence ∝ `V·W` (paper default; aligns with the depth numerator).
- `W2` — confidence ∝ `W²` (denominator energy).
- `V` / `W` — confidence ∝ `|V|` or `|W|`.

Higher confidence pixels are kept when evaluating at a given sparsity (see `optim.sparsity`).

**Fusion (`model.mode`).** Softmax weights `ω` combine channels across scales (and dx/dy if enabled):

- `joint` — fuse numerator and denominator first, then divide (more stable; default).
- `separate` — form a depth map per channel, then confidence-weighted average.

**Paper setting (recommended start):**

```text
model.n_scales=2 model.dxdy=true model.mode=joint model.const=rings model.n_rings=16 model.conf=VW
```

#### Train

Calibrate / train optical constants with Hydra overrides:

```bash
python train_focal_split.py data=11-06 data.group=texture1 \
  model.n_scales=2 model.dxdy=true model.mode=joint model.const=rings model.n_rings=16 \
  model.conf=VW
```

Checkpoints and logs are written under `./results/`. For the full ablation suite used in the paper, see [`train.sh`](train.sh).

#### Evaluate

After training, run inference with the same data/model/optim settings (must match the trained checkpoint path):

```bash
python run_focal_split.py data=11-06 data.group=texture1 \
  model.n_scales=2 model.dxdy=true model.mode=joint model.const=rings model.n_rings=16 \
  model.conf=VW
```

This loads `checkpoint_{n_epochs}epochs.pth`, reports MAE/MSE and working range at several sparsities, and saves heatmaps / depth maps under `./results/`.

#### Live hardware (optional)

With the SpiderCam FPGA connected over FT232H:

```bash
python serialcam_ft232h/serialcam_stream_ft232h.py
```

Requires the `serialcam` stack (PyQt5, `ftd2xx`). Use **Set DfDD Parameters** in the viewer to push A/B/ω and confidence thresholds to the device. 
<!-- PCB layouts, FPGA RTL, and printable enclosure parts are under [`pcb/`](pcb/), [`fpga/`](fpga/), and [`3d_printed_parts/`](3d_printed_parts/). -->

### Citation

```bibtex
@InProceedings{ferreira2026spidercam,
    author    = {Ferreira, Marcos A. and Li, Tianao and Mamish, John and Hester, Josiah and Sangar, Yaman and Guo, Qi and Alexander, Emma},
    title     = {SpiderCam: Low-Power Snapshot Depth from Differential Defocus},
    booktitle = {Proceedings of the IEEE/CVF Conference on Computer Vision and Pattern Recognition (CVPR)},
    month     = {June},
    year      = {2026},
    pages     = {41699-41709}
}
```

### Acknowledgment

This research was partially supported by the National Science Foundation under award numbers CNS-2430327 and CCF-2431505. Any opinions, findings, conclusions, or recommendations expressed in this material are those of the authors and do not necessarily reflect the views of the National Science Foundation or other supporters. We would also like to thank [Junjie Luo](https://luo-jun-jie.github.io/) and [Alan Fu](https://www.linkedin.com/in/alan-fu-a100b91a5/) for helpful discussions.
