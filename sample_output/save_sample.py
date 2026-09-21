"""Generates one real motion sample and saves the raw 263-dim HumanML3D pose
tensor to .npy, so Gemini has an actual output file to inspect/work from
instead of just a shape description. Reuses the exact model-loading pattern
already confirmed working in spike_generate.py."""
from types import SimpleNamespace

import clip
import numpy as np
import torch

import models.t2m_trans as trans
import models.vqvae as vqvae

device = torch.device("cuda")

args = SimpleNamespace(
    dataname="t2m", batch_size=128, fps=[20], seq_len=64, total_iter=100000,
    warm_up_iter=1000, lr=2e-4, lr_scheduler=[60000], gamma=0.05,
    weight_decay=1e-6, decay_option="all", optimizer="adamw", code_dim=512,
    nb_code=512, mu=0.99, down_t=2, stride_t=2, width=512, depth=3,
    dilation_growth_rate=3, output_emb_width=512, vq_act="relu",
    block_size=51, embed_dim_gpt=1024, clip_dim=512, num_layers=9,
    n_head_gpt=8, ff_rate=4, drop_out_rate=0.1, quantizer="ema_reset",
    quantbeta=1.0, resume_pth=None, resume_trans=None,
    out_dir="output_GPT_Final/", exp_name="exp_debug", vq_name="exp_debug",
    print_iter=200, eval_iter=5000, seed=123, if_maxtest=False, pkeep=1.0,
)

clip_model, _ = clip.load("ViT-B/32", device=device, jit=False)
clip.model.convert_weights(clip_model)
clip_model.eval()
for p in clip_model.parameters():
    p.requires_grad = False

net = vqvae.HumanVQVAE(
    args, args.nb_code, args.code_dim, args.output_emb_width,
    args.down_t, args.stride_t, args.width, args.depth, args.dilation_growth_rate,
)
trans_encoder = trans.Text2Motion_Transformer(
    num_vq=args.nb_code, embed_dim=args.embed_dim_gpt, clip_dim=args.clip_dim,
    block_size=args.block_size, num_layers=args.num_layers, n_head=args.n_head_gpt,
    drop_out_rate=args.drop_out_rate, fc_rate=args.ff_rate,
)

vq_ckpt = torch.load("pretrained/VQVAE/net_last.pth", map_location="cpu", weights_only=False)
net.load_state_dict(vq_ckpt["net"], strict=True)
net.eval().cuda()

trans_ckpt = torch.load(
    "pretrained/VQTransformer_corruption05/net_best_fid.pth", map_location="cpu", weights_only=False
)
trans_encoder.load_state_dict(trans_ckpt["trans"], strict=True)
trans_encoder.eval().cuda()

prompt = "a person walks forward and waves with their right hand"
text = clip.tokenize([prompt], truncate=True).to(device)
with torch.no_grad():
    feat_clip_text = clip_model.encode_text(text).float()
    index_motion = trans_encoder.sample(feat_clip_text[0:1], False)
    pred_pose = net.forward_decoder(index_motion)

pose_np = pred_pose[0].cpu().numpy()  # (num_frames, 263)
np.save("sample_output.npy", pose_np)
with open("sample_output_prompt.txt", "w") as f:
    f.write(prompt)

print(f"Saved sample_output.npy, shape={pose_np.shape}, dtype={pose_np.dtype}")
print(f"Prompt: {prompt}")
