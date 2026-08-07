import math

import numpy as np
import torch
import torch.nn.functional as F
import torchvision.transforms.functional as TF
from torch import Tensor, nn
from torch.fft import fft2, fftshift, ifft2, ifftshift
from torchvision.transforms import Grayscale

from utils.torch import *


class EfficientGaussianBlur(nn.Module):
    def __init__(self) -> None:
        super().__init__()

        gaussian_1d = torch.tensor([1/16, 4/16, 6/16, 4/16, 1/16])
        gaussian_1d = gaussian_1d / gaussian_1d.sum()
        gaussian_2d = torch.outer(gaussian_1d, gaussian_1d).unsqueeze(0).unsqueeze(0)
        self.register_buffer('gaussian_kernel', gaussian_2d)

    def forward(self, x: Tensor) -> Tensor:
        output = F.conv2d(x, self.gaussian_kernel, padding='same')
        return output


class AntiAliasingDownsample(nn.Module):
    def __init__(self, factor: int=2):
        super().__init__()
        self.gaussian_blur = EfficientGaussianBlur()
        self.average_pool = nn.AvgPool2d(kernel_size=factor, stride=factor)
        
    def forward(self, x: Tensor) -> Tensor:
        return self.average_pool(self.gaussian_blur(x))


class GaussianLaplacianPyramid(nn.Module):
    def __init__(self, n_scales: int, factor: int=2):
        super().__init__()
        self.n_scales = n_scales
        self.factor = factor
        self.downsamples = nn.ModuleList([AntiAliasingDownsample(factor) for _ in range(n_scales)])
        self.upsamples = nn.ModuleList([nn.Upsample(scale_factor=factor, mode='bilinear', align_corners=False) for _ in range(n_scales)])

    def forward(self, x: Tensor) -> list[Tensor]:
        gaussian_pyramid = [x]
        for downsample in self.downsamples:
            gaussian_pyramid.append(downsample(gaussian_pyramid[-1]))
            
        laplacian_pyramid = [gaussian_pyramid[i] - self.upsamples[i](gaussian_pyramid[i+1]) for i in range(self.n_scales)]
        
        return gaussian_pyramid[:-1], laplacian_pyramid


class FFTConvolution(nn.Module):
    def __init__(self):
        super().__init__()
        
    def forward(self, x: Tensor, kernel: Tensor) -> Tensor:
        kernel = kernel[0:1,0:1,...]
        pad_1 = x.shape[2]-kernel.shape[2]//2
        pad_2 = x.shape[2]-kernel.shape[2]-pad_1
        pad_3 = x.shape[3]-kernel.shape[3]//2
        pad_4 = x.shape[3]-kernel.shape[3]-pad_3
        pad_shape = (pad_1, pad_2, pad_3, pad_4)
        kernel = F.pad(kernel, pad_shape)
        return ifft2(fft2(x) * fft2(kernel)).real


class Laplacian(nn.Module):
    def __init__(self):
        super().__init__()
        laplacian_kernel = torch.tensor([
            [0, -1, 0],
            [-1, 4, -1],
            [0, -1, 0]
        ], dtype=torch.float32).unsqueeze(0).unsqueeze(0)
        self.register_buffer('laplacian_kernel', laplacian_kernel)

    def forward(self, x: Tensor) -> Tensor:
        return F.conv2d(x, self.laplacian_kernel, padding='same')


class DxDy(nn.Module):
    def __init__(self):
        super().__init__()
        self.register_buffer('dx_kernel', torch.tensor([[0.0, 0.0, 0.0], [-1.0, 0.0, 1.0], [0.0, 0.0, 0.0]]).unsqueeze(0).unsqueeze(0))
        self.register_buffer('dy_kernel', torch.tensor([[0.0, -1.0, 0.0], [0.0, 0.0, 0.0], [0.0, 1.0, 0.0]]).unsqueeze(0).unsqueeze(0))
        
    def forward(self, x: Tensor) -> Tensor:
        dx = F.conv2d(x, self.dx_kernel, padding='same')
        dy = F.conv2d(x, self.dy_kernel, padding='same')
        return torch.cat([x, dx, dy], dim=-3)
  

class RingOpticalParameter(nn.Module):
    def __init__(self, shape: tuple, center: tuple, n: int, init: float=1.0):
        super().__init__()
        self.x = nn.Parameter(torch.ones(n, 1, 1) * init, requires_grad=True)
        
        X, Y = get_pixel_coords(shape, center)
        R = torch.sqrt(X**2 + Y**2)
        r_list = np.linspace(0.0, R.max(), n+1)
        # print(r_list**2)
        self.register_buffer('masks', torch.stack([get_ring_mask(X, Y, r_list[idx], r_list[idx+1]) for idx in range(n)]))
      
    def forward(self) -> Tensor:
        return (self.masks * self.x).sum(dim=0)


