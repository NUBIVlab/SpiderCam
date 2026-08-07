import torch

DEVICE = torch.device('cuda' if torch.cuda.is_available() else 'cpu')

def calculate_depth(I_0, I_1, model):
    I_0 = torch.from_numpy(I_0).unsqueeze(0).unsqueeze(0).float().to(DEVICE) / 255.0
    I_1 = torch.from_numpy(I_1).unsqueeze(0).unsqueeze(0).float().to(DEVICE) / 255.0
    
    z_pred1 = torch.ones_like(I_0) * torch.nan
    conf1 = torch.ones_like(I_1) * torch.nan

    I_0 = I_0[..., 17:337, 5:325]
    I_1 = I_1[..., 17:337, 5:325]
    with torch.no_grad():
        z_pred, conf, _ = model(I_0, I_1)
    
    z_pred[conf < 10e-4] = torch.nan
    z_pred1[...,17:337, 5:325] = z_pred
    conf1[...,17:337, 5:325] = conf
    
    
    z_pred = z_pred1
    conf = conf1
    return z_pred.squeeze().detach().cpu().numpy(), conf.squeeze().detach().cpu().numpy()