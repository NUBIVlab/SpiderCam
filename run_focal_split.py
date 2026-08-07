import logging
import os
from time import time

import hydra
import numpy as np
import torch
from torch.nn import functional as F
from tqdm import tqdm

from datasets import get_data_loader
from models import FilteredDepthLoss, FocalSplit
from utils.dataio import *
from utils.metrics import *
from utils.name import *
from utils.torch import *
from utils.visualization import *

RESULTS_PATH = './results/'
DEVICE = torch.device('cuda' if torch.cuda.is_available() else 'cpu')


@hydra.main(version_base="1.3", config_path="configs", config_name="run")
def run_focal_split(config):
    logger = logging.getLogger('Focal Split Inference')

    name_data, name_model, name_optim = get_name_data(config.data), get_name_model(config.model), get_name_optim(config.optim)
    result_path = os.path.join(RESULTS_PATH, name_data, '_'.join([name_model, name_optim]))
    os.makedirs(result_path, exist_ok=True)
    
    device_count, device_name = torch.cuda.device_count(), torch.cuda.get_device_name()
    
    data_loader = get_data_loader(config)
    img_plus, img_minus, z_true = next(iter(data_loader))
    
    # Define the model, loss function, and optimizer.
    model = FocalSplit(config).to(DEVICE)
    n_params = get_total_params(model)
    logger.info(' Total number of parameters: %d.', n_params)
    model.eval()
    
    checkpoint = torch.load(os.path.join(result_path, 'checkpoints', f'checkpoint_{config.n_epochs}epochs.pth'), weights_only=True)
    model.load_state_dict(checkpoint['model_state_dict'])
    logger.info(f'Loaded model from {os.path.join(result_path, "checkpoints", f"checkpoint_{config.n_epochs}epochs.pth")}')
    
    # Print the learned parameters.
    for name, param in model.named_parameters():
        if param.requires_grad:
            if 'omega' in name:
                print(F.softmax(param, dim=1).flatten().detach().cpu().numpy())
            else:
                print(name, param.flatten().detach().cpu().numpy())
            print()
    
    # Model inference.
    z_true_list, z_pred_list, conf_list = [], [], []
    time_start = time()
    with torch.no_grad():
        for idx, (img_plus, img_minus, z_true) in enumerate(data_loader):
            img_plus, img_minus = img_plus.to(DEVICE), img_minus.to(DEVICE)
            z_pred, conf, outputs = model(img_plus, img_minus)
            z_true = z_true.unsqueeze(-1).unsqueeze(-1).repeat(1, 1, z_pred.shape[-2], z_pred.shape[-1]).to(DEVICE)
            z_true_list.append(z_true.detach().cpu())
            z_pred_list.append(z_pred.detach().cpu())
            conf_list.append(conf.detach().cpu())
            
        time_end = time()
        logger.info(f' Inference time: {time_end - time_start:.2f} seconds')
        
        z_true_list = torch.cat(z_true_list, dim=0)
        z_pred_list = torch.cat(z_pred_list, dim=0)
        conf_list = torch.cat(conf_list, dim=0)
        
        # Calculate loss
        log = {'sparsity': [], 'maes': [], 'mses': [], 'working_ranges': [], 'time': time_end - time_start}
        for sparsity in np.arange(0.0, 1.0, 0.1):
            log['sparsity'].append(sparsity)
            loss_fn = FilteredDepthLoss(norm='L1', sparsity=sparsity).cuda()
            log['maes'].append(loss_fn(z_pred_list[...,11:-11,11:-11], z_true_list[...,11:-11,11:-11], conf_list[...,11:-11,11:-11]).item())
            loss_fn = FilteredDepthLoss(norm='L2', sparsity=sparsity).cuda()
            log['mses'].append(loss_fn(z_pred_list[...,11:-11,11:-11], z_true_list[...,11:-11,11:-11], conf_list[...,11:-11,11:-11]).item())
            working_range = get_working_range(z_true_list[...,11:-11,11:-11], z_pred_list[...,11:-11,11:-11], conf_list[...,11:-11,11:-11], sparsity)
            log['working_ranges'].append(working_range)
            plot_error_depth(
                results_path=result_path, 
                epoch=config.n_epochs, 
                z_true=z_true_list[...,11:-11,11:-11], 
                z_pred=z_pred_list[...,11:-11,11:-11], 
                conf=conf_list[...,11:-11,11:-11],
                sparsity=sparsity
            )
    # Visualization.
    # Plot heatmaps.
    plot_heat_map(
        results_path=result_path, 
        z_true=z_true_list[...,11:-11,11:-11], 
        z_pred=z_pred_list[...,11:-11,11:-11], 
        conf=conf_list[...,11:-11,11:-11], 
        n_bins=z_true_list.shape[0]
    )

    # Plot depth maps.
    for idx in tqdm(range(z_true_list.shape[0]), desc='Plotting depth maps'):
        z_true = z_true_list[idx, 0]
        z_pred = z_pred_list[idx, 0]
        conf = conf_list[idx, 0]
        plot_depth_map(results_path=result_path, z_true=z_true[...,11:-11,11:-11], z_pred=z_pred[...,11:-11,11:-11], conf=conf[...,11:-11,11:-11], working_range=(z_true_list.min(), z_true_list.max()))

    # plot_error_sparsity(results_path=result_path, epoch=config.n_epochs, z_true=z_true_list[...,11:-11,11:-11], z_pred=z_pred_list[...,11:-11,11:-11], conf=conf_list[...,11:-11,11:-11])
    
    # # Save results.
    # np.save(os.path.join(results_path, 'z_true_list.npy'), z_true_list.numpy())
    # np.save(os.path.join(results_path, 'z_pred_list.npy'), z_pred_list.numpy())
    # np.save(os.path.join(results_path, 'conf_list.npy'), conf_list.numpy())
    
    # save_log(log=log, results_path=result_path)
    logger.info(f' Results saved to {result_path}.')



if __name__ == '__main__':
    run_focal_split()
    