class RadialOpticalParameter(nn.Module):
    def __init__(self, shape: tuple, center: tuple, n_orders: int):
        super().__init__()
        self.n_orders = n_orders
        self.coeffs = nn.Parameter(torch.ones(n_orders,), requires_grad=True)
        mgrid = get_mgrid(shape, center)
        self.register_buffer('r', torch.sqrt(mgrid[..., 0]**2 + mgrid[..., 1]**2).view(shape))
      
    def forward(self) -> Tensor:
        return torch.stack([self.coeffs[i] * (self.r ** i) for i in range(self.n_orders)], dim=0).sum(dim=0)


class PixelGridOpticalParameter(nn.Module):
    def __init__(self, shape: tuple, init: float):
        super().__init__()
        self.x = nn.Parameter(torch.ones(shape), requires_grad=True)
      
    def forward(self) -> Tensor:
        return self.x 


class PolynomialOpticalParameter(nn.Module):
    def __init__(self, shape: tuple, n_orders: int):
        super().__init__()
        self.n_orders = n_orders
        self.coeffs = nn.Parameter(torch.ones(n_orders,), requires_grad=True)
        mgrid = get_mgrid(shape)
        mgrid[...,1] *= shape[1] / shape[0]
        self.register_buffer('x', mgrid[...,0].view(shape))
        self.register_buffer('y', mgrid[...,1].view(shape))
      
        # Pre-calculate the exponents for each term in the polynomial, e.g., (x^i, y^j)
        exponents = []
        for order in range(n_orders):  # Total degree from 0 to n_orders-1
            for i in range(order + 1):
                j = order - i
                exponents.append((i, j))
        
        # `exponents` will be [(0,0), (1,0), (0,1), (2,0), (1,1), (0,2), ...]
        self.n_coeffs = len(exponents)
        exponents_tensor = torch.tensor(exponents, dtype=torch.float32)
        self.register_buffer('exponents', exponents_tensor)
        
        # Initialize the learnable polynomial coefficients
        self.coeffs = nn.Parameter(torch.zeros(self.n_coeffs), requires_grad=True)
      
    def forward(self) -> Tensor:
        """
        Computes the 2D polynomial map.

        Returns:
            Tensor: A 2D tensor of shape (H, W) representing the polynomial map.
        """
        # Get coordinate and parameter tensors
        # x, y shape: [H, W]
        # coeffs shape: [n_coeffs]
        # exponents shape: [n_coeffs, 2]
        x = self.x
        y = self.y
        coeffs = self.coeffs
        exponents = self.exponents

        # Use broadcasting to compute all basis functions (x^i * y^j) efficiently
        # Reshape tensors to enable broadcasting:
        # x, y -> [1, H, W]
        # coeffs -> [n_coeffs, 1, 1]
        # exponents_x, exponents_y -> [n_coeffs, 1, 1]
        x = x.unsqueeze(0)
        y = y.unsqueeze(0)
        coeffs = coeffs.view(-1, 1, 1)
        exponents_x = exponents[:, 0].view(-1, 1, 1)
        exponents_y = exponents[:, 1].view(-1, 1, 1)
        
        # This creates a tensor of shape [n_coeffs, H, W], where each
        # slice along the first dimension is one basis function (x^i * y^j).
        basis_functions = (x ** exponents_x) * (y ** exponents_y)
        
        # Compute the weighted sum of the basis functions using the coefficients
        # The result is a sum over the 'n_coeffs' dimension.
        output = torch.sum(coeffs * basis_functions, dim=0)
        
        return output


