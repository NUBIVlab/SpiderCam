import os

import numpy as np
import torch
from matplotlib import pyplot as plt

from utils.metrics import *

FONT_WEIGHT = 'semibold'
plt.rcParams.update({'font.weight': FONT_WEIGHT, 'font.family': 'DejaVu Serif'})


def plot_heat_map(results_path: str, z_true: np.ndarray, z_pred: np.ndarray, conf: np.ndarray, n_bins: int):
    
    working_range = [z_true.min(), z_true.max()]
    heatmap_range = [working_range,working_range]
    
    for sparsity in [0.0, 0.05, 0.8, 0.9, 0.95, 0.99]:
        mask = get_confidence_mask(conf, sparsity)
        heatmap, xedges, yedges = np.histogram2d(z_true[mask].flatten(), z_pred[mask].flatten(), bins=n_bins, range=heatmap_range)
        
        fig, ax = plt.subplots(figsize=(8, 7))
        ax.plot(working_range, working_range, 'w', alpha=0.5)
        heatmap = heatmap.T
        extent = [xedges[0], xedges[-1], yedges[0], yedges[-1]]
        ZkfHist = ax.imshow(heatmap, extent=extent, origin='lower')
        fig.colorbar(ZkfHist, ax=ax, fraction=0.046, pad=0.04)
        ax.set_xlabel('True Depth (m)', fontsize=15, fontweight=FONT_WEIGHT)
        ax.set_ylabel('Estimated Depth (m)', fontsize=15, fontweight=FONT_WEIGHT)
        fig.tight_layout()
        
        os.makedirs(os.path.join(results_path, 'heatmap'), exist_ok=True)
        plt.savefig(os.path.join(results_path, 'heatmap', f'heatmap_{sparsity*100:.1f}%.png'), dpi=128, bbox_inches='tight')
        plt.close()
    
    
def plot_depth_map(results_path: str, z_true: np.ndarray, z_pred: np.ndarray, conf: np.ndarray, working_range: tuple):
    
    norm = plt.Normalize(working_range[0], working_range[1])
    # print(z_pred.min(), z_pred.max())
    # z_pred[confs < threshold] = np.nan
    error = np.abs(z_pred - z_true)
    fig = plt.figure(figsize=(17, 8))
    for idx, sparsity in enumerate([0.0, 0.5, 0.8, 0.9, 0.95]):
        mask = get_confidence_mask(conf.reshape(1,1,conf.shape[-2],conf.shape[-1]), sparsity)[0,0]
        z_pred_filtered = z_pred.copy()
        z_pred_filtered[~mask] = np.nan
        ax = plt.subplot(2, 3, idx+1)
        plt.imshow(z_pred_filtered, cmap='jet', norm=norm)
        plt.axis('off')
        plt.title(f'Predicted depth (sparsity: {sparsity*100:.1f}%)', fontsize=14, fontweight=FONT_WEIGHT)
        plt.title(f'Mean depth error: {error[mask].mean():.3f}m  ({mask.mean()*100:.1f}%)', loc='left', y=-0.09, fontsize=11, fontweight='bold')
        if (idx + 1) % 3 == 0:
            cax = fig.add_axes([ax.get_position().x1+0.01, ax.get_position().y0, 0.02, ax.get_position().height])
            cb = plt.colorbar(cax=cax, norm=norm)

    ax = plt.subplot(2,3,6)
    plt.imshow(z_true, cmap='jet', norm=norm)
    plt.title('True depth', fontsize=16, fontweight=FONT_WEIGHT)
    plt.axis('off')
    cax = fig.add_axes([ax.get_position().x1+0.01, ax.get_position().y0, 0.02, ax.get_position().height])
    cb = plt.colorbar(cax=cax, norm=norm)
    cb.set_label("$\mathbf{m \cdot s^{-1}}$", fontsize=13)
    
    os.makedirs(os.path.join(results_path, 'depthmap'), exist_ok=True)
    plt.savefig(os.path.join(results_path, 'depthmap', f'depthmap_{z_true[0,0]:.3f}m.png'), dpi=128, bbox_inches='tight')
    plt.close()
    
    
