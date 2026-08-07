import numpy as np
import torch
from torch import Tensor, nn

from utils.metrics import *
from utils.torch import *


class FilteredDepthLoss(nn.Module):
    def __init__(self, config) -> None:
        super().__init__()
        self.norm = 'L1'
        self.sparsity = config.optim.sparsity
        self.shape = (config.data.mask[1] - config.data.mask[0] - 22, config.data.mask[3] - config.data.mask[2] - 22)
        self.center = config.data.center
        self.n_rings = config.model.n_rings
        
        # Create ring masks.
        X, Y = get_pixel_coords(self.shape, self.center)
        R = torch.sqrt(X**2 + Y**2)
        r_list = np.linspace(0.0, R.max(), self.n_rings+1)
        mask_rings = []
        for idx in range(self.n_rings):
            mask_ring = get_ring_mask(X, Y, r_list[idx], r_list[idx+1]).unsqueeze(0).unsqueeze(0)
            mask_rings.append(mask_ring)
        self.register_buffer('mask_rings', torch.cat(mask_rings, dim=1))
        
        # Create ring depenedent depth bounds.
        z_min = torch.linspace(config.optim.z_min[0], config.optim.z_min[1], self.n_rings).view(1, self.n_rings, 1, 1)
        z_max = torch.linspace(config.optim.z_max[0], config.optim.z_max[1], self.n_rings).view(1, self.n_rings, 1, 1)
        self.register_buffer('z_min', (z_min * self.mask_rings).sum(dim=1, keepdim=True))
        self.register_buffer('z_max', (z_max * self.mask_rings).sum(dim=1, keepdim=True))


    def forward(self, z_pred: Tensor, z_true: Tensor, confs: Tensor) -> Tensor:
        # Create confidence mask.
        confs = confs.repeat(1, self.n_rings, 1, 1)
        confs[~self.mask_rings.repeat(confs.shape[0], 1, 1, 1)] = torch.nan
        conf_bound_rings = torch.nanquantile(confs.reshape(confs.shape[0],confs.shape[1],-1), q=self.sparsity, dim=-1, keepdim=True).unsqueeze(-1)
        mask_conf = torch.any(confs >= conf_bound_rings, dim=1, keepdim=True)
        # print(mask_conf.shape)
        # print(z_pred.max(), z_pred.min())
        # Create working range mask.
        # mask_wr = (z_pred >= self.z_min) * (z_pred <= self.z_max)
        # print(mask_wr.shape)
        mask = mask_conf #* mask_wr
        
        if self.norm == 'L1':
            loss = torch.abs(z_pred[mask] - z_true[mask])
        elif self.norm == 'L2':
            loss = (z_pred[mask] - z_true[mask]) ** 2
        else:
            raise ValueError(f"Unsupported norm: {self.norm}")
        
        if loss.numel() == 0:
            print("No valid samples for loss calculation.")
            
        return loss.mean()
    