class FocalSplit(nn.Module):
    def __init__(self, config) -> None:
        super().__init__()
        self.img_shape = (config.data.mask[1] - config.data.mask[0], config.data.mask[3] - config.data.mask[2])
        self.img_center = config.data.center
        self.model_config = config.model
        self.n_channels = self.model_config.n_scales * (3 if self.model_config.dxdy else 1)
        
        self.laplacian = Laplacian()
        self.fft_convolution = FFTConvolution()
        
        if self.model_config.box_filter_background:
            self.register_buffer('box_filter_background', torch.ones((1, 1, self.model_config.box_filter_background, self.model_config.box_filter_background)) / self.model_config.box_filter_background ** 2)
        
        if self.model_config.gaussian_denoise:
            self.gaussian_denoise = EfficientGaussianBlur()
            
        if self.model_config.box_denoise:
            self.register_buffer('box_denoise', torch.ones((self.n_channels, 1, self.model_config.box_denoise, self.model_config.box_denoise)) / self.model_config.box_denoise ** 2)
        
        if self.model_config.const == 'universal':
            self.A_list = nn.ParameterList([nn.Parameter(torch.ones(1, ) * 2.3, requires_grad=True) for _ in range(self.model_config.n_scales)])
            self.B_list = nn.ParameterList([nn.Parameter(torch.ones(1, ) * 1.6, requires_grad=True) for _ in range(self.model_config.n_scales)])
        elif self.model_config.const == 'rings':
            self.A_list = nn.ParameterList([RingOpticalParameter(shape=(self.img_shape[0]//2**idx, self.img_shape[1]//2**idx), center=(self.img_center[0]//2**idx, self.img_center[1]//2**idx), n=self.model_config.n_rings, init=1.5) for idx in range(self.model_config.n_scales)])
            self.B_list = nn.ParameterList([RingOpticalParameter(shape=(self.img_shape[0]//2**idx, self.img_shape[1]//2**idx), center=(self.img_center[0]//2**idx, self.img_center[1]//2**idx), n=self.model_config.n_rings, init=1.5) for idx in range(self.model_config.n_scales)])
        elif self.model_config.const == 'radial':
            self.A_list = nn.ParameterList([RadialOpticalParameter(shape=(self.img_shape[0]//2**idx, self.img_shape[1]//2**idx), center=(self.img_center[0]//2**idx, self.img_center[1]//2**idx), n_orders=self.model_config.n_orders) for idx in range(self.model_config.n_scales)])
            self.B_list = nn.ParameterList([RadialOpticalParameter(shape=(self.img_shape[0]//2**idx, self.img_shape[1]//2**idx), center=(self.img_center[0]//2**idx, self.img_center[1]//2**idx), n_orders=self.model_config.n_orders) for idx in range(self.model_config.n_scales)])
        elif self.model_config.const == 'pixel-grid': 
            self.A_list = nn.ParameterList([PixelGridOpticalParameter(shape=(self.img_shape[0]//2**idx, self.img_shape[1]//2**idx), init=2.0) for idx in range(self.model_config.n_scales)])
            self.B_list = nn.ParameterList([PixelGridOpticalParameter(shape=(self.img_shape[0]//2**idx, self.img_shape[1]//2**idx), init=1.5) for idx in range(self.model_config.n_scales)])
        elif self.model_config.const == 'polynomial':
            self.A_list = nn.ParameterList([PolynomialOpticalParameter(shape=(self.img_shape[0]//2**idx, self.img_shape[1]//2**idx), n_orders=self.model_config.n_orders) for idx in range(self.model_config.n_scales)])
            self.B_list = nn.ParameterList([PolynomialOpticalParameter(shape=(self.img_shape[0]//2**idx, self.img_shape[1]//2**idx), n_orders=self.model_config.n_orders) for idx in range(self.model_config.n_scales)])
        else:
            raise ValueError(f'Constant mode ({self.model_config.const}) is not supported.')
            
        self.omega = nn.Parameter(torch.zeros(1, self.n_channels, 1, 1), requires_grad=True)
        # self.register_buffer('omega', torch.tensor([0.0, 0.0, 0.0, 1.0, 1.0, 1.0]).view(1, self.n_channels, 1, 1))

        self.pyramid = GaussianLaplacianPyramid(n_scales=self.model_config.n_scales, factor=2)
        self.upsamples = nn.ModuleList([nn.Upsample(scale_factor=2**idx, mode='bilinear', align_corners=False) for idx in range(self.model_config.n_scales)])
        
        if self.model_config.dxdy:
            self.dxdy = DxDy()

    def forward(self, I0: Tensor, I1: Tensor) -> Tensor:
        
        # Reduce the non-uniform background lighting.
        if self.model_config.box_filter_background:
            if self.model_config.fft:
                I0 = I0 - self.fft_convolution(I0, self.box_filter_background)
                I1 = I1 - self.fft_convolution(I1, self.box_filter_background)
            else:
                I0 = I0 - F.conv2d(I0, self.box_filter_background, padding="same")
                I1 = I1 - F.conv2d(I1, self.box_filter_background, padding="same")

        # Suppress noise with gaussian blur.
        if self.model_config.gaussian_denoise:
            I0 = self.gaussian_denoise(I0)
            I1 = self.gaussian_denoise(I1)
            
        I1s, I1_laplacians = self.pyramid(I1)
        I0s, I0_laplacians = self.pyramid(I0)
        
        V_list, W_list, laplacian_I_list, Is_list = [], [], [], []
        for I1, I1_laplacian, I0, I0_laplacian, A, B, upsample in zip(I1s, I1_laplacians, I0s, I0_laplacians, self.A_list, self.B_list, self.upsamples):
            if self.model_config.const == 'universal':
                pass
            else:
                A, B = A.forward(), B.forward()
            laplacian_I = (I1_laplacian + I0_laplacian) / 2
            Is = (I0 - I1) / 2
            V = upsample(laplacian_I * A)
            W = upsample(laplacian_I * A * B - Is)
            V_list.append(self.dxdy(V) if self.model_config.dxdy else V)
            W_list.append(self.dxdy(W) if self.model_config.dxdy else W)
            laplacian_I_list.append(self.dxdy(upsample(laplacian_I)) if self.model_config.dxdy else upsample(laplacian_I))
            Is_list.append(self.dxdy(upsample(Is)) if self.model_config.dxdy else upsample(Is))

        V = torch.cat(V_list, dim=-3)
        W = torch.cat(W_list, dim=-3)
        laplacian_I = torch.cat(laplacian_I_list, dim=-3)
        Is = torch.cat(Is_list, dim=-3)
        
        numerator = V * W
        denominator = W ** 2

        if self.model_config.box_denoise:
            if self.model_config.fft:
                numerator = self.fft_convolution(numerator, self.box_denoise)
                denominator = self.fft_convolution(denominator, self.box_denoise)
            else:
                numerator = F.conv2d(numerator, self.box_denoise, padding="same", groups=self.n_channels)
                denominator = F.conv2d(denominator, self.box_denoise, padding="same", groups=self.n_channels)

        z_preds = numerator / (denominator + 1e-7) # Avoid division by zero.
        
        if self.model_config.conf == 'VW':
            confs = V*W
        elif self.model_config.conf == 'W2':
            confs = W**2
        elif self.model_config.conf == 'V':
            confs = V.abs()
        elif self.model_config.conf == 'W':
            confs = W.abs()
        else:
            raise ValueError(f"Confidence mode ({self.model_config.conf}) is not supported.")
        
        z_pred1, conf1 = None, None
        if self.model_config.mode == 'separate':  
            z_pred = (z_preds * F.softmax(confs * F.softplus(self.omega), dim=1)).sum(dim=1, keepdim=True)
            conf = (confs * F.softmax(confs * F.softplus(self.omega), dim=1)).sum(dim=1, keepdim=True)
        elif self.model_config.mode == 'joint':
            if self.model_config.n_scales == 2:
                numerator1 = (numerator[:,0:3] * F.softmax(self.omega[:,0:3], dim=1)).sum(dim=1, keepdim=True)
                denominator1 = (denominator[:,0:3] * F.softmax(self.omega[:,0:3], dim=1)).sum(dim=1, keepdim=True)
                z_pred1 = numerator1 / (denominator1 + 1e-17)
                conf1 = numerator1
            
            numerator = (numerator * F.softmax(self.omega, dim=1)).sum(dim=1, keepdim=True)
            denominator = (denominator * F.softmax(self.omega, dim=1)).sum(dim=1, keepdim=True)
            z_pred = numerator / (denominator + 1e-17)
            if self.model_config.conf == 'VW':
                conf = numerator
            elif self.model_config.conf == 'W2':
                conf = denominator
            elif self.model_config.conf == 'V':
                conf = (V.abs() * F.softmax(self.omega, dim=1)).sum(dim=1, keepdim=True)
            elif self.model_config.conf == 'W':
                conf = (W.abs() * F.softmax(self.omega, dim=1)).sum(dim=1, keepdim=True)
            else:
                raise ValueError(f"Confidence mode ({self.model_config.conf}) is not supported.")
        else:
            raise ValueError(f"Mode ({self.model_config.mode}) is not supported.")

        # # Add bias.
        # bias = (2 * F.sigmoid(self.bias) - 1) * 0.0
        # # bias = self.bias()
        # z_pred = z_pred + bias
        # z_preds = z_preds + bias
        
        outputs = {
            'z_pred': z_pred,
            'conf': conf,
            'z_preds': z_preds,
            'confs': confs,
            'VW': numerator,
            'W2': denominator,
        }
        
        return z_pred, conf, z_pred1, conf1, outputs
    
    # def get_constants(self):
    #     constants = []
    #     for A, B in zip(self.A_list, self.B_list):
    #         if self.model_config.const == 'universal':
    #             A, B = torch.ones(self.img_shape[0], self.img_shape[1], device=A.device) * A, torch.ones(self.img_shape[0], self.img_shape[1], device=B.device) * B
    #         else:
    #             A, B = A.forward(), B.forward()
    #         constants.append((A.detach().cpu().numpy(), B.detach().cpu().numpy()))
    #     return constants
    