def show_A_B(results_path: str, A: np.ndarray, B: np.ndarray):
    fig = plt.figure(figsize=(12, 5))
    
    ax = plt.subplot(1,2,1)
    plt.imshow(A, cmap='magma', norm=plt.Normalize(vmin=A.min(), vmax=A.max()))
    plt.title('A', fontsize=16, fontweight=FONT_WEIGHT)
    plt.axis('off')
    cax = fig.add_axes([ax.get_position().x1+0.01, ax.get_position().y0, 0.02, ax.get_position().height])
    cb = plt.colorbar(cax=cax, norm=plt.Normalize(vmin=A.min(), vmax=A.max()))

    
    ax = plt.subplot(1,2,2)
    plt.imshow(B, cmap='magma', norm=plt.Normalize(vmin=B.min(), vmax=B.max()))
    plt.title('B', fontsize=16, fontweight=FONT_WEIGHT)
    plt.axis('off')
    cax = fig.add_axes([ax.get_position().x1+0.01, ax.get_position().y0, 0.02, ax.get_position().height])
    cb = plt.colorbar(cax=cax, norm=plt.Normalize(vmin=B.min(), vmax=B.max()))

    plt.savefig(os.path.join(results_path, 'A_B.png'), dpi=128, bbox_inches='tight')


def plot_error_conf(results_path: str, z_true: np.ndarray, z_pred: np.ndarray, conf: np.ndarray):
    
    thresholds = np.logspace(-11, np.log10(conf.max()), 256, base=10)
    errors, percentages = [], []
    error = np.abs(z_true - z_pred)

    for threshold in thresholds:
        mask = conf >= threshold
        errors.append(error[mask].mean())
        percentages.append(mask.mean()*100)  

    fig, ax1 = plt.subplots(figsize=(7,6))
    ax2 = ax1.twinx()
    lns1 = ax1.plot(thresholds, errors, linewidth=2.5, label='Mean depth error')
    ax1.set_xlabel('Confidence threshold', fontsize=15, fontweight=FONT_WEIGHT)
    ax1.set_ylabel('Mean depth error (m)', fontsize=15, fontweight=FONT_WEIGHT)
    ax1.set_xscale('log')
    ax1.set_ylim(bottom=0, top=np.max(errors)*1.1)
    
    lns2 = ax2.plot(thresholds, percentages, color='orange', linewidth=2.5, label='Percentage')
    ax2.set_ylabel('Percentage of pixels above threshold', fontsize=15, fontweight=FONT_WEIGHT)
    ax2.set_xscale('log')
    # ax2.set_yscale('log')
    ax2.set_ylim(bottom=0, top=105)
    
    lns = lns1 + lns2
    labs = [l.get_label() for l in lns]
    ax1.legend(lns, labs, loc='lower center', fontsize=13)
    fig.tight_layout()
    
    plt.savefig(os.path.join(results_path, f'error-conf.png'), dpi=128, bbox_inches='tight')
    plt.close()
    
    
