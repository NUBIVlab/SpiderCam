import os

import cv2
import torch
from torch.utils.data import Dataset
from torchvision.transforms import functional as TF

from . import get_dataset, register_dataset


@register_dataset(name='linear_slide')
class LinearSlideDataset(Dataset): 
    def __init__(self, config):
        self.config = config
        self.files = os.listdir(os.path.join(self.config.data_path, self.config.group))
        # self.n_samples = len(self.files) // 2
        self.n_samples = config.frame_range[1] - config.frame_range[0]
        self.file_name = self.files[0].split('_')[0]
    
    def __len__(self):
        return self.n_samples

    def get_depth(self, idx: int) -> float:
        return (idx * self.config.step_size + self.config.offset) * 0.0254

    def crop(self, img):
        if self.config.mask is not None and self.config.crop:
            return img[:, self.config.mask[0]:self.config.mask[1], self.config.mask[2]:self.config.mask[3]]
        else:
            return img
        
    def select_channel(self, img):
        if self.config.channel == 'gray':
            img = TF.rgb_to_grayscale(img)
        elif self.config.channel == 'red':
            img = img[..., 0:1, :, :]
        elif self.config.channel == 'green':
            img = img[..., 1:2, :, :]
        elif self.config.channel == 'blue':
            img = img[..., 2:3, :, :]
        else:
            raise ValueError(f'Channel {self.channel} is not supported. Choose from "gray", "red", "green", or "blue".')
        return img
    
    def __getitem__(self, idx):
        idx += self.config.frame_range[0]
        file_name = self.file_name if idx == 0 else f"{self.file_name}_{idx-1}"
        img_plus = torch.from_numpy(cv2.imread(os.path.join(self.config.data_path, self.config.group, f'{file_name}_camera0.png'))).permute(2, 0, 1).float() / 256.0
        img_minus = torch.from_numpy(cv2.imread(os.path.join(self.config.data_path, self.config.group, f'{file_name}_camera1.png'))).permute(2, 0, 1).float() / 256.0
        depth = torch.ones(1) * self.get_depth(idx)
        return self.crop(self.select_channel(img_plus)), self.crop(self.select_channel(img_minus)), depth


@register_dataset(name='linear_slide_new')
class LinearSlideDatasetNew(Dataset): 
    def __init__(self, config):
        self.config = config
        self.files = os.listdir(os.path.join(self.config.data_path, self.config.group))
        self.files.sort()
        # self.n_samples = len(self.files) // 2
        self.n_samples = config.frame_range[1] - config.frame_range[0]
        
    
    def __len__(self):
        return self.n_samples

    def get_depth(self, idx: int) -> float:
        return idx * self.config.step_size + self.config.offset

    def crop(self, img):
        if self.config.mask is not None and self.config.crop:
            return img[:, self.config.mask[0]:self.config.mask[1], self.config.mask[2]:self.config.mask[3]]
        else:
            return img
        
    def select_channel(self, img):
        if self.config.channel == 'gray':
            img = TF.rgb_to_grayscale(img)
        elif self.config.channel == 'red':
            img = img[..., 0:1, :, :]
        elif self.config.channel == 'green':
            img = img[..., 1:2, :, :]
        elif self.config.channel == 'blue':
            img = img[..., 2:3, :, :]
        else:
            raise ValueError(f'Channel {self.channel} is not supported. Choose from "gray", "red", "green", or "blue".')
        return img
    
    def __getitem__(self, idx):
        idx += self.config.frame_range[0]
        img_plus = torch.from_numpy(cv2.imread(os.path.join(self.config.data_path, self.config.group, f'cam_1_500_480_{idx}.png'))).permute(2, 0, 1).float() / 256.0
        img_minus = torch.from_numpy(cv2.imread(os.path.join(self.config.data_path, self.config.group, f'cam_0_500_480_{idx}.png'))).permute(2, 0, 1).float() / 256.0
        depth = torch.ones(1) * self.get_depth(idx)
        return self.crop(self.select_channel(img_plus)), self.crop(self.select_channel(img_minus)), depth
