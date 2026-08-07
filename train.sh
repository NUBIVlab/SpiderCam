data=11-06
group=texture1_half

# Foacl split.
python train_focal_split.py data=$data data.group=$group \
                                 model.n_scales=2 model.dxdy=true model.mode=separate model.const=universal model.conf=W \
                                 'optim.z_min=[0.3, 0.3]' 'optim.z_max=[1.1, 1.1]'

# Condifdence ablation.
for conf in VW W2 V W; do
    python train_focal_split.py data=$data data.group=$group \
                                     model.conf=$conf
done

# Ours.
for n_scales in 2 1; do
    for dxdy in true false; do
        for n_rings in 16; do
            python train_focal_split.py data=$data data.group=$group \
                                             model.n_scales=$n_scales model.const=rings model.n_rings=$n_rings model.dxdy=$dxdy
        done

        # Ours without spatial variation.
        python train_focal_split.py data=$data data.group=$group \
                                         model.n_scales=$n_scales model.const=universal model.dxdy=$dxdy
    done
done



# for sparsity in 0.99 0.95 0.9 0.8 0.5 0.0; do
#     python train_focal_split.py optim.sparsity=$sparsity
# done

# for box_denoise in 11 9 7 5 3 false; do
#     python train_focal_split.py model.box_denoise=$box_denoise
# done
