# from typing import TYPE_CHECKING, Any

import numpy as np
import torch
from torch import Tensor
from torch.nn import Module

# if TYPE_CHECKING:
#     from torch.nn import Module
# else:
#     Module = Any


def get_total_params(model: Module) -> int:
    """Calculate the total number of parameters in a model.
	
	Args:
		model (Module): PyTorch module.

	Returns:
		int: Total number of parameters in the model.
	"""
    return sum([param.nelement() if param.requires_grad else 0 for param in model.parameters()])


def get_pixel_coords(shape: tuple, center: tuple) -> tuple[Tensor, Tensor]:
    """Generates a flattened grid of (x,y,...) coordinates in a given range.
    
    Args:
        shape (tuple): Shape of the datacude to be fitted.
        range (tuple, optional): Range of the grid. Defaults to `(-1, 1)`.

    Returns:
        Tensor: Generated flattened grid of coordinates.
    """
    X = torch.arange(0, shape[-2], 1) - center[-2]
    Y = torch.arange(0, shape[-1], 1) - center[-1]
    X, Y = torch.meshgrid(X, Y, indexing='ij')
    return X, Y


def get_ring_mask(X: Tensor, Y: Tensor, r_min: float=0.0, r_max: float=1.0):
    return (torch.sqrt(X ** 2 + Y ** 2) >= r_min) * (torch.sqrt(X ** 2 + Y ** 2) < r_max)


def get_ring_mask_stack(config) -> Tensor:
    shape = (config.data.mask[1] - config.data.mask[0] - 22, config.data.mask[3] - config.data.mask[2] - 22)

    # Create ring masks.
    X, Y = get_pixel_coords(shape, config.data.center)
    R = torch.sqrt(X**2 + Y**2)
    r_list = torch.linspace(0.0, R.max()+1, config.model.n_rings+1)
    masks = [get_ring_mask(X, Y, r_list[idx], r_list[idx+1]) for idx in range(config.model.n_rings)]
    return torch.stack(masks, axis=0)