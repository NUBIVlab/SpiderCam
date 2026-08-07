import logging
import math
import os
import shutil
from time import time

import hydra
import torch
from omegaconf import OmegaConf
from torch import nn
from torch.optim import Adam, AdamW
from tqdm import tqdm

from datasets import get_data_loader
from models import FilteredDepthLoss, FocalSplit
from utils.name import *
from utils.torch import *
from utils.visualization import *

# torch.set_default_dtype(torch.float16)

RESULTS_PATH = './results/'
DEVICE = torch.device('cuda' if torch.cuda.is_available() else 'cpu')


@hydra.main(version_base="1.3", config_path="configs", config_name="train")
def train_focal_split(config):
    logger = logging.getLogger('Focal Split Calibration')

    name_data, name_model, name_optim = get_name_data(config.data), get_name_model(config.model), get_name_optim(config.optim)
    model_save_path = os.path.join(RESULTS_PATH, name_data, '_'.join([name_model, name_optim]))
    if os.path.exists(model_save_path):
        shutil.rmtree(model_save_path)
    os.makedirs(os.path.join(model_save_path, 'checkpoints'), exist_ok=True)
    
    if torch.cuda.is_available():
        device_count, device_name = torch.cuda.device_count(), torch.cuda.get_device_name()
    else:
        device_count, device_name = 1, 'cpu'
    
    data_loader = get_data_loader(config)
    img_plus, img_minus, z_true = next(iter(data_loader))

    # Define the model, loss function, and optimizer.
    model = FocalSplit(config).to(DEVICE)
    n_params = get_total_params(model)
    logger.info(' Total number of parameters: %d.', n_params)
    
    loss_fn = FilteredDepthLoss(config).to(DEVICE)
    optimizer = AdamW(model.parameters(), lr=config.optim.lr, weight_decay=config.optim.weight_decay)

    # Load checkpoint if specified.
    pretrained_epochs = config.pretrained_epochs
    if config.pretrained_epochs > 0:
        try:
            checkpoint = torch.load(os.path.join(model_save_path, 'checkpoints', f'checkpoint_{pretrained_epochs}epochs.pth'), weights_only=True)
            model.load_state_dict(checkpoint['model_state_dict'])
            optimizer.load_state_dict(checkpoint['optimizer_state_dict'])
            model.load_state_dict(checkpoint['model_state_dict'])
            loss_list = checkpoint['loss_list']
            loss_min = checkpoint['loss_min']
            epoch_min = checkpoint['epoch_min']
            if 'torch_rng_state' in checkpoint:
                torch.set_rng_state(checkpoint['torch_rng_state'])
            if 'cuda_rng_state' in checkpoint and torch.cuda.is_available():
                torch.cuda.set_rng_state(checkpoint['cuda_rng_state'])
            time_pretrain = checkpoint['time']
            logger.info(' Successfully loaded checkpoint from %s epochs.', pretrained_epochs)
        except:
            pretrained_epochs = 0
            logger.warning(' Checkpoint not found. Starting training from scratch.')
            
    if pretrained_epochs == 0:
        loss_list = []
        loss_min, epoch_min = math.inf, 0
        time_pretrain = 0.0
    
    # Training loop.
    t_start = time() - time_pretrain
    for epoch in range(pretrained_epochs+1, pretrained_epochs+config.n_epochs+1):
        model.train()
        z_true_list, z_pred_list, conf_list = [], [], []
        train_loss = 0.0
        for idx, (img_plus, img_minus, z_true) in enumerate(data_loader):
            img_plus, img_minus = img_plus.to(DEVICE), img_minus.to(DEVICE)

            optimizer.zero_grad()
            z_pred, conf, z_pred1, conf1, outputs = model(img_plus, img_minus)
            # print(z_pred.shape, z_pred1.shape, conf.shape, conf1.shape)

            z_true = z_true.unsqueeze(-1).unsqueeze(-1).repeat(1, 1, z_pred.shape[-2], z_pred.shape[-1]).to(DEVICE)
            loss = loss_fn(z_pred[...,11:-11,11:-11], z_true[...,11:-11,11:-11], conf[...,11:-11,11:-11])
            # if z_pred1 is not None:
            #     loss1 = loss_fn(z_pred1[...,11:-11,11:-11], z_true[...,11:-11,11:-11], conf1[...,11:-11,11:-11])
            #     loss = loss + loss1
            
            train_loss += loss.item()
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), config.optim.clip)
            optimizer.step()
            
            z_true_list.append(z_true.detach().cpu())
            z_pred_list.append(z_pred.detach().cpu())
            conf_list.append(conf.detach().cpu())
            
        loss_list.append(train_loss / len(data_loader))
        
        if loss_min > train_loss:
            loss_min = train_loss
            epoch_min = epoch

        if epoch % config.eval_interval == 0 or epoch == config.n_epochs:
            logger.info(f' [Epoch {epoch}/{config.n_epochs}]   loss={loss_list[-1]:.4e}   time={(time()-t_start)/3600:.3f}h')
            
            # Plot loss curve.
            plot_loss_curve(model_save_path, loss_list, None, epoch_min)

        
        if epoch % 100 == 0:
            # Save checkpoints.
            checkpoint = {
                'config': OmegaConf.to_container(config, resolve=True),
                'epoch': epoch,
                'model_state_dict': model.state_dict(),
                'optimizer_state_dict': optimizer.state_dict(),
                'loss_list': loss_list,
                'loss_min': loss_min,
                'epoch_min': epoch_min,
                'gpu': device_name,
                'device_count': device_count,
                'gpu_memory': torch.cuda.max_memory_allocated() if torch.cuda.is_available() else None,
                'time': time() - t_start,
                'torch_rng_state': torch.get_rng_state(),
                'cuda_rng_state': torch.cuda.get_rng_state() if torch.cuda.is_available() else None,
            }
            torch.save(checkpoint, os.path.join(model_save_path, 'checkpoints', f'checkpoint_{epoch}epochs.pth'))

            # Visualization and saving results.
            z_true_list = torch.cat(z_true_list, dim=0)
            z_pred_list = torch.cat(z_pred_list, dim=0)
            conf_list = torch.cat(conf_list, dim=0)
            
            z_pred = z_pred.detach().cpu().numpy()
            conf = conf.detach().cpu().numpy()
            z_true = z_true.detach().cpu().numpy()
            z_true_list = z_true_list.detach().cpu().numpy()
            z_pred_list = z_pred_list.detach().cpu().numpy()
            conf_list = conf_list.detach().cpu().numpy()
            
            plot_error_sparsity(results_path=model_save_path, z_true=z_true[...,11:-11,11:-11], z_pred=z_pred[...,11:-11,11:-11], conf=conf[...,11:-11,11:-11])
            for sparsity in [0.0, 0.05, 0.8, 0.9, 0.95, 0.99]:
                plot_error_depth(
                    results_path=model_save_path, 
                    z_true=z_true[...,11:-11,11:-11], 
                    z_pred=z_pred[...,11:-11,11:-11], 
                    conf=conf[...,11:-11,11:-11],
                    sparsity=sparsity
                )
            
            logger.info(f'Checkpoint and results saved to {model_save_path}.')
            
            # Save model outputs.
            np.save(os.path.join(model_save_path, 'z_true.npy'), z_true)
            np.save(os.path.join(model_save_path, 'z_pred.npy'), z_pred)
            np.save(os.path.join(model_save_path, 'conf.npy'), conf)
            np.save(os.path.join(model_save_path, 'z_preds.npy'), outputs['z_preds'].detach().cpu().numpy())
            np.save(os.path.join(model_save_path, 'confs.npy'), outputs['confs'].detach().cpu().numpy())
            try:
                np.save(os.path.join(model_save_path, 'V.npy'), outputs['V'].detach().cpu().numpy())
                np.save(os.path.join(model_save_path, 'W.npy'), outputs['W'].detach().cpu().numpy())
                np.save(os.path.join(model_save_path, 'laplacian_I.npy'), outputs['laplacian_I'].detach().cpu().numpy())
                np.save(os.path.join(model_save_path, 'Is.npy'), outputs['Is'].detach().cpu().numpy())
            except:
                pass

    # Plot heatmaps.
    plot_heat_map(results_path=model_save_path, z_true=z_true_list[...,11:-11,11:-11], z_pred=z_pred_list[...,11:-11,11:-11], conf=conf_list[...,11:-11,11:-11], n_bins=z_true_list.shape[0])
    
    # Plot depth maps.
    for idx in tqdm(range(z_true_list.shape[0]), desc='Plotting depth maps'):
        z_true = z_true_list[idx, 0]
        z_pred = z_pred_list[idx, 0]
        conf = conf_list[idx, 0]
        plot_depth_map(results_path=model_save_path, z_true=z_true[...,11:-11,11:-11], z_pred=z_pred[...,11:-11,11:-11], conf=conf[...,11:-11,11:-11], working_range=(z_true_list.min(), z_true_list.max()))

    logger.info(f' Results saved to {model_save_path}.')

if __name__ == '__main__':
    train_focal_split()