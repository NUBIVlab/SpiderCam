from torch.utils.data import DataLoader

_DATASETS = {}

def register_dataset(cls=None, *, name=None):
  """A decorator for registering dataset classes."""

  def _register(cls):
    if name is None:
      local_name = cls.__name__
    else:
      local_name = name
    if local_name in _DATASETS:
      raise ValueError(f'Already registered dataset with name: {local_name}')
    _DATASETS[local_name] = cls
    return cls

  if cls is None:
    return _register
  else:
    return _register(cls)


def get_dataset(name: str, **kwargs):
    if _DATASETS.get(name, None) is None:
        raise NameError(f"Name {name} is not defined.")
    return _DATASETS[name](**kwargs)


def get_data_loader(config):
    dataset = get_dataset(config.data.type, config=config.data)
    return DataLoader(dataset, batch_size=len(dataset), shuffle=False, num_workers=5)


from .linear_slide import *