def plot_error_depth(results_path: str, z_true: np.ndarray, z_pred: np.ndarray, conf: np.ndarray, sparsity: float=0.8):
    depth = z_true[...,0,0]
    
    mask = get_confidence_mask(conf, sparsity)
    
    confs = (conf * mask).sum(axis=(-3,-2,-1)) / mask.sum(axis=(-3,-2,-1))
    mae = (np.abs(z_true - z_pred) * mask).sum(axis=(-3,-2,-1)) / mask.sum(axis=(-3,-2,-1))
    
    working_range = get_working_range(z_true, z_pred, conf, sparsity)
    
    fig, ax1 = plt.subplots(figsize=(8,7))
    ax2 = ax1.twinx()
    lns1 = ax1.plot(depth, mae, linewidth=2.5, label='Mean depth error')
    ax1.set_xlabel('Truth depth (m)', fontsize=15, fontweight=FONT_WEIGHT)
    ax1.set_ylabel('Mean depth error (m)', fontsize=15, fontweight=FONT_WEIGHT)
    ax1.set_ylim(bottom=0, top=mae.max()*1.1)
    x = np.linspace(depth.min(), depth.max(), 100)
    y = x * 0.1
    lns3 = ax1.plot(x, y, linestyle='--', linewidth=2.5, color='red', label='Working range threshold')
    if len(working_range) == 2:
        ax1.vlines(working_range[0], 0, mae.max()*1.1, linestyle='--', linewidth=1.5, color='red')
        ax1.vlines(working_range[1], 0, mae.max()*1.1, linestyle='--', linewidth=1.5, color='red')
        ax1.text(s=f'Working range: {working_range[1]-working_range[0]:.3f}m', x=(depth[0] + depth[-1])/2, y=mae.max()*1.05, fontsize=14, fontweight=FONT_WEIGHT)
    ax1.text(s=f'MAE: {mae.mean():.3f}m', x=depth[0], y=mae.max()*1.05, fontsize=14, fontweight=FONT_WEIGHT)
    
    
    lns2 = ax2.plot(depth, confs, color='orange', linewidth=2.5, label='Confidence')
    ax2.set_ylabel('Confidence', fontsize=15, fontweight=FONT_WEIGHT)
    # ax2.set_ylim(bottom=0, top=105)
    
    lns = lns1 + lns2 + lns3
    labs = [l.get_label() for l in lns]
    ax1.legend(lns, labs, loc='lower center', fontsize=13)
    fig.tight_layout()
    
    plt.title(f'Error Depth (Sparsity: {sparsity*100:.1f}%)', fontsize=16, fontweight=FONT_WEIGHT)
    
    os.makedirs(os.path.join(results_path, 'error-depth'), exist_ok=True)
    plt.savefig(os.path.join(results_path, 'error-depth', f'error-depth_{sparsity*100:.1f}%.png'), dpi=128, bbox_inches='tight')
    plt.close()


def plot_error_sparsity(results_path: str, z_true: np.ndarray, z_pred: np.ndarray, conf: np.ndarray):
    sparsity_list = np.arange(0, 1, 0.01)
    errors = []
    error = np.abs(z_true - z_pred)

    for sparsity in sparsity_list:
        mask = get_confidence_mask(conf, sparsity)
        errors.append(error[mask].mean())

    fig, ax = plt.subplots(figsize=(7,7))
    ax.plot(sparsity_list*100, errors, linewidth=2.5, label='Mean depth error')
    ax.set_xlabel('Sparsity (%)', fontsize=15, fontweight=FONT_WEIGHT)
    ax.set_ylabel('Mean depth error (m)', fontsize=15, fontweight=FONT_WEIGHT)
    ax.set_ylim(bottom=0, top=np.max(errors)*1.1)
    ax.legend(loc='lower center', fontsize=13)
    fig.tight_layout()
    
    os.makedirs(os.path.join(results_path, 'error-sparsity'), exist_ok=True)
    plt.savefig(os.path.join(results_path, 'error-sparsity', 'error-sparsity.png'), dpi=128, bbox_inches='tight')
    plt.close()
    
    
def plot_loss_curve(model_save_path: str, train_loss: list, val_loss: list, epoch_min: int):
    n_epochs = len(train_loss)
    plt.figure(figsize=(12,7))
    plt.plot(range(1, n_epochs+1), train_loss, '-o', markersize=4, label='Train Loss')
    # plt.plot(range(1, n_epochs+1), val_loss, '-o', markersize=4, label='Valid Loss')
    plt.plot([epoch_min], [train_loss[epoch_min-1]], 'ro', markersize=7, label='Best Epoch')
    plt.title('Loss Curve', fontsize=18, fontweight=FONT_WEIGHT)
    plt.xlabel('Epoch', fontsize=14, fontweight=FONT_WEIGHT)
    plt.ylabel('Loss', fontsize=14, fontweight=FONT_WEIGHT)
    plt.yscale('log')
    plt.legend(fontsize=15)
    file_name = os.path.join(model_save_path, 'loss_curve.jpg')
    plt.savefig(file_name, bbox_inches='tight')
    plt.close()