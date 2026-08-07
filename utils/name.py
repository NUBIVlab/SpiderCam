import os


def get_name_data(config):
    return f'{config.name}_{config.group}_{config.channel}' + ('_cropped' if config.crop else '')
        
        
def get_name_model(config):
    name_list = [f'{config.n_scales}scales']
    if config.dxdy:
        name_list.append('dxdy')
    name_list.append(config.mode)
    if config.const == 'rings':
        name_list.append(f'{config.n_rings}rings')
    elif config.const == 'radial':
        name_list.append(f'{config.n_orders}orders')
    elif config.const in ['universal', 'pixel-grid', 'polynomial']:
        name_list.append(config.const)
    else:
        raise ValueError(f'Constant {config.const} is not supported.')
    if config.conf:
        name_list.append(f'conf={config.conf}')
    if config.box_denoise:
        name_list.append(f'{config.box_denoise}x{config.box_denoise}box')
    if config.gaussian_denoise:
        name_list.append(f'{config.gaussian_denoise}x{config.gaussian_denoise}gaussian')
    return '_'.join(name_list)



def get_name_optim(config):
    return f'{config.optimizer}_lr={config.lr}_wd={config.weight_decay}_clip={config.clip}_sparsity={config.sparsity}'