import numpy as np
import torch
from torch import Tensor


def get_confidence_mask(conf, sparsity):
    H, W = conf.shape[-2:]
    if sparsity == 1.0:
        return np.ones_like(conf)
    conf_bound = np.quantile(conf.reshape(-1,H*W), q=sparsity, axis=-1, keepdims=True).reshape(*conf.shape[:-2],1,1)
    return (conf >= conf_bound)


def get_working_range(z_true: Tensor, z_pred: Tensor, conf: Tensor, sparsity: float):
    """Get the working range of the predicted depth map."""
    
    mask = get_confidence_mask(conf, sparsity)

    mae = (np.abs(z_true - z_pred) * mask).sum(axis=(-3,-2,-1)) / mask.sum(axis=(-3,-2,-1))
    # mae = mae.squeeze(-1)
    z_true_mean = z_true.mean(axis=(-3,-2,-1))
    sign = np.sign(mae - 0.1 * z_true_mean).flatten()

    # Find where the sign changes
    sign_change = (sign[1:] != sign[:-1]).nonzero()[0]

    if len(sign_change) == 0:
        return []

    working_range = []
    for idx in [sign_change[0], sign_change[-1]]:
        # The two points defining the interval
        x1, x2 = idx, idx + 1
        y1_c1, y2_c1 = mae[x1], mae[x2]
        y1_c2, y2_c2 = 0.1*z_true_mean[x1], 0.1*z_true_mean[x2]

        # Calculate the x-intersection point
        numerator = y1_c2 - y1_c1
        denominator = (y2_c1 - y1_c1) - (y2_c2 - y1_c2)

        # Handle the case where the curves are parallel in the interval
        if denominator.item() == 0:
            working_range.append(z_true_mean[x1])
        else:
            x_intersection = x1 + (numerator / denominator)
            working_range.append(10*(y1_c1 + (y2_c1 - y1_c1) * (x_intersection - x1)).item())

    if working_range[0] == working_range[1]:
        working_range = [working_range[0], z_true.max().item()]
        
    return working_range
    