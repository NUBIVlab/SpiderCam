import json
import logging
import os

import numpy as np

from utils.name import *


def save_log(log: dict, results_path: str) -> None:
    """Save log dictionary to `.json` file.

    Args:
        results_path (str): Path to results directory.
        log (dict): Log dictionary.
    """
    logger = logging.getLogger('DataIO')
    log_file = os.path.join(results_path, 'log.json')
    with open(log_file, 'w') as f:
        json.dump(log, f)
    logger.debug(' Successfully saved log to "%s".', log_file)
    
    
def load_log(log_file: str) -> dict:
    """Load log dictionary from `.json` file.

    Args:
        log_file (str): Path to log file.

    Returns:
        dict: Log dictionary.
    """
    logger = logging.getLogger('DataIO')
    with open(log_file, 'r') as f:
        log = json.load(f)
    logger.debug(' Successfully loaded log file from "%s".', log_file)
    return log


def load_results(config, result_path: str, crop: int = 0) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    name_data, name_model, name_optim = get_name_data(config.data), get_name_model(config.model), get_name_optim(config.optim)
    result_path = os.path.join(result_path, name_data, '_'.join([name_model, name_optim]))
    
    z_pred = np.load(os.path.join(result_path, 'z_pred.npy')).squeeze()
    conf = np.load(os.path.join(result_path, 'conf.npy')).squeeze()
    z_true = np.load(os.path.join(result_path, 'z_true.npy')).squeeze()
    if crop > 0:
        z_pred = z_pred[..., crop:-crop, crop:-crop]
        conf = conf[..., crop:-crop, crop:-crop]
        z_true = z_true[..., crop:-crop, crop:-crop]
    return z_pred, conf, z_true
