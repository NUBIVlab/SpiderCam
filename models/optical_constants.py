import torch
from torch import nn


class OpticalConstants(nn.Module):
    def __init__(self, mode: str, init: float):
        super().__init__()
        if config.mode == 'universal':
            self.const = nn.Parameter(torch.ones(1,), requires_grad=True)
        else:
            raise ValueError(f'Mode {config.mode} is not supported.')


    def forward(self, x):
        return self.const